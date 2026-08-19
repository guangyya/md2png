import AppKit
import XCTest
@testable import MD2PNG

final class SplitImageExportTests: XCTestCase {
    func testSaveDestinationPresentationIncludesExactFileCount() {
        let single = SplitImageExportDestinationPresentation.make(
            suggestedDirectoryName: "Roadmap-split",
            fileCount: 1
        )
        XCTAssertEqual(single.title, "Save 1 Split PNG")
        XCTAssertTrue(single.message.contains("containing 1 numbered PNG file"))

        let multiple = SplitImageExportDestinationPresentation.make(
            suggestedDirectoryName: "Roadmap-split",
            fileCount: 12
        )
        XCTAssertEqual(multiple.title, "Save 12 Split PNGs")
        XCTAssertTrue(multiple.message.contains("containing 12 numbered PNG files"))
        XCTAssertEqual(multiple.prompt, "Choose Folder")
    }

    @MainActor
    func testCompletionCanRevealEverySavedPNGInFinder() {
        let destinationURL = URL(
            fileURLWithPath: "/tmp/Roadmap-split",
            isDirectory: true
        )
        var presented: SplitImageExportCompletionPresentation?
        var revealedURLs: [URL] = []
        let presenter = SplitImageExportCompletionPresenter(dependencies: .init(
            confirmShowInFinder: { presentation in
                presented = presentation
                return true
            },
            revealFiles: { revealedURLs = $0 }
        ))

        presenter.show(count: 2, directoryURL: destinationURL)

        XCTAssertEqual(presented?.title, "Saved 2 Split PNGs")
        XCTAssertEqual(presented?.showInFinderTitle, "Show in Finder")
        XCTAssertEqual(revealedURLs.map(\.lastPathComponent), [
            "Roadmap-split-01.png",
            "Roadmap-split-02.png"
        ])
    }

    func testNamingUsesMarkdownAndStableZeroPaddedNumbers() {
        XCTAssertEqual(
            SplitImageExportNaming.suggestedDirectoryName(
                from: "# Release roadmap"
            ),
            "Release roadmap-split"
        )
        XCTAssertEqual(
            SplitImageExportNaming.fileNames(
                directoryName: "Release roadmap-split",
                count: 3
            ),
            [
                "Release roadmap-split-01.png",
                "Release roadmap-split-02.png",
                "Release roadmap-split-03.png"
            ]
        )
        XCTAssertEqual(
            SplitImageExportNaming.fileNames(
                directoryName: "Export",
                count: 101
            ).last,
            "Export-101.png"
        )
        let longName = String(repeating: "导", count: 100)
        XCTAssertTrue(
            SplitImageExportNaming.fileNames(
                directoryName: longName,
                count: 100
            ).allSatisfy { $0.utf8.count <= 240 }
        )
    }

    @MainActor
    func testDestinationAvoidsReplacingAnExistingExportFolder() throws {
        let rootURL = makeTemporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("Roadmap-split", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("Roadmap-split-2", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertEqual(
            SplitImageExportDestination.uniqueDestination(
                parentURL: rootURL,
                suggestedDirectoryName: "Roadmap-split"
            ).lastPathComponent,
            "Roadmap-split-3"
        )
    }

    @MainActor
    func testWriterCreatesOneAtomicDirectoryOfReadableNumberedPNGs() async throws {
        let rootURL = makeTemporaryDirectoryURL()
        let destinationURL = rootURL.appendingPathComponent(
            "Roadmap-split",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try await SplitImageExportWriter.write(
            try makeSplitResult(),
            to: destinationURL
        )

        let names = try FileManager.default.contentsOfDirectory(atPath: destinationURL.path)
            .sorted()
        XCTAssertEqual(names, [
            "Roadmap-split-01.png",
            "Roadmap-split-02.png"
        ])
        let first = try XCTUnwrap(NSBitmapImageRep(data: Data(
            contentsOf: destinationURL.appendingPathComponent(names[0])
        )))
        let second = try XCTUnwrap(NSBitmapImageRep(data: Data(
            contentsOf: destinationURL.appendingPathComponent(names[1])
        )))
        XCTAssertEqual(NSSize(width: first.pixelsWide, height: first.pixelsHigh), NSSize(
            width: 40,
            height: 20
        ))
        XCTAssertEqual(NSSize(width: second.pixelsWide, height: second.pixelsHigh), NSSize(
            width: 40,
            height: 24
        ))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: rootURL.path),
            ["Roadmap-split"]
        )
    }

    @MainActor
    func testWriterAppliesRoundedCornersToEverySplitPNG() async throws {
        let rootURL = makeTemporaryDirectoryURL()
        let destinationURL = rootURL.appendingPathComponent(
            "Rounded-split",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try await SplitImageExportWriter.write(
            try makeSplitResult(),
            to: destinationURL,
            cornerStyle: .rounded
        )

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: destinationURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(fileURLs.count, 2)
        for fileURL in fileURLs {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: fileURL)))
            XCTAssertLessThan(
                try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent,
                0.05
            )
            XCTAssertGreaterThan(
                try XCTUnwrap(
                    bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
                ).alphaComponent,
                0.95
            )
        }
    }

    @MainActor
    func testWriterNeverOverwritesAnExistingDestination() async throws {
        let rootURL = makeTemporaryDirectoryURL()
        let destinationURL = rootURL.appendingPathComponent(
            "Existing-split",
            isDirectory: true
        )
        let sentinelURL = destinationURL.appendingPathComponent("keep.txt")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: sentinelURL)

        do {
            try await SplitImageExportWriter.write(
                try makeSplitResult(),
                to: destinationURL
            )
            XCTFail("Expected an existing-destination failure")
        } catch AppError.splitExportWriteFailed {
            XCTAssertEqual(try String(contentsOf: sentinelURL, encoding: .utf8), "keep")
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: rootURL.path),
                ["Existing-split"]
            )
        }
    }

    @MainActor
    func testRealRendererAndWriterExportTallMarkdownEndToEnd() async throws {
        _ = NSApplication.shared
        let rootURL = makeTemporaryDirectoryURL()
        let destinationURL = rootURL.appendingPathComponent(
            "Tall-document-split",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let markdown = (1 ... 180).map { index in
            "Paragraph \(index): offline split-export end-to-end validation."
        }.joined(separator: "\n\n")
        let renderer = MarkdownRenderer()

        let result = try await withCheckedThrowingContinuation { continuation in
            renderer.renderSplit(
                markdown,
                maximumSliceHeight: SplitImageExportPolicy.maximumSliceHeight
            ) { result in
                continuation.resume(with: result)
            }
        }
        try await SplitImageExportWriter.write(result, to: destinationURL)

        XCTAssertGreaterThan(result.parts.count, 1)
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: destinationURL,
            includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(fileURLs.count, result.parts.count)
        XCTAssertEqual(fileURLs.first?.lastPathComponent, "Tall-document-split-01.png")
        for fileURL in fileURLs {
            XCTAssertNotNil(NSBitmapImageRep(data: try Data(contentsOf: fileURL)))
        }
    }

    private func makeTemporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "SplitImageExportTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    @MainActor
    private func makeSplitResult() throws -> SplitRenderResult {
        let geometry = try XCTUnwrap(RenderSplitGeometry(
            contentHeight: 22,
            preferredBreakOffsets: [10],
            protectedRanges: []
        ))
        return SplitRenderResult(
            contentSize: NSSize(width: 20, height: 22),
            geometry: geometry,
            parts: [
                SplitRenderResult.Part(
                    image: try makeRetinaImage(
                        pointSize: NSSize(width: 20, height: 10),
                        pixelSize: NSSize(width: 40, height: 20)
                    ),
                    slice: RenderSnapshotSlice(
                        range: 0 ..< 10,
                        ending: .preferredBoundary
                    )
                ),
                SplitRenderResult.Part(
                    image: try makeRetinaImage(
                        pointSize: NSSize(width: 20, height: 12),
                        pixelSize: NSSize(width: 40, height: 24)
                    ),
                    slice: RenderSnapshotSlice(
                        range: 10 ..< 22,
                        ending: .contentEnd
                    )
                )
            ]
        )
    }

    private func makeRetinaImage(
        pointSize: NSSize,
        pixelSize: NSSize
    ) throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = pointSize
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(origin: .zero, size: pixelSize).fill()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: pointSize)
        image.addRepresentation(bitmap)
        return image
    }
}
