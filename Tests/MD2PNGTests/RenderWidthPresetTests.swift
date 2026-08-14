import AppKit
import XCTest
@testable import MD2PNG

final class RenderWidthPresetTests: XCTestCase {
    func testPresetsHaveStableIncreasingMaximumWidths() {
        XCTAssertEqual(RenderWidthPreset.allCases, [.compact, .standard, .wide])
        XCTAssertEqual(RenderWidthPreset.compact.cardMaximumWidth, 720)
        XCTAssertEqual(RenderWidthPreset.standard.cardMaximumWidth, 1_120)
        XCTAssertEqual(RenderWidthPreset.wide.cardMaximumWidth, 1_520)
    }

    func testPreferenceDefaultsToStandardWithoutWritingASelection() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preference = RenderWidthPreference(defaults: defaults)

        XCTAssertEqual(preference.selectedPreset, .standard)
        XCTAssertNil(defaults.object(forKey: RenderWidthPreference.defaultsKey))
    }

    func testPreferenceRemembersOnlySupportedExplicitSelections() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preference = RenderWidthPreference(defaults: defaults)

        preference.select(.wide)

        XCTAssertEqual(
            RenderWidthPreference(defaults: defaults).selectedPreset,
            .wide
        )
        defaults.set("custom", forKey: RenderWidthPreference.defaultsKey)
        XCTAssertEqual(preference.selectedPreset, .standard)
    }

    @MainActor
    func testRendererAppliesEachPresetAndKeepsStandardAsDefault() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let markdown = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Examples/width-presets.md"
            ),
            encoding: .utf8
        )

        var renderedWidths: [RenderWidthPreset: CGFloat] = [:]
        for preset in RenderWidthPreset.allCases {
            let image = try await render(
                markdown,
                with: renderer,
                widthPreset: preset
            )
            renderedWidths[preset] = image.size.width
            XCTAssertEqual(
                image.size.width,
                CGFloat(preset.cardMaximumWidth),
                accuracy: 0.5,
                preset.rawValue
            )
            try writeReferenceImageIfRequested(image, preset: preset)
        }

        let defaultImage = try await render(markdown, with: renderer)
        let standardWidth = try XCTUnwrap(renderedWidths[.standard])
        XCTAssertEqual(
            defaultImage.size.width,
            standardWidth,
            accuracy: 0.5
        )
    }

    @MainActor
    private func writeReferenceImageIfRequested(
        _ image: NSImage,
        preset: RenderWidthPreset
    ) throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment[
            "MD2PNG_WIDTH_PRESET_SNAPSHOT_DIR"
        ], let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            .appendingPathComponent("width-preset-\(preset.rawValue).png")
        try png.write(to: outputURL, options: .atomic)
    }

    @MainActor
    private func render(
        _ markdown: String,
        with renderer: MarkdownRenderer,
        widthPreset: RenderWidthPreset? = nil
    ) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            if let widthPreset {
                renderer.render(markdown, widthPreset: widthPreset) { result in
                    continuation.resume(with: result)
                }
            } else {
                renderer.render(markdown) { result in
                    continuation.resume(with: result)
                }
            }
        }
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "MD2PNGRenderWidthTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
