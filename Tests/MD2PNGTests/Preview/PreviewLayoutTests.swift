import AppKit
import XCTest
@testable import MD2PNG

final class PreviewLayoutTests: XCTestCase {
    @MainActor
    func testPreviewWindowDrawsActualRenderedContent() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            renderer.render("""
            # Visible preview

            ```swift
            let answer = 42
            print(answer)
            ```
            """) { result in
                continuation.resume(with: result)
            }
        }
        let controller = PreviewController()
        controller.show(image: image)
        defer { controller.close() }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertGreaterThan(controller.displayedImageFrame.width, 100)
        XCTAssertGreaterThan(controller.displayedImageFrame.height, 100)
        XCTAssertTrue(controller.imageIsAttachedToWindow)
        XCTAssertFalse(controller.canvasUsesAutoLayout)
        XCTAssertFalse(controller.displayedImageVisibleRect.isEmpty)
        XCTAssertTrue(controller.documentVisibleRect.intersects(controller.displayedImageFrame))
        XCTAssertTrue(controller.displayedImage === image)
        let displayedImage = try XCTUnwrap(controller.renderedImageSnapshot())
        XCTAssertTrue(containsDarkContent(in: displayedImage))
        if let outputPath = ProcessInfo.processInfo.environment["MD2PNG_PREVIEW_IMAGE_SNAPSHOT_PATH"],
           let png = displayedImage.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: outputPath))
        }
    }

    @MainActor
    func testShowingASecondImageReplacesPixels() throws {
        _ = NSApplication.shared
        let first = try makeImage(
            pixelsWide: 320,
            pixelsHigh: 200,
            backgroundColor: .white,
            accentColor: .systemRed
        )
        let second = try makeImage(
            pixelsWide: 640,
            pixelsHigh: 360,
            backgroundColor: .white,
            accentColor: .systemBlue
        )
        let controller = PreviewController()
        controller.show(image: first)
        controller.show(image: second)
        defer { controller.close() }

        XCTAssertTrue(controller.displayedImage === second)
        let snapshot = try XCTUnwrap(controller.renderedImageSnapshot())
        XCTAssertTrue(containsColor(.systemBlue, in: snapshot))
        XCTAssertFalse(containsColor(.systemRed, in: snapshot))
    }

    @MainActor
    func testPreviewContentRemainsVisibleAfterWindowResize() throws {
        _ = NSApplication.shared
        let image = try makeImage(
            pixelsWide: 900,
            pixelsHigh: 600,
            backgroundColor: .white,
            accentColor: .systemGreen
        )
        let controller = PreviewController()
        controller.show(image: image)
        defer { controller.close() }

        controller.window?.setContentSize(NSSize(width: 520, height: 420))
        controller.windowDidResize(Notification(name: NSWindow.didResizeNotification))

        XCTAssertLessThanOrEqual(
            controller.displayedImageFrame.width,
            controller.previewViewportSize.width - 48 + 0.001
        )
        XCTAssertTrue(containsColor(
            .systemGreen,
            in: try XCTUnwrap(controller.renderedImageSnapshot())
        ))
    }

    @MainActor
    func testTallPreviewIsScrollableStartsAtTopAndDrawsPixels() throws {
        _ = NSApplication.shared
        let image = try makeImage(
            pixelsWide: 600,
            pixelsHigh: 2_400,
            backgroundColor: .systemPurple,
            accentColor: .white
        )
        let controller = PreviewController()
        controller.show(image: image)
        defer { controller.close() }

        XCTAssertGreaterThan(
            controller.previewCanvasSize.height,
            controller.previewViewportSize.height
        )
        XCTAssertEqual(controller.displayedImageFrame.minY, 24, accuracy: 0.001)
        XCTAssertEqual(controller.visibleDocumentOrigin.y, 0, accuracy: 0.001)
        XCTAssertTrue(controller.displayedImage === image)
    }

    @MainActor
    func testClosingAndReopeningPreviewKeepsPixelsVisible() throws {
        _ = NSApplication.shared
        let image = try makeImage(
            pixelsWide: 480,
            pixelsHigh: 300,
            backgroundColor: .white,
            accentColor: .systemOrange
        )
        let controller = PreviewController()
        controller.show(image: image)
        controller.close()
        controller.show(image: image)
        defer { controller.close() }

        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertTrue(containsColor(
            .systemOrange,
            in: try XCTUnwrap(controller.renderedImageSnapshot())
        ))
    }

    @MainActor
    func testPreviewTitleIdentifiesPresetAndActualDimensions() throws {
        _ = NSApplication.shared
        let image = try makeImage(
            pixelsWide: 720,
            pixelsHigh: 1_120,
            backgroundColor: .white,
            accentColor: .systemBlue
        )
        let controller = PreviewController()
        controller.show(image: image, widthPreset: .compact)
        defer { controller.close() }

        XCTAssertEqual(
            controller.window?.title,
            L10n.format(
                "preview.window_title_with_width",
                defaultValue: "Preview — %@ · %ld × %ld px",
                RenderWidthPreset.compact.menuTitle,
                720,
                1_120
            )
        )
    }

    @MainActor
    func testPreviewExposesRenderedImageAndZoomToAccessibility() throws {
        _ = NSApplication.shared
        let image = try makeImage(
            pixelsWide: 720,
            pixelsHigh: 1_120,
            backgroundColor: .white,
            accentColor: .systemBlue
        )
        let controller = PreviewController()
        controller.show(image: image)
        defer { controller.close() }

        XCTAssertEqual(controller.previewImageAccessibilityRole, .image)
        XCTAssertEqual(
            controller.previewImageAccessibilityLabel,
            L10n.text("preview.rendered_image", defaultValue: "Rendered image")
        )
        XCTAssertEqual(
            controller.previewImageAccessibilityValue,
            L10n.format(
                "preview.rendered_image_dimensions",
                defaultValue: "%1$ld × %2$ld pixels",
                720,
                1_120
            )
        )
        XCTAssertEqual(
            controller.previewImageAccessibilityHelp,
            L10n.text(
                "preview.drag_help",
                defaultValue: "Drag to export this PNG to another app or folder."
            )
        )
        XCTAssertEqual(
            controller.previewZoomAccessibilityLabel,
            L10n.text("preview.zoom_level", defaultValue: "Preview zoom")
        )
        XCTAssertEqual(
            controller.previewZoomAccessibilityValue,
            controller.previewZoomStatus
        )
        XCTAssertEqual(
            controller.previewZoomAccessibilityHelp,
            L10n.text("preview.reset_actual_size", defaultValue: "Reset to Actual Size")
        )
    }

    @MainActor
    func testPreviewProvidesActionsAndResetsNewImagesToFit() throws {
        _ = NSApplication.shared
        let first = try makeImage(
            pixelsWide: 1_200,
            pixelsHigh: 800,
            backgroundColor: .white,
            accentColor: .systemBlue
        )
        let second = try makeImage(
            pixelsWide: 600,
            pixelsHigh: 1_600,
            backgroundColor: .white,
            accentColor: .systemPurple
        )
        let controller = PreviewController()
        controller.show(image: first, markdown: "# Monthly Product Update")
        defer { controller.close() }

        XCTAssertEqual(controller.previewZoomMode, .fit)
        XCTAssertTrue(controller.previewHasHorizontalScroller)
        XCTAssertEqual(controller.previewScrollerStyle, .overlay)
        XCTAssertEqual(controller.previewToolbarStyle, .expanded)
        XCTAssertEqual(
            controller.previewZoomStatusContainerSize,
            NSSize(width: 64, height: 22)
        )
        XCTAssertNil(controller.previewSelectedToolbarIdentifier)
        XCTAssertTrue(
            controller.toolbarSelectableItemIdentifiers(
                NSToolbar(identifier: "preview-layout-selection-test")
            ).isEmpty
        )
        XCTAssertEqual(
            Set(controller.previewToolbarLabels),
            Set([
                L10n.text("preview.copy_again", defaultValue: "Copy Again"),
                L10n.text("preview.save_png", defaultValue: "Save PNG…"),
                L10n.text("preview.open_in_preview", defaultValue: "Open in Preview"),
                L10n.text("preview.fit", defaultValue: "Fit to Window"),
                L10n.text("preview.zoom_out", defaultValue: "Zoom Out"),
                L10n.text("preview.zoom_level", defaultValue: "Preview zoom"),
                L10n.text("preview.zoom_in", defaultValue: "Zoom In")
            ])
        )
        XCTAssertEqual(controller.previewToolbarIconSizes.count, 6)
        XCTAssertEqual(controller.previewSuggestedPNGFilename, "Monthly Product Update.png")
        XCTAssertEqual(
            controller.toolbarDefaultItemIdentifiers(NSToolbar(identifier: "preview-layout-test")),
            [
                NSToolbarItem.Identifier("preview.copy-again"),
                NSToolbarItem.Identifier("preview.save-png"),
                NSToolbarItem.Identifier("preview.open-in-preview"),
                .flexibleSpace,
                NSToolbarItem.Identifier("preview.fit"),
                NSToolbarItem.Identifier("preview.zoom-out"),
                NSToolbarItem.Identifier("preview.zoom-status"),
                NSToolbarItem.Identifier("preview.zoom-in")
            ]
        )

        controller.selectActualSizeForTesting()
        XCTAssertEqual(controller.previewZoomMode, .actualSize)
        XCTAssertEqual(controller.previewZoomFactor, 1)
        XCTAssertNil(controller.previewSelectedToolbarIdentifier)
        let actualSizeFrame = controller.displayedImageFrame
        controller.selectActualSizeForTesting()
        XCTAssertEqual(controller.displayedImageFrame, actualSizeFrame)
        controller.zoomInForTesting()
        XCTAssertEqual(controller.previewZoomMode, .custom(1.25))
        XCTAssertNil(controller.previewSelectedToolbarIdentifier)
        controller.clickZoomStatusForTesting()
        XCTAssertEqual(controller.previewZoomMode, .actualSize)
        XCTAssertEqual(controller.previewZoomFactor, 1)

        controller.show(image: second)
        XCTAssertEqual(controller.previewZoomMode, .fit)
        XCTAssertTrue(controller.previewZoomStatus.contains("%"))
        XCTAssertFalse(controller.previewZoomStatus.contains("Fit"))
        let fitFrame = controller.displayedImageFrame
        let fitFactor = controller.previewZoomFactor
        controller.selectFitForTesting()
        XCTAssertEqual(controller.displayedImageFrame, fitFrame)
        XCTAssertEqual(controller.previewZoomFactor, fitFactor)
    }

    @MainActor
    func testPreviewVisibilityBoundaryChangesOnlyOnShowAndClose() throws {
        _ = NSApplication.shared
        let image = try makeImage(
            pixelsWide: 520,
            pixelsHigh: 180,
            backgroundColor: .white,
            accentColor: .systemBlue
        )
        var visibilityChanges: [Bool] = []
        let controller = PreviewController(
            onVisibilityChange: { visibilityChanges.append($0) }
        )

        controller.show(image: image)
        controller.show(image: image)
        XCTAssertEqual(visibilityChanges, [true])

        controller.close()
        XCTAssertEqual(visibilityChanges, [true, false])
    }

    @MainActor
    func testStalePreviewOpenFailureCannotDeleteTheCurrentGeneration() async throws {
        _ = NSApplication.shared
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PreviewOpenLifecycleTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let store = PreviewTemporaryImageStore(baseDirectory: baseDirectory)
        var requests: [(url: URL, completion: PreviewFileOpenCompletion)] = []
        var reportedErrors: [Error] = []
        let controller = PreviewController(
            onError: { reportedErrors.append($0) },
            temporaryImageStore: store,
            openFileInPreview: { url, completion in
                requests.append((url, completion))
            }
        )
        defer { controller.close() }
        let first = try makeImage(
            pixelsWide: 320,
            pixelsHigh: 200,
            backgroundColor: .white,
            accentColor: .systemRed
        )
        let second = try makeImage(
            pixelsWide: 640,
            pixelsHigh: 360,
            backgroundColor: .white,
            accentColor: .systemBlue
        )

        controller.show(image: first)
        controller.openInPreviewForTesting()
        controller.show(image: second)
        controller.openInPreviewForTesting()

        XCTAssertEqual(requests.count, 2)
        XCTAssertNotEqual(requests[0].url, requests[1].url)
        XCTAssertEqual(store.currentFileURL, requests[1].url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: requests[1].url.path))

        requests[0].completion(false)
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(store.currentFileURL, requests[1].url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: requests[1].url.path))
        XCTAssertTrue(reportedErrors.isEmpty)

        requests[1].completion(false)
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertNil(store.currentFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: requests[1].url.path))
        XCTAssertEqual(reportedErrors.count, 1)
    }

    private func containsDarkContent(in bitmap: NSBitmapImageRep) -> Bool {
        var darkPixels = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.redComponent < 0.45,
                   color.greenComponent < 0.45,
                   color.blueComponent < 0.45 {
                    darkPixels += 1
                }
            }
        }
        return darkPixels > 40
    }

    private func makeImage(
        pixelsWide: Int,
        pixelsHigh: Int,
        backgroundColor: NSColor,
        accentColor: NSColor
    ) throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
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
        backgroundColor.setFill()
        NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
        accentColor.setFill()
        NSRect(
            x: CGFloat(pixelsWide) * 0.25,
            y: CGFloat(pixelsHigh) * 0.25,
            width: CGFloat(pixelsWide) * 0.5,
            height: CGFloat(pixelsHigh) * 0.5
        ).fill()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: pixelsWide, height: pixelsHigh))
        image.addRepresentation(bitmap)
        return image
    }

    private func containsColor(_ expected: NSColor, in bitmap: NSBitmapImageRep) -> Bool {
        guard let expected = expected.usingColorSpace(.deviceRGB) else { return false }
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                guard let actual = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if abs(actual.redComponent - expected.redComponent) < 0.12,
                   abs(actual.greenComponent - expected.greenComponent) < 0.12,
                   abs(actual.blueComponent - expected.blueComponent) < 0.12,
                   actual.alphaComponent > 0.8 {
                    return true
                }
            }
        }
        return false
    }

    func testFitUpscalesSmallImageToAvailableWidth() {
        let layout = PreviewLayout.calculate(
            imageSize: NSSize(width: 400, height: 300),
            viewportSize: NSSize(width: 720, height: 580)
        )

        XCTAssertEqual(layout.canvasSize, NSSize(width: 720, height: 580))
        XCTAssertEqual(layout.zoomFactor, 1.68, accuracy: 0.001)
        XCTAssertEqual(layout.imageFrame.size, NSSize(width: 672, height: 504))
        XCTAssertEqual(layout.imageFrame.midX, 360, accuracy: 0.001)
        XCTAssertEqual(layout.imageFrame.midY, 290, accuracy: 0.001)
    }

    func testWideImageFitsAvailableWidthAndRemainsCentered() {
        let layout = PreviewLayout.calculate(
            imageSize: NSSize(width: 1_064, height: 688),
            viewportSize: NSSize(width: 720, height: 580)
        )

        XCTAssertEqual(layout.imageFrame.width, 672, accuracy: 0.001)
        XCTAssertLessThan(layout.imageFrame.height, 580)
        XCTAssertEqual(layout.imageFrame.midX, 360, accuracy: 0.001)
        XCTAssertEqual(layout.imageFrame.midY, 290, accuracy: 0.001)
    }

    func testTallImageFitsWidthAndStartsAtTopPadding() {
        let layout = PreviewLayout.calculate(
            imageSize: NSSize(width: 1_064, height: 3_000),
            viewportSize: NSSize(width: 720, height: 580)
        )

        XCTAssertEqual(layout.imageFrame.width, 672, accuracy: 0.001)
        XCTAssertGreaterThan(layout.canvasSize.height, 580)
        XCTAssertEqual(layout.imageFrame.minX, 24, accuracy: 0.001)
        XCTAssertEqual(layout.imageFrame.minY, 24, accuracy: 0.001)
    }

    func testPreviewWindowWidthReflectsPresetUntilLimitedByScreen() {
        let screenSize = NSSize(width: 1_440, height: 900)
        let compact = PreviewWindowLayout.calculate(
            imageSize: NSSize(width: 720, height: 1_120),
            visibleScreenSize: screenSize
        )
        let standard = PreviewWindowLayout.calculate(
            imageSize: NSSize(width: 1_120, height: 928),
            visibleScreenSize: screenSize
        )
        let wide = PreviewWindowLayout.calculate(
            imageSize: NSSize(width: 1_520, height: 880),
            visibleScreenSize: screenSize
        )

        XCTAssertEqual(compact.contentSize, NSSize(width: 768, height: 640))
        XCTAssertEqual(standard.contentSize, NSSize(width: 1_168, height: 640))
        XCTAssertEqual(wide.contentSize, NSSize(width: 1_360, height: 640))
        XCTAssertLessThan(compact.contentSize.width, standard.contentSize.width)
        XCTAssertLessThan(standard.contentSize.width, wide.contentSize.width)
    }

    func testActualSizeMapsOneImagePixelToOneBackingPixel() {
        let layout = PreviewLayout.calculate(
            imagePixelSize: NSSize(width: 1_440, height: 2_240),
            backingScaleFactor: 2,
            viewportSize: NSSize(width: 900, height: 700),
            zoomMode: .actualSize
        )

        XCTAssertEqual(layout.zoomFactor, 1)
        XCTAssertEqual(layout.imageFrame.size, NSSize(width: 720, height: 1_120))
        XCTAssertEqual(layout.imageFrame.minY, 24)
    }

    func testRetinaFitCanExceedOneHundredPercentToFillTheWindow() {
        let layout = PreviewLayout.calculate(
            imagePixelSize: NSSize(width: 520, height: 180),
            backingScaleFactor: 2,
            viewportSize: NSSize(width: 568, height: 420),
            zoomMode: .fit
        )

        XCTAssertEqual(layout.zoomFactor, 2, accuracy: 0.001)
        XCTAssertEqual(layout.imageFrame.width, 520, accuracy: 0.001)
        XCTAssertEqual(layout.imageFrame.midX, 284, accuracy: 0.001)
    }

    func testFitUsesActualPixelSizeAndPreservesTallScrolling() {
        let layout = PreviewLayout.calculate(
            imagePixelSize: NSSize(width: 2_240, height: 8_000),
            backingScaleFactor: 2,
            viewportSize: NSSize(width: 720, height: 580),
            zoomMode: .fit
        )

        XCTAssertEqual(layout.zoomFactor, 0.6, accuracy: 0.001)
        XCTAssertEqual(layout.imageFrame.width, 672, accuracy: 0.001)
        XCTAssertGreaterThan(layout.canvasSize.height, 580)
        XCTAssertEqual(layout.imageFrame.minY, 24, accuracy: 0.001)
    }

    func testCustomZoomClampsAndCreatesHorizontalScrollingCanvas() {
        let maximum = PreviewLayout.calculate(
            imagePixelSize: NSSize(width: 800, height: 600),
            backingScaleFactor: 2,
            viewportSize: NSSize(width: 720, height: 580),
            zoomMode: .custom(10)
        )
        let minimum = PreviewLayout.calculate(
            imagePixelSize: NSSize(width: 800, height: 600),
            backingScaleFactor: 2,
            viewportSize: NSSize(width: 720, height: 580),
            zoomMode: .custom(0.01)
        )

        XCTAssertEqual(maximum.zoomFactor, 4)
        XCTAssertEqual(maximum.imageFrame.size, NSSize(width: 1_600, height: 1_200))
        XCTAssertGreaterThan(maximum.canvasSize.width, 720)
        XCTAssertEqual(maximum.imageFrame.minX, 24)
        XCTAssertEqual(minimum.zoomFactor, 0.25)
        XCTAssertEqual(minimum.imageFrame.size, NSSize(width: 100, height: 75))
    }
}
