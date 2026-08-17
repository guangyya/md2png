import AppKit
import XCTest
@testable import MD2PNG

final class PackagedRenderSelfTestTests: XCTestCase {
    func testSelfTestMarkdownLookupUsesOnlyPackagedExamplesDirectory() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MD2PNG-SelfTest-\(UUID().uuidString)", isDirectory: true)
        let examples = root.appendingPathComponent("Examples", isDirectory: true)
        let markdownURL = examples.appendingPathComponent(
            PackagedRenderSelfTestResources.markdownFileName
        )
        defer { try? fileManager.removeItem(at: root) }

        XCTAssertNil(PackagedRenderSelfTestResources.markdownURL(resourcesURL: root))
        XCTAssertNil(PackagedRenderSelfTestResources.markdownURL(resourcesURL: nil))

        try fileManager.createDirectory(at: examples, withIntermediateDirectories: true)
        try Data("self-test".utf8).write(to: markdownURL)

        XCTAssertEqual(
            PackagedRenderSelfTestResources.markdownURL(resourcesURL: root)?.standardizedFileURL,
            markdownURL.standardizedFileURL
        )
    }

    func testCommittedSelfTestMarkdownCoversRequiredRendererFeatures() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let markdownURL = repositoryRoot.appendingPathComponent(
            "Examples/\(PackagedRenderSelfTestResources.markdownFileName)"
        )
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)

        XCTAssertTrue(PackagedRenderSelfTestResources.validate(markdown: markdown))
        XCTAssertFalse(PackagedRenderSelfTestResources.validate(markdown: "# Incomplete"))
    }

    func testSelfTestImplementationHasNoClipboardDependency() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/MD2PNG/Rendering/PackagedRenderSelfTest.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("NSPasteboard"))
        XCTAssertFalse(source.contains("Clipboard."))
    }

    @MainActor
    func testImageValidatorAcceptsPlausiblePNGWithVisibleContent() throws {
        let image = try makeImage(
            width: 620,
            height: 320,
            background: .white,
            foreground: .black
        )

        let report = try XCTUnwrap(PackagedRenderSelfTestImageValidator.validate(image))

        XCTAssertGreaterThanOrEqual(report.width, 620)
        XCTAssertGreaterThanOrEqual(report.height, 320)
        XCTAssertGreaterThanOrEqual(report.pngByteCount, 1_024)
    }

    @MainActor
    func testImageValidatorRejectsBlankAndImplausiblySmallImages() throws {
        let blank = try makeImage(
            width: 620,
            height: 320,
            background: .white,
            foreground: nil
        )
        let small = try makeImage(
            width: 100,
            height: 80,
            background: .white,
            foreground: .black
        )

        XCTAssertNil(PackagedRenderSelfTestImageValidator.validate(blank))
        XCTAssertNil(PackagedRenderSelfTestImageValidator.validate(small))
    }

    @MainActor
    func testRendererFailsDeterministicallyWithoutAResourcePage() async {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer(pageURL: nil)

        let result: Result<NSImage, Error> = await withCheckedContinuation { continuation in
            renderer.render("# Test") { continuation.resume(returning: $0) }
        }

        guard case let .failure(error) = result else {
            XCTFail("Expected renderer resource failure")
            return
        }
        XCTAssertEqual(
            error.localizedDescription,
            AppError.rendererUnavailable.localizedDescription
        )
    }

    @MainActor
    private func makeImage(
        width: Int,
        height: Int,
        background: NSColor,
        foreground: NSColor?
    ) throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        background.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        if let foreground {
            foreground.setFill()
            NSRect(x: 80, y: 80, width: 220, height: 100).fill()
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }
}
