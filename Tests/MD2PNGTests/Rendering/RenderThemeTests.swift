import AppKit
import XCTest
@testable import MD2PNG

final class RenderThemeTests: XCTestCase {
    func testThemesHaveStableExplicitOrder() {
        XCTAssertEqual(RenderTheme.allCases, [.cleanLight, .warmPaper, .dark])
        XCTAssertEqual(RenderTheme.cleanLight.rawValue, "cleanLight")
        XCTAssertEqual(RenderTheme.warmPaper.rawValue, "warmPaper")
        XCTAssertEqual(RenderTheme.dark.rawValue, "dark")
    }

    func testPreferenceDefaultsToCleanLightWithoutWritingASelection() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preference = RenderThemePreference(defaults: defaults)

        XCTAssertEqual(preference.selectedTheme, .cleanLight)
        XCTAssertNil(defaults.object(forKey: RenderThemePreference.defaultsKey))
    }

    func testPreferenceRemembersOnlySupportedExplicitSelections() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preference = RenderThemePreference(defaults: defaults)

        preference.select(.dark)

        XCTAssertEqual(
            RenderThemePreference(defaults: defaults).selectedTheme,
            .dark
        )
        defaults.set("system", forKey: RenderThemePreference.defaultsKey)
        XCTAssertEqual(preference.selectedTheme, .cleanLight)
    }

    @MainActor
    func testEveryThemeRendersAllPhaseOneContentWithoutLayoutOrStyleLeakage() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        let sequence: [RenderTheme] = [.cleanLight, .dark, .warmPaper, .cleanLight]
        let expectedBackgrounds: [RenderTheme: NSColor] = [
            .cleanLight: color(0xFF, 0xFF, 0xFF),
            .warmPaper: color(0xFA, 0xF8, 0xF3),
            .dark: color(0x0D, 0x11, 0x17)
        ]
        var renderedSizes: [NSSize] = []

        for theme in sequence {
            let image = try await render(validationMarkdown, with: renderer, theme: theme)
            renderedSizes.append(image.size)

            XCTAssertGreaterThanOrEqual(image.size.width, 1_100, theme.rawValue)
            XCTAssertGreaterThan(image.size.height, 900, theme.rawValue)
            let background = try sampledBackground(in: image)
            assertColor(
                background,
                equals: try XCTUnwrap(expectedBackgrounds[theme]),
                message: theme.rawValue
            )
            XCTAssertEqual(background.alphaComponent, 1, accuracy: 0.001, theme.rawValue)
            XCTAssertTrue(containsVisibleForeground(in: image), theme.rawValue)
        }

        let referenceSize = try XCTUnwrap(renderedSizes.first)
        for size in renderedSizes.dropFirst() {
            XCTAssertEqual(size.width, referenceSize.width, accuracy: 0.5)
            XCTAssertEqual(size.height, referenceSize.height, accuracy: 0.5)
        }
    }

    @MainActor
    func testRendererDefaultsToCleanLight() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        defer { withExtendedLifetime(renderer) {} }
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            renderer.render("# Default theme") { result in
                continuation.resume(with: result)
            }
        }

        assertColor(
            try sampledBackground(in: image),
            equals: color(0xFF, 0xFF, 0xFF),
            message: "default"
        )
    }

    private var validationMarkdown: String {
        """
        # Theme validation

        Prose with **emphasis**, [a local label](#theme-validation), and `inline code`.

        > Every bundled theme keeps the same typography and spacing.

        | Surface | Status | Detail |
        |:--|:--:|:--|
        | Markdown | Ready | Opaque background |
        | Highlighting | Ready | Theme-specific colors |

        ```swift
        struct RenderRequest {
            let theme: String
            let isLocal = true
        }
        ```

        ```mermaid
        flowchart LR
            Source[Markdown] --> Render{Render locally?}
            Render -->|Yes| Image[Opaque PNG]
        ```

        ```mermaid
        sequenceDiagram
            actor User
            participant App as md2png
            participant Renderer
            User->>App: Choose theme
            App->>Renderer: Render fixed palette
            Renderer-->>User: Return PNG
        ```

        ```mermaid
        gantt
            title Theme validation
            dateFormat YYYY-MM-DD
            axisFormat %b %d
            section Render
            Markdown and table :done, markdown, 2026-08-17, 1d
            Code highlighting  :active, code, after markdown, 1d
            Mermaid diagrams   :diagram, after code, 1d
        ```
        """
    }

    @MainActor
    private func render(
        _ markdown: String,
        with renderer: MarkdownRenderer,
        theme: RenderTheme
    ) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            renderer.render(markdown, widthPreset: .wide, theme: theme) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func sampledBackground(in image: NSImage) throws -> NSColor {
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB))
    }

    private func containsVisibleForeground(in image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let background = bitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB) else {
            return false
        }

        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
                guard let sample = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if colorDistance(sample, background) > 0.18 {
                    return true
                }
            }
        }
        return false
    }

    private func assertColor(
        _ actual: NSColor,
        equals expected: NSColor,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // WKSnapshot output may be color-managed before conversion to device RGB.
        XCTAssertLessThan(
            colorDistance(actual, expected),
            0.08,
            message,
            file: file,
            line: line
        )
    }

    private func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        abs(lhs.redComponent - rhs.redComponent)
            + abs(lhs.greenComponent - rhs.greenComponent)
            + abs(lhs.blueComponent - rhs.blueComponent)
    }

    private func color(_ red: Int, _ green: Int, _ blue: Int) -> NSColor {
        NSColor(
            deviceRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "MD2PNGRenderThemeTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
