import AppKit
import Foundation
import XCTest
@testable import MD2PNG

final class AboutControllerTests: XCTestCase {
    private let testProjectURL = URL(string: "https://github.com/owner/md2png")!

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
        XCTAssertEqual(
            window.contentRect(forFrameRect: window.frame).size,
            NSSize(width: 560, height: 490)
        )
        XCTAssertTrue(controller.usesSwiftUIHostingBoundary)
        XCTAssertEqual(contentView.bounds.size, AboutLayout.windowSize)
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

        writeSnapshotIfRequested(
            environmentKey: "MD2PNG_ABOUT_SNAPSHOT_PATH",
            contentView: contentView
        )
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
        XCTAssertEqual(
            controller.displayedUpdateCardHeight,
            AboutLayout.detailedUpdateHeight,
            accuracy: 0.5
        )

        writeSnapshotIfRequested(
            environmentKey: "MD2PNG_ABOUT_FAILURE_SNAPSHOT_PATH",
            contentView: try XCTUnwrap(controller.window?.contentView)
        )
    }

    @MainActor
    func testAboutDownloadFailureWrapsCompleteIntegrityMessage() throws {
        _ = NSApplication.shared
        let message = UpdateError.digestMismatch.localizedDescription
        let update = UpdateTestFixtures.availableUpdate()
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

        writeSnapshotIfRequested(
            environmentKey: "MD2PNG_ABOUT_DOWNLOAD_FAILURE_SNAPSHOT_PATH",
            contentView: try XCTUnwrap(controller.window?.contentView)
        )
    }

    @MainActor
    func testAboutReadyStatusCanBeSelectedAndOffersOpenAgain() throws {
        _ = NSApplication.shared
        let update = UpdateTestFixtures.availableUpdate()
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
        XCTAssertTrue(controller.displayedUpdateStatusIsSelectable)
        controller.selectAllUpdateStatusForTesting()
        XCTAssertEqual(
            controller.displayedUpdateStatusSelectedRange,
            NSRange(location: 0, length: (controller.displayedUpdateStatus as NSString).length)
        )

        writeSnapshotIfRequested(
            environmentKey: "MD2PNG_ABOUT_READY_SNAPSHOT_PATH",
            contentView: try XCTUnwrap(controller.window?.contentView)
        )
    }

    @MainActor
    func testAboutUpdateCardKeepsCompactAndDetailedHeightsInHostingBoundary() {
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
        let compactCardHeight = compactController.displayedUpdateCardHeight
        let compactWindowSize = compactController.window?.contentView?.bounds.size
        compactController.close()

        let expandedController = makeAboutController(phase: .failed(
            message: UpdateError.networkUnavailable.localizedDescription,
            releasesURL: URL(string: "https://github.com/owner/md2png/releases"),
            retryAt: nil,
            availableUpdate: nil
        ))
        expandedController.show(metadata: metadata)
        defer { expandedController.close() }
        let expandedCardHeight = expandedController.displayedUpdateCardHeight
        let expandedWindowSize = expandedController.window?.contentView?.bounds.size

        XCTAssertEqual(compactCardHeight, AboutLayout.compactUpdateHeight, accuracy: 0.5)
        XCTAssertEqual(expandedCardHeight, AboutLayout.detailedUpdateHeight, accuracy: 0.5)
        XCTAssertEqual(compactWindowSize, AboutLayout.windowSize)
        XCTAssertEqual(expandedWindowSize, AboutLayout.windowSize)
        XCTAssertTrue(expandedController.usesSwiftUIHostingBoundary)
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
    func testAboutSeamlessUpdateFixtureShowsSignedNotesAndKeepsActionsOffline() throws {
        _ = NSApplication.shared
        let update = UpdateTestFixtures.seamlessUpdate()
        let availableController = makeAboutController(
            phase: .sparkleUpdateAvailable(update)
        )
        availableController.show(metadata: AppMetadata(
            version: "0.7.0",
            build: "7",
            buildConfiguration: .debug,
            releaseNotes: "Installed release notes",
            projectURL: testProjectURL
        ))
        defer { availableController.close() }

        XCTAssertEqual(availableController.displayedUpdateButtonTitle, "Download Update")
        XCTAssertFalse(availableController.displayedUpdateButtonIsEnabled)
        XCTAssertEqual(availableController.displayedReleaseNotesTitle, "What’s new in 0.8.0")
        XCTAssertTrue(availableController.displayedReleaseNotesText.contains("Seamless updates"))
        XCTAssertFalse(availableController.displayedReleaseNotesText.contains("Installed release notes"))
        XCTAssertTrue(availableController.displaysFullReleaseNotesAction)

        let readyController = makeAboutController(
            phase: .sparkleReadyToInstall(update)
        )
        readyController.show(metadata: AppMetadata(
            version: "0.7.0",
            build: "7",
            buildConfiguration: .debug,
            releaseNotes: "Installed release notes",
            projectURL: testProjectURL
        ))
        defer { readyController.close() }

        XCTAssertEqual(readyController.displayedUpdateButtonTitle, "Install and Relaunch")
        XCTAssertFalse(readyController.displayedUpdateButtonIsEnabled)
        XCTAssertEqual(readyController.displayedSecondaryUpdateButtonTitle, "Later")
        XCTAssertEqual(
            readyController.displayedUpdateDetail,
            L10n.text(
                "about.update_relaunch_memory_detail",
                defaultValue: "Relaunch clears Last Render and Last Source. The clipboard is unchanged."
            )
        )

        writeSnapshotIfRequested(
            environmentKey: "MD2PNG_ABOUT_SEAMLESS_READY_SNAPSHOT_PATH",
            contentView: try XCTUnwrap(readyController.window?.contentView)
        )

        writeSnapshotIfRequested(
            environmentKey: "MD2PNG_ABOUT_SEAMLESS_UPDATE_SNAPSHOT_PATH",
            contentView: try XCTUnwrap(availableController.window?.contentView)
        )
    }

    @MainActor
    func testClosingReadyAboutExplicitlyCancelsInstallOnQuit() {
        _ = NSApplication.shared
        let driver = AboutCloseUpdateDriver()
        let updateController = UpdateController(
            channel: { .stableGitHubReleases(
                repository: GitHubRepository(projectURL: self.testProjectURL)!
            ) },
            updateDriver: driver
        )
        updateController.setStatusForTesting(UpdateStatus(
            phase: .sparkleReadyToInstall(UpdateTestFixtures.seamlessUpdate())
        ))
        let controller = AboutController(updateController: updateController)
        controller.show(metadata: AppMetadata(
            version: "0.7.0",
            build: "7",
            buildConfiguration: .debug,
            releaseNotes: "Installed release notes",
            projectURL: testProjectURL
        ))

        controller.close()

        XCTAssertEqual(driver.deferCount, 1)
    }

    @MainActor
    func testAboutReleaseNotesResetScrollIdentityEveryTimeWindowIsShown() {
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

        let initialRevision = controller.displayedReleaseNotesRevision
        controller.show(metadata: AppMetadata(
            version: "0.1.1",
            build: "2",
            buildConfiguration: .debug,
            releaseNotes: "Fixed\n• Reset release notes to their beginning.",
            projectURL: testProjectURL
        ))

        XCTAssertEqual(controller.displayedReleaseNotesRevision, initialRevision + 1)
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

    @MainActor
    private func writeSnapshotIfRequested(
        environmentKey: String,
        contentView: NSView
    ) {
        guard let outputPath = ProcessInfo.processInfo.environment[environmentKey],
              let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            return
        }
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: outputPath))
        }
    }
}

@MainActor
private final class AboutCloseUpdateDriver: UpdateDriving {
    private(set) var deferCount = 0

    func setEventHandler(_ handler: @escaping @MainActor (UpdateDriverEvent) -> Void) {}

    func probe(
        installedVersion: String,
        completion: @escaping @MainActor (UpdateProbeResult) -> Void
    ) {}

    func downloadUpdate(expectedBuildVersion: String) {}

    func cancelDownload() {}

    func deferInstallation(
        completion: (@MainActor () -> Void)?
    ) -> Bool {
        deferCount += 1
        return true
    }

    func installAndRelaunch() -> Bool { false }
}
