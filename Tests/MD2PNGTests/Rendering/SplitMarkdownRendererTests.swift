import AppKit
import XCTest
@testable import MD2PNG

final class SplitMarkdownRendererTests: XCTestCase {
    @MainActor
    func testSplitRendererProducesBlockAwareContiguousSnapshots() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        let markdown = (1 ... 20).map { section in
            """
            ## Section \(section)

            This paragraph gives section \(section) enough content to produce a stable block.

            - First item in section \(section)
            - Second item in section \(section)
            """
        }.joined(separator: "\n\n")

        let result = try await renderSplit(
            markdown,
            with: renderer,
            maximumSliceHeight: 500
        )
        try writeReferenceImagesIfRequested(result)

        XCTAssertGreaterThan(result.parts.count, 2)
        XCTAssertEqual(result.parts.first?.slice.y, 0)
        XCTAssertEqual(
            result.parts.last?.slice.range.upperBound,
            Int(result.contentSize.height)
        )
        XCTAssertTrue(result.parts.dropLast().contains {
            $0.slice.ending == .preferredBoundary
        })
        for (index, part) in result.parts.enumerated() {
            XCTAssertLessThanOrEqual(part.slice.height, 500)
            XCTAssertEqual(part.image.size.width, result.contentSize.width, accuracy: 1)
            XCTAssertEqual(
                part.image.size.height,
                CGFloat(part.slice.height),
                accuracy: 1
            )
            if index > 0 {
                XCTAssertEqual(
                    result.parts[index - 1].slice.range.upperBound,
                    part.slice.range.lowerBound
                )
            }
        }

        let laterSingleImage = try await render("# After split", with: renderer)
        XCTAssertGreaterThanOrEqual(laterSingleImage.size.width, 520)
        XCTAssertLessThanOrEqual(laterSingleImage.size.width, 1_120)
        XCTAssertGreaterThanOrEqual(laterSingleImage.size.height, 80)
    }

    @MainActor
    func testSplitRendererHandlesContentBeyondSingleImageLimit() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        let markdown = (1 ... 520).map { paragraph in
            "Paragraph \(paragraph): local-only tall-render validation content."
        }.joined(separator: "\n\n")

        do {
            _ = try await render(markdown, with: renderer)
            XCTFail("Expected the legacy single-image limit")
        } catch let error as AppError {
            guard case let .contentTooLarge(width, height) = error else {
                return XCTFail("Expected contentTooLarge, got \(error)")
            }
            XCTAssertLessThanOrEqual(width, MarkdownRenderer.maximumSnapshotWidth)
            XCTAssertGreaterThan(height, MarkdownRenderer.maximumSnapshotHeight)
        }

        let result = try await renderSplit(
            markdown,
            with: renderer,
            maximumSliceHeight: MarkdownRenderer.maximumSnapshotHeight
        )

        XCTAssertGreaterThan(result.contentSize.height, 16_000)
        XCTAssertGreaterThan(result.parts.count, 1)
        XCTAssertTrue(result.parts.allSatisfy {
            $0.slice.height <= MarkdownRenderer.maximumSnapshotHeight
        })
        XCTAssertEqual(
            result.parts.map(\.slice.height).reduce(0, +),
            Int(result.contentSize.height)
        )
    }

    @MainActor
    func testDOMGeometryProtectsCodeMermaidAndIndividualTableRows() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        let markdown = """
        # Protected blocks

        Introductory content before the protected elements.

        ```swift
        struct Release {
            let version: String
            let date: String
        }

        let current = Release(
            version: "0.10.0",
            date: "2026-08-18"
        )
        ```

        | Version | State | Notes |
        | --- | --- | --- |
        | 0.8 | Shipped | Diagnostics |
        | 0.9 | Shipped | Updates |
        | 0.10 | Planned | Tall renders |

        ```mermaid
        flowchart LR
          A[Markdown] --> B[Measure blocks]
          B --> C[Split snapshots]
        ```

        ## Closing section

        Closing content after every protected element.
        """

        let result = try await renderSplit(
            markdown,
            with: renderer,
            maximumSliceHeight: 360
        )
        let cutOffsets = result.parts.dropLast().map(\.slice.range.upperBound)

        XCTAssertGreaterThanOrEqual(result.geometry.protectedRanges.count, 6)
        for range in result.geometry.protectedRanges where range.count <= 360 {
            XCTAssertFalse(cutOffsets.contains(where: {
                range.lowerBound < $0 && $0 < range.upperBound
            }), "Unexpected cut inside protected range \(range)")
        }
    }

    @MainActor
    private func render(
        _ markdown: String,
        with renderer: MarkdownRenderer
    ) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            renderer.render(markdown) { result in
                continuation.resume(with: result)
            }
        }
    }

    @MainActor
    private func renderSplit(
        _ markdown: String,
        with renderer: MarkdownRenderer,
        maximumSliceHeight: Int
    ) async throws -> SplitRenderResult {
        try await withCheckedThrowingContinuation { continuation in
            renderer.renderSplit(
                markdown,
                maximumSliceHeight: maximumSliceHeight
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func writeReferenceImagesIfRequested(
        _ result: SplitRenderResult
    ) throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment[
            "MD2PNG_SPLIT_SNAPSHOT_DIR"
        ] else {
            return
        }
        let directoryURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        for (index, part) in result.parts.enumerated() {
            let fileURL = directoryURL.appendingPathComponent(
                String(format: "split-%02d.png", index + 1)
            )
            try RenderedImageExport.writePNG(part.image, to: fileURL)
        }
    }
}
