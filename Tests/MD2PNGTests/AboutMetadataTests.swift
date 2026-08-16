import Foundation
import XCTest
@testable import MD2PNG

final class AboutMetadataTests: XCTestCase {
    private let testProjectURL = URL(string: "https://github.com/owner/md2png")!

    func testAboutChangelogDoesNotFallBackToFullProjectChangelog() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MD2PNGAboutChangelogTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("## [1.0.0]\n\n- Full project details".utf8).write(
            to: root.appendingPathComponent("CHANGELOG.md")
        )

        XCTAssertNil(
            AppResources.aboutChangelogURL(resourcesURL: nil, currentDirectoryURL: root)
        )

        let conciseURL = root.appendingPathComponent("ABOUT_CHANGELOG.md")
        try Data("## [1.0.0]\n\n- Concise highlight".utf8).write(to: conciseURL)

        XCTAssertEqual(
            AppResources.aboutChangelogURL(resourcesURL: nil, currentDirectoryURL: root),
            conciseURL
        )
    }

    func testChangelogParserReturnsOnlyRequestedVersion() {
        let english = L10n.localizedBundle(for: "en")
        let changelog = """
        ## [Unreleased]

        - Future item

        ## [1.2.0] - 2026-08-13

        ### Added

        - A `new` feature.

        ## [1.1.0] - 2026-08-12

        - Old item
        """

        XCTAssertEqual(
            ChangelogParser.releaseNotes(
                for: "1.2.0",
                in: changelog,
                localizationBundle: english
            ),
            "Added\n• A new feature."
        )
        XCTAssertNil(ChangelogParser.releaseNotes(for: "9.9.9", in: changelog))
    }

    func testChangelogParserMergesWrappedBulletsAndCompressesBlankLines() {
        let changelog = """
        ## [1.2.0] - 2026-08-13

        ### Added

        - Add bundled syntax highlighting for common fenced-code languages,
          including Swift, JavaScript, TypeScript, JSON, Shell, and Python.


        - Add focused examples.

        ### Changed

        - Keep the About window compact while release notes remain
          vertically scrollable.

        ## [1.1.0] - 2026-08-12
        """

        XCTAssertEqual(
            ChangelogParser.releaseNotes(for: "1.2.0", in: changelog),
            """
            Added
            • Add bundled syntax highlighting for common fenced-code languages, including Swift, JavaScript, TypeScript, JSON, Shell, and Python.
            • Add focused examples.

            Changed
            • Keep the About window compact while release notes remain vertically scrollable.
            """
        )
    }

    func testBuildConfigurationLabelsAreLocalized() {
#if DEBUG
        XCTAssertEqual(AppBuildConfiguration.current, .debug)
#else
        XCTAssertEqual(AppBuildConfiguration.current, .release)
#endif
        XCTAssertEqual(
            AppBuildConfiguration.debug.displayName(bundle: L10n.localizedBundle(for: "en")),
            "DEBUG"
        )
        XCTAssertEqual(
            AppBuildConfiguration.release.displayName(bundle: L10n.localizedBundle(for: "zh-Hans")),
            "正式版"
        )
    }

    func testVersionInfoIncludesUsefulDiagnosticsAndLocalization() {
        let metadata = AppMetadata(
            version: "0.1.0",
            build: "1",
            sourceCommit: "A1B2C3D4E5F6789012345678901234567890ABCD",
            buildConfiguration: .release,
            releaseNotes: "",
            projectURL: testProjectURL
        )

        XCTAssertEqual(
            metadata.versionInfo(
                macOSVersion: "15.6.0",
                architecture: "arm64",
                localizationBundle: L10n.localizedBundle(for: "en")
            ),
            "md2png 0.1.0 (1) · commit a1b2c3d · RELEASE · macOS 15.6.0 · arm64"
        )
        XCTAssertTrue(
            metadata.versionInfo(
                macOSVersion: "15.6.0",
                architecture: "arm64",
                localizationBundle: L10n.localizedBundle(for: "zh-Hans")
            ).contains("正式版")
        )
    }

    func testSourceCommitIsShortenedAndInvalidValuesAreOmitted() {
        XCTAssertEqual(
            AppMetadata.shortSourceCommit(
                from: " A1B2C3D4E5F6789012345678901234567890ABCD\n"
            ),
            "a1b2c3d"
        )
        XCTAssertNil(AppMetadata.shortSourceCommit(from: "abc123"))
        XCTAssertNil(AppMetadata.shortSourceCommit(from: "not-a-commit"))

        let metadata = AppMetadata(
            version: "0.1.0",
            build: "1",
            sourceCommit: "not-a-commit",
            releaseNotes: "",
            projectURL: nil
        )
        XCTAssertEqual(
            metadata.versionBuildText(localizationBundle: L10n.localizedBundle(for: "en")),
            "Version 0.1.0  •  Build 1"
        )
    }
}
