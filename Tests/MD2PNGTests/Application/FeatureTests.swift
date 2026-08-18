import AppKit
import Foundation
import XCTest
@testable import MD2PNG

final class FeatureTests: XCTestCase {
    func testEveryExampleResourceResolves() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MD2PNGFeatureTests-\(UUID().uuidString)", isDirectory: true)
        let examples = root.appendingPathComponent("Examples", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: examples, withIntermediateDirectories: true)
        for kind in ExampleKind.allCases {
            try Data(kind.menuTitle.utf8).write(
                to: examples.appendingPathComponent(kind.fileName)
            )
        }

        XCTAssertEqual(ExampleKind.allCases.count, 9)
        XCTAssertEqual(
            ExampleKind.allCases.filter(\.startsMenuSection),
            [.formatting, .flowchart]
        )
        XCTAssertEqual(Set(ExampleKind.allCases.map(\.fileName)).count, 9)
        for kind in ExampleKind.allCases {
            XCTAssertEqual(
                AppResources.exampleURL(for: kind, resourcesURL: root)?.lastPathComponent,
                kind.fileName
            )
        }
    }

    func testEnglishAndSimplifiedChineseLocalizationsResolve() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))

        let englishStrings = try localizationStrings(in: english)
        let chineseStrings = try localizationStrings(in: chinese)
        XCTAssertEqual(Set(englishStrings.keys), Set(chineseStrings.keys))
        XCTAssertGreaterThanOrEqual(englishStrings.count, 40)

        XCTAssertEqual(
            L10n.text("menu.render", defaultValue: "fallback", bundle: english),
            "Render Clipboard as Image"
        )
        XCTAssertEqual(
            L10n.text("menu.render", defaultValue: "fallback", bundle: chinese),
            "将剪贴板渲染为图片"
        )
        XCTAssertEqual(
            L10n.text(
                "preview.reset_actual_size",
                defaultValue: "fallback",
                bundle: english
            ),
            "Reset to Actual Size"
        )
        XCTAssertEqual(
            L10n.format(
                "preview.rendered_image_dimensions",
                defaultValue: "fallback",
                bundle: chinese,
                720,
                1_120
            ),
            "720 × 1120 像素"
        )
        XCTAssertEqual(
            Clipboard.menuPreview(
                text: nil,
                hasImage: true,
                localizationBundle: chinese
            ),
            "剪贴板：PNG 图片"
        )
        XCTAssertEqual(
            L10n.format(
                "error.content_too_large",
                defaultValue: "fallback",
                bundle: chinese,
                1_200,
                3_400
            ),
            "无法生成 1200 × 3400 的 PNG，剪贴板内容未改变。请缩短 Markdown 后重试。"
        )

        let changelog = """
        ## [1.0.0]

        ### Added

        - Chinese localization.
        """
        XCTAssertEqual(
            ChangelogParser.releaseNotes(
                for: "1.0.0",
                in: changelog,
                localizationBundle: chinese
            ),
            "新增\n• Chinese localization."
        )
    }

    func testLocalizedFormatArgumentsMatchAndUsePositionsForMultipleValues() throws {
        let english = try localizationStrings(
            in: XCTUnwrap(L10n.localizedBundle(for: "en"))
        )
        let chinese = try localizationStrings(
            in: XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))
        )

        for key in english.keys.sorted() {
            let englishTokens = try formatTokens(in: XCTUnwrap(english[key]))
            let chineseTokens = try formatTokens(in: XCTUnwrap(chinese[key]))
            XCTAssertEqual(
                englishTokens.sorted(),
                chineseTokens.sorted(),
                "Format arguments differ for \(key)"
            )
            if englishTokens.count > 1 {
                XCTAssertTrue(
                    englishTokens.allSatisfy { $0.position != nil },
                    "Multiple values must use positional formats for \(key)"
                )
                XCTAssertTrue(
                    chineseTokens.allSatisfy { $0.position != nil },
                    "Multiple values must use positional formats for \(key)"
                )
            }
        }
    }

    @MainActor
    func testHUDLayoutSupportsMultilineRecoveryAndVisibleFramePlacement() {
        let short = HUDLayout.panelSize(for: "PNG copied")
        let long = HUDLayout.panelSize(for: String(repeating: "A longer error message ", count: 8))

        XCTAssertGreaterThanOrEqual(short.width, HUDLayout.minimumWidth)
        XCTAssertLessThanOrEqual(long.width, HUDLayout.maximumWidth)
        XCTAssertGreaterThan(long.height, short.height)

        let visibleFrame = NSRect(x: 1440, y: 24, width: 1920, height: 1056)
        let origin = HUDLayout.panelOrigin(panelSize: long, visibleFrame: visibleFrame)
        XCTAssertEqual(origin.x + long.width / 2, visibleFrame.midX, accuracy: 0.01)
        XCTAssertGreaterThan(origin.y, visibleFrame.minY)
        XCTAssertLessThan(origin.y + long.height, visibleFrame.maxY)
    }

    @MainActor
    func testHUDAnnouncesFeedbackOnceWithSeverityAndCanSuppressDuplicates() {
        _ = NSApplication.shared
        var announcements: [(message: String, priority: NSAccessibilityPriorityLevel)] = []
        let hud = HUDController(isVoiceOverEnabled: { false }) { message, priority in
            announcements.append((message, priority))
        }
        defer { hud.dismiss() }

        hud.show(
            "PNG copied — paste with Command-V",
            symbol: "checkmark.circle.fill",
            accessibilityAnnouncement: "PNG copied and ready to paste with Command-V"
        )
        XCTAssertTrue(hud.visualPanelIsHiddenFromAccessibilityForTesting)
        hud.show(
            "Render failed",
            symbol: "exclamationmark.triangle.fill",
            style: .error
        )
        hud.show(
            "Update ready",
            symbol: "arrow.down.circle.fill",
            announces: false
        )

        XCTAssertEqual(announcements.map(\.message), [
            "PNG copied and ready to paste with Command-V",
            "Render failed"
        ])
        XCTAssertEqual(announcements.map(\.priority), [.medium, .high])
    }

    @MainActor
    func testHUDKeepsCompleteFeedbackVisibleWhileVoiceOverIsEnabled() {
        var announcements: [String] = []
        let hud = HUDController(isVoiceOverEnabled: { true }) { message, _ in
            announcements.append(message)
        }

        hud.show(
            "PNG copied — paste with Command-V",
            symbol: "checkmark.circle.fill",
            accessibilityAnnouncement: "PNG copied and ready to paste with Command-V"
        )

        defer { hud.dismiss() }
        XCTAssertTrue(hud.hasVisualPanelForTesting)
        XCTAssertFalse(hud.visualPanelIsHiddenFromAccessibilityForTesting)
        XCTAssertEqual(
            hud.visualMessageForTesting,
            "PNG copied and ready to paste with Command-V"
        )
        XCTAssertTrue(announcements.isEmpty)
        XCTAssertEqual(
            HUDStyle.success.displayDuration(voiceOverEnabled: true),
            8.0
        )

        hud.show(
            "Update ready",
            symbol: "arrow.down.circle.fill",
            announces: false
        )
        XCTAssertFalse(hud.hasVisualPanelForTesting)
        XCTAssertTrue(announcements.isEmpty)
    }

    func testProjectAndReleaseLinksUseInjectedHTTPSRepository() throws {
        let project = try XCTUnwrap(ProjectLinks.projectURL(
            from: "  https://github.com/owner/md2png  "
        ))
        let releases = ProjectLinks.releasesURL(for: project)

        XCTAssertEqual(project.scheme, "https")
        XCTAssertEqual(releases.host, project.host)
        XCTAssertEqual(
            releases.path,
            "/owner/md2png/releases"
        )
    }

    func testProjectLinkRejectsMissingOrUnsafeConfiguration() {
        XCTAssertNil(ProjectLinks.projectURL(from: nil))
        XCTAssertNil(ProjectLinks.projectURL(from: ""))
        XCTAssertNil(ProjectLinks.projectURL(from: "http://github.com/owner/repository"))
        XCTAssertNil(ProjectLinks.projectURL(from: "https://user@example.com/owner/repository"))
        XCTAssertNil(ProjectLinks.projectURL(from: "https://example.com/owner/repository?q=1"))
    }

    @MainActor
    func testFocusedSamplesRenderEndToEnd() async throws {
        _ = NSApplication.shared
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let renderer = MarkdownRenderer()

        for kind in ExampleKind.allCases where kind != .long {
            let markdown = try String(
                contentsOf: repositoryRoot
                    .appendingPathComponent("Examples", isDirectory: true)
                    .appendingPathComponent(kind.fileName),
                encoding: .utf8
            )
            let image: NSImage = try await withCheckedThrowingContinuation { continuation in
                renderer.render(markdown) { result in
                    continuation.resume(with: result)
                }
            }

            XCTAssertGreaterThanOrEqual(image.size.width, 520, kind.menuTitle)
            XCTAssertGreaterThan(image.size.height, 100, kind.menuTitle)
            XCTAssertNotNil(image.tiffRepresentation, kind.menuTitle)
        }
    }

    func testCodeSampleCoversCommonFencedLanguages() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let markdown = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Examples/code-blocks.md"),
            encoding: .utf8
        )

        XCTAssertTrue(markdown.contains("```swift"))
        XCTAssertTrue(markdown.contains("```json"))
        XCTAssertTrue(markdown.contains("```sh"))
    }

    @MainActor
    func testCodeSampleRendersWithSyntaxHighlightColors() async throws {
        _ = NSApplication.shared
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let markdown = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Examples/code-blocks.md"),
            encoding: .utf8
        )
        let renderer = MarkdownRenderer()
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            renderer.render(markdown) { result in
                continuation.resume(with: result)
            }
        }

        XCTAssertTrue(containsChromaticSyntaxColor(in: image))

        if let outputPath = ProcessInfo.processInfo.environment["MD2PNG_CODE_SNAPSHOT_PATH"],
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: outputPath))
        }
    }

    @MainActor
    func testInvalidMermaidReturnsARecoveryMessageInsteadOfWebKitDetails() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        let result: Result<NSImage, Error> = await withCheckedContinuation { continuation in
            renderer.render(
                """
                ```mermaid
                flowchart LR
                    A -->
                ```
                """
            ) { continuation.resume(returning: $0) }
        }

        guard case let .failure(error) = result,
              let failure = error as? RendererFailure else {
            XCTFail("Expected a privacy-safe renderer failure, got \(result)")
            return
        }
        XCTAssertEqual(failure.kind, .mermaidSyntax)
        XCTAssertEqual(failure.diagramNumber, 1)
        XCTAssertEqual(failure.sourceLine, 3)
        XCTAssertEqual(
            failure.errorDescription,
            L10n.format(
                "renderer_error.mermaid_diagram_line",
                defaultValue: "Couldn’t render Mermaid diagram %1$ld near Markdown line %2$ld.",
                1,
                3
            )
        )
    }

    @MainActor
    func testMermaidDiagnosticsIdentifyDiagramTypeAndSecondDiagramLocation() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        let unknownType: Result<NSImage, Error> = await withCheckedContinuation { continuation in
            renderer.render(
                """
                # Diagram

                ```mermaid
                notADiagramType
                    A --> B
                ```
                """
            ) { continuation.resume(returning: $0) }
        }
        guard case let .failure(typeError) = unknownType,
              let typeFailure = typeError as? RendererFailure else {
            XCTFail("Expected a structured Mermaid type failure")
            return
        }
        XCTAssertEqual(typeFailure.kind, .mermaidDiagramType)
        XCTAssertEqual(typeFailure.diagramNumber, 1)
        XCTAssertEqual(typeFailure.sourceLine, 4)

        let secondDiagram: Result<NSImage, Error> = await withCheckedContinuation { continuation in
            renderer.render(
                """
                ```mermaid
                flowchart LR
                    A --> B
                ```

                ```mermaid
                flowchart LR
                    C -->
                ```
                """
            ) { continuation.resume(returning: $0) }
        }
        guard case let .failure(syntaxError) = secondDiagram,
              let syntaxFailure = syntaxError as? RendererFailure else {
            XCTFail("Expected a structured second-diagram failure")
            return
        }
        XCTAssertEqual(syntaxFailure.kind, .mermaidSyntax)
        XCTAssertEqual(syntaxFailure.diagramNumber, 2)
        XCTAssertEqual(syntaxFailure.sourceLine, 8)
    }

    private func localizationStrings(in bundle: Bundle) throws -> [String: String] {
        let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
    }

    private func formatTokens(in value: String) throws -> [FormatToken] {
        let expression = try NSRegularExpression(
            pattern: #"%(?:(\d+)\$)?(@|ld|d|f)"#
        )
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).map { match in
            let position = Range(match.range(at: 1), in: value).flatMap {
                Int(value[$0])
            }
            let typeRange = Range(match.range(at: 2), in: value)!
            return FormatToken(position: position, type: String(value[typeRange]))
        }
    }

    private func containsChromaticSyntaxColor(in image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return false
        }

        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                if channels.max()! - channels.min()! > 0.12,
                   channels.min()! < 0.75 {
                    return true
                }
            }
        }
        return false
    }
}

private struct FormatToken: Comparable {
    let position: Int?
    let type: String

    static func < (lhs: FormatToken, rhs: FormatToken) -> Bool {
        if lhs.position != rhs.position {
            return (lhs.position ?? 0) < (rhs.position ?? 0)
        }
        return lhs.type < rhs.type
    }
}
