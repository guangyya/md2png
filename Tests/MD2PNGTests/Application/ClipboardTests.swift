import AppKit
import Carbon
import XCTest
@testable import MD2PNG

final class ClipboardTests: XCTestCase {
    @MainActor
    func testLastRenderShortcutIsDistinctFromRenderShortcut() {
        let render = GlobalHotKey.Registration.render {}
        let showLastRender = GlobalHotKey.Registration.showLastRender {}

        XCTAssertNotEqual(render.id, showLastRender.id)
        XCTAssertNotEqual(render.keyCode, showLastRender.keyCode)
        XCTAssertEqual(render.keyCode, UInt32(kVK_ANSI_X))
        XCTAssertEqual(showLastRender.keyCode, UInt32(kVK_ANSI_Z))
        XCTAssertEqual(render.modifiers, showLastRender.modifiers)
        XCTAssertEqual(render.displayName, "Render (Control-Command-X)")
        XCTAssertEqual(
            showLastRender.displayName,
            "Show Last Render (Control-Command-Z)"
        )
    }

    @MainActor
    func testPreviewWindowRecognizesCommandW() throws {
        _ = NSApplication.shared
        let commandW = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))
        let optionCommandW = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))

        XCTAssertTrue(PreviewWindow.isCloseShortcut(commandW))
        XCTAssertFalse(PreviewWindow.isCloseShortcut(optionCommandW))

        let window = PreviewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        XCTAssertTrue(window.isVisible)

        window.sendEvent(commandW)

        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    func testPreviewWindowMapsActionAndZoomShortcuts() throws {
        func event(_ characters: String, modifiers: NSEvent.ModifierFlags = .command) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: 0
            ))
        }

        XCTAssertEqual(PreviewWindow.command(for: try event("c")), .copyAgain)
        XCTAssertEqual(PreviewWindow.command(for: try event("s")), .savePNG)
        XCTAssertEqual(PreviewWindow.command(for: try event("9")), .fit)
        XCTAssertEqual(PreviewWindow.command(for: try event("0")), .actualSize)
        XCTAssertEqual(PreviewWindow.command(for: try event("-")), .zoomOut)
        XCTAssertEqual(PreviewWindow.command(for: try event("=")), .zoomIn)
        XCTAssertEqual(
            PreviewWindow.command(for: try event("=", modifiers: [.command, .shift])),
            .zoomIn
        )
        XCTAssertNil(PreviewWindow.command(for: try event("c", modifiers: [.command, .option])))
    }

    @MainActor
    func testPreviewCopyAgainUsesInjectedClipboardBoundary() throws {
        _ = NSApplication.shared
        let image = NSImage(size: NSSize(width: 120, height: 80))
        var copiedImage: NSImage?
        var recordedChangeCount: Int?
        let controller = PreviewController(
            copyImage: {
                copiedImage = $0
                return 73
            },
            onCopied: { recordedChangeCount = $0 }
        )
        controller.show(image: image)
        defer { controller.close() }
        let commandC = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8
        ))

        controller.window?.sendEvent(commandC)

        XCTAssertTrue(copiedImage === image)
        XCTAssertEqual(recordedChangeCount, 73)
    }

    func testPackagedRendererResolvesFromContentsResources() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("MD2PNGTests-\(UUID().uuidString)", isDirectory: true)
        let resourcesURL = testRoot.appendingPathComponent("Contents/Resources", isDirectory: true)
        let bundleURL = resourcesURL.appendingPathComponent("md2png_MD2PNG.bundle", isDirectory: true)
        let rendererURL = bundleURL.appendingPathComponent("renderer.html")
        defer { try? fileManager.removeItem(at: testRoot) }

        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try Data("<!doctype html>".utf8).write(to: rendererURL)

        XCTAssertEqual(
            RendererResources.packagedPageURL(resourcesURL: resourcesURL)?.standardizedFileURL,
            rendererURL.standardizedFileURL
        )
    }

    @MainActor
    func testBrandStatusIconIsCompactTemplateImage() {
        let image = BrandIcon.statusBarImage()

        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(
            image.accessibilityDescription,
            L10n.text("accessibility.app", defaultValue: "md2png")
        )
    }

    func testMenuPreviewIsCompactAndCollapsesWhitespace() {
        let english = L10n.localizedBundle(for: "en")
        let preview = Clipboard.menuPreview(
            text: "# Weekly update\n\n| Platform | Status |",
            hasImage: false,
            maxCharacters: 24,
            localizationBundle: english
        )

        XCTAssertEqual(preview, "Clipboard: # Weekly update | Platf…")
    }

    func testMenuPreviewDescribesImageAndEmptyClipboard() {
        let english = L10n.localizedBundle(for: "en")
        XCTAssertEqual(
            Clipboard.menuPreview(text: nil, hasImage: true, localizationBundle: english),
            "Clipboard: PNG image"
        )
        XCTAssertEqual(
            Clipboard.menuPreview(
                text: "  \n  ",
                hasImage: false,
                localizationBundle: english
            ),
            "Clipboard: No text"
        )
        XCTAssertEqual(
            Clipboard.menuPreview(
                text: "A short note",
                hasImage: false,
                includeLabel: false,
                localizationBundle: english
            ),
            "A short note"
        )
    }

    func testMenuStateEnablesRenderingOnlyForNonemptyText() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))

        let text = Clipboard.menuState(
            text: "  # Markdown  ",
            hasImage: false,
            includeLabel: false,
            localizationBundle: english
        )
        let image = Clipboard.menuState(
            text: nil,
            hasImage: true,
            includeLabel: false,
            localizationBundle: english
        )
        let empty = Clipboard.menuState(
            text: " \n\t ",
            hasImage: false,
            includeLabel: false,
            localizationBundle: english
        )

        XCTAssertEqual(text, ClipboardMenuState(preview: "# Markdown", containsMarkdown: true))
        XCTAssertEqual(image, ClipboardMenuState(preview: "PNG image", containsMarkdown: false))
        XCTAssertEqual(empty, ClipboardMenuState(preview: "No text", containsMarkdown: false))
    }

    func testMarkdownValidationPreservesTheExactSource() throws {
        let markdown = "\n  # Keep surrounding whitespace  \n"

        XCTAssertEqual(try Clipboard.markdownText(from: markdown), markdown)
        XCTAssertThrowsError(try Clipboard.markdownText(from: " \n\t "))
        XCTAssertThrowsError(try Clipboard.markdownText(from: nil))
    }

    @MainActor
    func testClipboardPreviewViewHasFixedCompactSize() {
        let view = ClipboardPreviewView()
        view.update(String(repeating: "Long clipboard content ", count: 50))

        XCTAssertEqual(view.frame.size, ClipboardPreviewView.preferredSize)
        XCTAssertEqual(view.accessibilityValue() as? String, String(repeating: "Long clipboard content ", count: 50))
    }

    func testUserFacingErrorsHaveDescriptions() {
        XCTAssertNotNil(AppError.emptyClipboard.errorDescription)
        XCTAssertNotNil(AppError.unsupportedMarkdownFileType.errorDescription)
        XCTAssertNotNil(AppError.markdownFileReadFailed.errorDescription)
        XCTAssertNotNil(AppError.markdownFileInvalidEncoding.errorDescription)
        XCTAssertNotNil(AppError.emptyMarkdownFile.errorDescription)
        XCTAssertNotNil(AppError.rendererUnavailable.errorDescription)
        XCTAssertNotNil(AppError.rendererRecoveryFailed.errorDescription)
        XCTAssertNotNil(AppError.rendererTimedOut.errorDescription)
        XCTAssertNotNil(AppError.rendererFailed.errorDescription)
        XCTAssertNotNil(AppError.invalidRendererResponse.errorDescription)
        XCTAssertNotNil(AppError.contentTooLarge(width: 1, height: 2).errorDescription)
        XCTAssertNotNil(
            AppError.splitExportContentTooLarge(width: 1, height: 2).errorDescription
        )
        XCTAssertNotNil(AppError.rendererPNGEncodingFailed.errorDescription)
        XCTAssertNotNil(AppError.pngEncodingFailed.errorDescription)
        XCTAssertNotNil(AppError.pngWriteFailed.errorDescription)
        XCTAssertNotNil(AppError.splitExportWriteFailed.errorDescription)
        XCTAssertNotNil(AppError.previewOpenFailed.errorDescription)
        XCTAssertNotNil(AppError.clipboardWriteFailed.errorDescription)
        XCTAssertNotNil(AppError.exampleUnavailable("Short Example").errorDescription)
    }

    func testRenderErrorsConfirmClipboardSafetyAndOfferRecovery() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))

        let englishMessage = AppError.rendererTimedOut.message(localizationBundle: english)
        XCTAssertTrue(englishMessage.contains("clipboard is unchanged"))
        XCTAssertTrue(englishMessage.contains("try again"))

        let chineseMessage = AppError.contentTooLarge(width: 1_200, height: 3_400)
            .message(localizationBundle: chinese)
        XCTAssertEqual(
            chineseMessage,
            "无法生成 1200 × 3400 的 PNG，剪贴板内容未改变。请缩短 Markdown 后重试。"
        )
    }

    @MainActor
    func testRendererProducesNonEmptyImageForTableAndMermaid() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        let markdown = """
        # Weekly delivery update

        Everything below is rendered locally on your Mac.

        | Area | Status | Owner | Notes |
        |:--|:--:|--:|:--|
        | macOS app | ✅ Done | Alice | Ready to share |
        | Documentation | 🚧 In progress | Bob | Release notes next |
        | Validation | ⏳ Pending | Carol | Test on a second Mac |

        ```mermaid
        flowchart LR
            Draft[Copy Markdown] --> Render[Render locally]
            Render --> Review{Looks good?}
            Review -->|Yes| Paste[Paste PNG]
            Review -->|No| Draft
            Paste --> Send[Send manually]
        ```

        > md2png never sends a message automatically.
        """

        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            renderer.render(markdown) { result in
                continuation.resume(with: result)
            }
        }

        XCTAssertGreaterThanOrEqual(image.size.width, 520)
        XCTAssertGreaterThan(image.size.height, 150)
        XCTAssertNotNil(image.tiffRepresentation)

        if let outputPath = ProcessInfo.processInfo.environment["MD2PNG_SNAPSHOT_PATH"],
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: outputPath))
        }
    }

    @MainActor
    func testRendererGanttTimelineHasReadableWidthAndSpacing() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        let markdown = """
        ## Milestone timeline

        ```mermaid
        gantt
            title md2png pilot timeline
            dateFormat  YYYY-MM-DD
            axisFormat  %b %d
            section Product
            MVP implementation       :done,    mvp, 2026-08-10, 3d
            Brand and packaging      :done,    pkg, 2026-08-12, 2d
            Pilot feedback           :active,  pilot, 2026-08-14, 8d
            section Release
            Developer ID certificate :active,  cert, 2026-08-14, 5d
            Notarization validation  :         note, after cert, 2d
            General availability     :milestone, ga, 2026-09-04, 0d
        ```
        """

        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            renderer.render(markdown) { result in
                continuation.resume(with: result)
            }
        }

        XCTAssertGreaterThanOrEqual(image.size.width, 1_100)
        XCTAssertGreaterThanOrEqual(image.size.height, 300)

        if let outputPath = ProcessInfo.processInfo.environment["MD2PNG_GANTT_SNAPSHOT_PATH"],
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: outputPath))
        }
    }

    @MainActor
    func testLongProjectUpdateSampleRendersEndToEnd() async throws {
        _ = NSApplication.shared
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let markdownURL = repositoryRoot.appendingPathComponent("Examples/long-project-update.md")
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        let renderer = MarkdownRenderer()

        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            renderer.render(markdown) { result in
                continuation.resume(with: result)
            }
        }

        XCTAssertGreaterThanOrEqual(image.size.width, 1_100)
        XCTAssertGreaterThan(image.size.height, 2_000)
        XCTAssertNotNil(image.tiffRepresentation)

        if let outputPath = ProcessInfo.processInfo.environment["MD2PNG_LONG_SAMPLE_SNAPSHOT_PATH"],
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: outputPath))
        }
    }
}
