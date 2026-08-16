import AppKit
import Foundation
import XCTest
@testable import MD2PNG

final class FeatureTests: XCTestCase {
    private let testProjectURL = URL(string: "https://github.com/owner/md2png")!

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
            "渲染内容过大（1200 × 3400）。请尝试缩短内容。"
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

    private func localizationStrings(in bundle: Bundle) throws -> [String: String] {
        let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
    }

    @MainActor
    func testAboutWindowHasStructuredLayout() throws {
        _ = NSApplication.shared
        let controller = makeAboutController()
        controller.show(metadata: AppMetadata(
            version: "0.1.0",
            build: "1",
            sourceCommit: "A1B2C3D4E5F6789012345678901234567890ABCD",
            buildConfiguration: .debug,
            releaseNotes: """
            Added
            • More focused Markdown samples.
            • Manual update link with no background request.

            Changed
            • Easier global shortcuts and a compact clipboard preview.
            """,
            projectURL: testProjectURL
        ))
        defer { controller.close() }

        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)
        XCTAssertEqual(
            window.title,
            L10n.text("about.window_title", defaultValue: "About md2png")
        )
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, NSSize(width: 560, height: 490))
        XCTAssertGreaterThanOrEqual(contentView.subviews.count, 8)
        XCTAssertEqual(controller.displayedBuildConfiguration, .debug)
        XCTAssertEqual(
            controller.displayedProjectButtonTitle,
            L10n.text("about.open_project", defaultValue: "Open Project")
        )
        XCTAssertEqual(
            controller.displayedUpdateButtonTitle,
            L10n.text("about.update_check_again", defaultValue: "Check Again")
        )
        XCTAssertFalse(controller.displayedUpdateButtonIsHidden)
        XCTAssertEqual(
            controller.displayedUpdateStatus,
            L10n.format(
                "about.update_up_to_date",
                defaultValue: "Up to Date · %@",
                "0.1.0"
            )
        )
        XCTAssertEqual(
            controller.displayedCopyVersionButtonToolTip,
            L10n.text("about.copy_version_info", defaultValue: "Copy Version Info")
        )
        XCTAssertTrue(controller.displayedVersionInfo.contains("0.1.0 (1)"))
        XCTAssertTrue(controller.displayedVersionBuild.contains("Commit a1b2c3d"))
        XCTAssertTrue(controller.displayedVersionInfo.contains("commit a1b2c3d"))

        if let outputPath = ProcessInfo.processInfo.environment["MD2PNG_ABOUT_SNAPSHOT_PATH"],
           let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) {
            contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: outputPath))
            }
        }
    }

    @MainActor
    func testAboutManualCheckShowsProgressAndRecentCompletionFeedback() {
        _ = NSApplication.shared
        let phase = UpdatePhase.upToDate(version: SemanticVersion("0.1.0")!)
        let retryAt = Date().addingTimeInterval(60)
        let metadata = AppMetadata(
            version: "0.1.0",
            build: "1",
            buildConfiguration: .debug,
            releaseNotes: "Changed\n• Clear manual update feedback.",
            projectURL: testProjectURL
        )

        let checkingController = makeAboutController(
            phase: phase,
            isChecking: true,
            nextManualCheckAt: retryAt,
            manualCheckFeedback: .checking
        )
        checkingController.show(metadata: metadata)
        XCTAssertEqual(
            checkingController.displayedUpdateButtonTitle,
            L10n.text("about.update_checking", defaultValue: "Checking…")
        )
        checkingController.close()

        let completedController = makeAboutController(
            phase: phase,
            nextManualCheckAt: retryAt,
            manualCheckFeedback: .completed
        )
        completedController.show(metadata: metadata)
        XCTAssertEqual(
            completedController.displayedUpdateButtonTitle,
            L10n.text("about.update_checked_recently", defaultValue: "Checked just now")
        )
        completedController.close()

        let cooldownController = makeAboutController(
            phase: phase,
            nextManualCheckAt: retryAt
        )
        cooldownController.show(metadata: metadata)
        XCTAssertEqual(
            cooldownController.displayedUpdateButtonTitle,
            L10n.text("about.update_check_again_later", defaultValue: "Check Again Later")
        )
        cooldownController.close()

        let failedController = makeAboutController(
            phase: .failed(
                message: UpdateError.networkUnavailable.localizedDescription,
                releasesURL: testProjectURL.appendingPathComponent("releases"),
                retryAt: retryAt,
                availableUpdate: nil
            ),
            nextManualCheckAt: retryAt
        )
        failedController.show(metadata: metadata)
        XCTAssertEqual(
            failedController.displayedUpdateButtonTitle,
            L10n.text("about.update_try_again_later", defaultValue: "Try Again Later")
        )
        failedController.close()
    }

    @MainActor
    func testAboutWindowSeparatesFailureSummaryFromLongDetailAndActions() throws {
        _ = NSApplication.shared
        let message = UpdateError.networkUnavailable.localizedDescription
        let controller = makeAboutController(phase: .failed(
            message: message,
            releasesURL: URL(string: "https://github.com/owner/md2png/releases"),
            retryAt: nil,
            availableUpdate: nil
        ))
        controller.show(metadata: AppMetadata(
            version: "0.1.0",
            build: "1",
            buildConfiguration: .debug,
            releaseNotes: "Added\n• Failure layout coverage.",
            projectURL: testProjectURL
        ))
        defer { controller.close() }

        XCTAssertEqual(
            controller.displayedUpdateStatus,
            L10n.text("about.update_check_failed", defaultValue: "Update check failed")
        )
        XCTAssertEqual(controller.displayedUpdateDetail, message)
        XCTAssertEqual(
            controller.displayedUpdateButtonTitle,
            L10n.text("about.update_retry_check", defaultValue: "Try Again")
        )
        XCTAssertFalse(controller.displayedReleasesFallbackIsHidden)
        XCTAssertEqual(controller.displayedDescriptionFrame.height, 20, accuracy: 0.5)
        XCTAssertEqual(
            controller.displayedDescriptionFrame.maxX,
            controller.displayedUpdateCardFrame.maxX,
            accuracy: 2.5
        )

        if let outputPath = ProcessInfo.processInfo.environment[
            "MD2PNG_ABOUT_FAILURE_SNAPSHOT_PATH"
        ], let contentView = controller.window?.contentView,
           let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) {
            contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: outputPath))
            }
        }
    }

    @MainActor
    func testAboutDownloadFailureWrapsCompleteIntegrityMessage() throws {
        _ = NSApplication.shared
        let message = UpdateError.digestMismatch.localizedDescription
        let update = AvailableUpdate(
            version: SemanticVersion("0.2.0")!,
            tagName: "v0.2.0",
            assetName: "md2png-0.2.0-macOS-arm64-developer-id.dmg",
            downloadURL: URL(string:
                "https://github.com/owner/md2png/releases/download/v0.2.0/md2png-0.2.0-macOS-arm64-developer-id.dmg"
            )!,
            size: 1,
            sha256: String(repeating: "0", count: 64)
        )
        let controller = makeAboutController(phase: .failed(
            message: message,
            releasesURL: URL(string: "https://github.com/owner/md2png/releases"),
            retryAt: nil,
            availableUpdate: update
        ))
        controller.show(metadata: AppMetadata(
            version: "0.1.0",
            build: "1",
            buildConfiguration: .debug,
            releaseNotes: "Added\n• Download failure layout coverage.",
            projectURL: testProjectURL
        ))
        defer { controller.close() }

        XCTAssertEqual(controller.displayedUpdateDetail, message)
        XCTAssertEqual(controller.displayedUpdateDetailMaximumNumberOfLines, 2)
        XCTAssertEqual(controller.displayedUpdateDetailLineBreakMode, .byWordWrapping)

        if let outputPath = ProcessInfo.processInfo.environment[
            "MD2PNG_ABOUT_DOWNLOAD_FAILURE_SNAPSHOT_PATH"
        ], let contentView = controller.window?.contentView,
           let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) {
            contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: outputPath))
            }
        }
    }

    @MainActor
    func testAboutReadyStatusCanBeSelectedAndOffersOpenAgain() throws {
        _ = NSApplication.shared
        let update = AvailableUpdate(
            version: SemanticVersion("0.2.0")!,
            tagName: "v0.2.0",
            assetName: "md2png-0.2.0-macOS-arm64-developer-id.dmg",
            downloadURL: URL(string:
                "https://github.com/owner/md2png/releases/download/v0.2.0/md2png-0.2.0-macOS-arm64-developer-id.dmg"
            )!,
            size: 1,
            sha256: String(repeating: "0", count: 64)
        )
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            update.assetName
        )
        let controller = makeAboutController(phase: .readyToInstall(
            update: update,
            fileURL: fileURL
        ))
        controller.show(metadata: AppMetadata(
            version: "0.1.0",
            build: "1",
            buildConfiguration: .debug,
            releaseNotes: "Added\n• Reopen downloaded DMGs.",
            projectURL: testProjectURL
        ))
        defer { controller.close() }

        XCTAssertEqual(
            controller.displayedUpdateButtonTitle,
            L10n.text("about.update_open_again", defaultValue: "Open")
        )
        XCTAssertEqual(
            controller.displayedSecondaryUpdateButtonTitle,
            L10n.text("about.update_show_in_finder", defaultValue: "Show in Finder")
        )
        XCTAssertEqual(
            controller.displayedUpdateDetail,
            L10n.text(
                "about.update_ready_detail",
                defaultValue: "Downloaded — open the DMG and drag md2png into Applications."
            )
        )
        controller.selectAllUpdateStatusForTesting()
        XCTAssertEqual(
            controller.displayedUpdateStatusSelectedRange,
            NSRange(location: 0, length: (controller.displayedUpdateStatus as NSString).length)
        )

        if let outputPath = ProcessInfo.processInfo.environment[
            "MD2PNG_ABOUT_READY_SNAPSHOT_PATH"
        ], let contentView = controller.window?.contentView,
           let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) {
            contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: outputPath))
            }
        }
    }

    @MainActor
    func testAboutUpdateCardResizesWithoutMovingChangelog() throws {
        _ = NSApplication.shared
        let metadata = AppMetadata(
            version: "0.1.0",
            build: "1",
            buildConfiguration: .debug,
            releaseNotes: "Added\n• Stable update layout.",
            projectURL: testProjectURL
        )

        let compactController = makeAboutController()
        compactController.show(metadata: metadata)
        let compactCardFrame = compactController.displayedUpdateCardFrame
        let compactDescriptionFrame = compactController.displayedDescriptionFrame
        let compactHeadingFrame = compactController.displayedReleaseHeadingFrame
        compactController.close()

        let expandedController = makeAboutController(phase: .failed(
            message: UpdateError.networkUnavailable.localizedDescription,
            releasesURL: URL(string: "https://github.com/owner/md2png/releases"),
            retryAt: nil,
            availableUpdate: nil
        ))
        expandedController.show(metadata: metadata)
        defer { expandedController.close() }
        let expandedCardFrame = expandedController.displayedUpdateCardFrame
        let expandedDescriptionFrame = expandedController.displayedDescriptionFrame
        let expandedHeadingFrame = expandedController.displayedReleaseHeadingFrame

        XCTAssertEqual(compactCardFrame.height, 36, accuracy: 0.5)
        XCTAssertEqual(expandedCardFrame.height, 66, accuracy: 0.5)
        XCTAssertGreaterThan(compactDescriptionFrame.minY, compactCardFrame.maxY)
        XCTAssertEqual(
            compactDescriptionFrame.height,
            expandedDescriptionFrame.height,
            accuracy: 0.5
        )
        XCTAssertEqual(
            compactHeadingFrame.origin.y,
            expandedHeadingFrame.origin.y,
            accuracy: 0.5
        )
        XCTAssertEqual(
            compactHeadingFrame.height,
            expandedHeadingFrame.height,
            accuracy: 0.5
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

    func testRenderActivityRejectsReentryUntilFinished() {
        var activity = RenderActivityState()

        XCTAssertTrue(activity.begin())
        XCTAssertTrue(activity.isRendering)
        XCTAssertFalse(activity.begin())
        activity.finish()
        XCTAssertFalse(activity.isRendering)
        XCTAssertTrue(activity.begin())
    }

    @MainActor
    func testHUDLayoutSupportsTwoLinesAndVisibleFramePlacement() {
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
    func testAboutWindowCanShowReleaseBuild() {
        _ = NSApplication.shared
        let controller = makeAboutController()
        controller.show(metadata: AppMetadata(
            version: "0.1.0",
            build: "1",
            buildConfiguration: .release,
            releaseNotes: "Added\n\n• Release build badge.",
            projectURL: testProjectURL
        ))
        defer { controller.close() }

        XCTAssertEqual(controller.displayedBuildConfiguration, .release)
    }

    @MainActor
    func testAboutHidesRepositoryActionsWithoutPackagedURL() {
        _ = NSApplication.shared
        let controller = makeAboutController()
        controller.show(metadata: AppMetadata(
            version: "0.1.0",
            build: "1",
            buildConfiguration: .debug,
            releaseNotes: "No repository URL in this local build.",
            projectURL: nil
        ))
        defer { controller.close() }

        XCTAssertTrue(controller.displayedProjectButtonIsHidden)
        XCTAssertTrue(controller.displayedUpdateButtonIsHidden)
    }

    @MainActor
    func testAboutKeepsProjectLinkButHidesUpdatesForDisabledChannel() {
        _ = NSApplication.shared
        let controller = AboutController(updateController: UpdateController(
            channel: { .disabled }
        ))
        controller.show(metadata: AppMetadata(
            version: "0.1.0",
            build: "1",
            buildConfiguration: .debug,
            releaseNotes: "Debug builds do not use production updates.",
            projectURL: testProjectURL
        ))
        defer { controller.close() }

        XCTAssertFalse(controller.displayedProjectButtonIsHidden)
        XCTAssertTrue(controller.displayedUpdateButtonIsHidden)
    }

    @MainActor
    func testAboutOfflineFixtureDisablesProductionDownloadAction() {
        _ = NSApplication.shared
        let update = UpdateTestFixtures.availableUpdate()
        let updateController = UpdateController(channel: { .disabled })
        updateController.setStatusForTesting(UpdateStatus(
            phase: .updateAvailable(update)
        ))
        let controller = AboutController(updateController: updateController)
        controller.show(metadata: AppMetadata(
            version: "0.1.0",
            build: "1",
            buildConfiguration: .debug,
            releaseNotes: "Debug fixtures stay offline.",
            projectURL: testProjectURL
        ))
        defer { controller.close() }

        XCTAssertFalse(controller.displayedUpdateButtonIsHidden)
        XCTAssertEqual(
            controller.displayedUpdateButtonTitle,
            L10n.text("about.update_download", defaultValue: "Download Update")
        )
        XCTAssertFalse(controller.displayedUpdateButtonIsEnabled)
    }

    @MainActor
    func testAboutReleaseNotesStartScrolledToTop() {
        _ = NSApplication.shared
        let controller = makeAboutController()
        let notes = (["Added"] + (1...30).map { "• Change \($0)" })
            .joined(separator: "\n")
        controller.show(metadata: AppMetadata(
            version: "0.1.0",
            build: "1",
            buildConfiguration: .debug,
            releaseNotes: notes,
            projectURL: testProjectURL
        ))
        defer { controller.close() }

        XCTAssertEqual(controller.releaseNotesVisibleOrigin, .zero)
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

    @MainActor
    private func makeAboutController(
        phase: UpdatePhase = .upToDate(version: SemanticVersion("0.1.0")!),
        isChecking: Bool = false,
        nextManualCheckAt: Date? = nil,
        manualCheckFeedback: ManualCheckFeedback = .none
    ) -> AboutController {
        let repository = GitHubRepository(projectURL: testProjectURL)!
        let updateController = UpdateController(
            channel: { .stableGitHubReleases(repository: repository) }
        )
        updateController.setStatusForTesting(UpdateStatus(
            phase: phase,
            isChecking: isChecking,
            nextManualCheckAt: nextManualCheckAt,
            manualCheckFeedback: manualCheckFeedback
        ))
        return AboutController(updateController: updateController)
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
