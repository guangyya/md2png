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
            if theme == .warmPaper {
                try assertWarmPaperPalette(in: image)
                let plainCodeImage = try await render(
                    """
                    ```
                    plain code text
                    ```
                    """,
                    with: renderer,
                    theme: .warmPaper
                )
                try assertWarmPaperPlainCodeText(in: plainCodeImage)
            }
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
            let label = "Warm Paper"
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

    private func assertWarmPaperPalette(
        in image: NSImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let background = color(0xFA, 0xF8, 0xF3)
        let codeSurface = color(0xEC, 0xE7, 0xDE)
        let codeText = color(0x34, 0x2F, 0x29)
        let renderedColors: [(
            name: String,
            color: NSColor,
            minimumPixels: Int,
            tolerance: CGFloat
        )] = [
            ("code surface", codeSurface, 100, 0.08),
            ("syntax keyword", color(0x96, 0x37, 0x43), 3, 0.26),
            ("syntax string", color(0x6C, 0x4D, 0x13), 3, 0.26),
            ("syntax title", color(0x68, 0x4A, 0x92), 3, 0.26),
            ("syntax variable", color(0x24, 0x5B, 0x73), 3, 0.26),
            ("Mermaid secondary surface", color(0xE7, 0xE5, 0xC7), 100, 0.08),
            ("Mermaid tertiary surface", color(0xF4, 0xD8, 0xBC), 10, 0.08)
        ]

        XCTAssertGreaterThan(
            colorDistance(background, codeSurface),
            0.18,
            "Warm Paper code blocks must remain visually distinct from the page",
            file: file,
            line: line
        )
        assertContrast(
            codeText,
            against: codeSurface,
            atLeast: 7,
            message: "Warm Paper code text",
            file: file,
            line: line
        )
        for expected in renderedColors where expected.name.hasPrefix("syntax") {
            assertContrast(
                expected.color,
                against: codeSurface,
                atLeast: 4.5,
                message: expected.name,
                file: file,
                line: line
            )
        }
        assertContrast(
            color(0x3D, 0x34, 0x28),
            against: color(0xE7, 0xE5, 0xC7),
            atLeast: 4.5,
            message: "Warm Paper Mermaid secondary surface",
            file: file,
            line: line
        )
        assertContrast(
            color(0x3D, 0x34, 0x28),
            against: color(0xF4, 0xD8, 0xBC),
            atLeast: 4.5,
            message: "Warm Paper Mermaid tertiary surface",
            file: file,
            line: line
        )

        let tiff = try XCTUnwrap(image.tiffRepresentation, file: file, line: line)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff), file: file, line: line)
        var hitCounts = Array(repeating: 0, count: renderedColors.count)
        var nearestDistances = Array(
            repeating: CGFloat.greatestFiniteMagnitude,
            count: renderedColors.count
        )

        scan: for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let sample = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                for index in renderedColors.indices {
                    let distance = colorDistance(sample, renderedColors[index].color)
                    nearestDistances[index] = min(nearestDistances[index], distance)
                    if hitCounts[index] < renderedColors[index].minimumPixels
                        && distance < renderedColors[index].tolerance {
                        hitCounts[index] += 1
                    }
                }
                if renderedColors.indices.allSatisfy({
                    hitCounts[$0] >= renderedColors[$0].minimumPixels
                }) {
                    break scan
                }
            }
        }

        for index in renderedColors.indices {
            XCTAssertGreaterThanOrEqual(
                hitCounts[index],
                renderedColors[index].minimumPixels,
                "Warm Paper render is missing the expected \(renderedColors[index].name) color; "
                    + "nearest distance: \(nearestDistances[index])",
                file: file,
                line: line
            )
        }
    }

    private func assertWarmPaperPlainCodeText(
        in image: NSImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let codeText = color(0x34, 0x2F, 0x29)
        let tiff = try XCTUnwrap(image.tiffRepresentation, file: file, line: line)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff), file: file, line: line)
        var textPixels = 0
        var nearestDistance = CGFloat.greatestFiniteMagnitude

        scan: for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let sample = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let distance = colorDistance(sample, codeText)
                nearestDistance = min(nearestDistance, distance)
                if distance < 0.26 {
                    textPixels += 1
                    if textPixels >= 3 {
                        break scan
                    }
                }
            }
        }

        XCTAssertGreaterThanOrEqual(
            textPixels,
            3,
            "Warm Paper plain code is missing its expected text color; "
                + "nearest distance: \(nearestDistance)",
            file: file,
            line: line
        )
    }

    private func assertContrast(
        _ foreground: NSColor,
        against background: NSColor,
        atLeast minimumRatio: CGFloat,
        message: String,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertGreaterThanOrEqual(
            contrastRatio(foreground, background),
            minimumRatio,
            message,
            file: file,
            line: line
        )
    }

    private func contrastRatio(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        let lhsLuminance = relativeLuminance(lhs)
        let rhsLuminance = relativeLuminance(rhs)
        return (max(lhsLuminance, rhsLuminance) + 0.05)
            / (min(lhsLuminance, rhsLuminance) + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) -> CGFloat {
        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return linearized(color.redComponent) * 0.2126
            + linearized(color.greenComponent) * 0.7152
            + linearized(color.blueComponent) * 0.0722
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
