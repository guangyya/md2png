import Foundation
import XCTest
@testable import MD2PNG

final class AboutPresentationTests: XCTestCase {
    private let english = L10n.localizedBundle(for: "en")

    func testUnknownStatusOffersAnExplicitCheckWithoutClaimingAResult() {
        let presentation = makePresentation(status: UpdateStatus())

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.title, "Updates")
        XCTAssertEqual(presentation.primaryAction?.title, "Check for Updates…")
        XCTAssertEqual(presentation.primaryAction?.action, .checkAgain)
        XCTAssertNil(presentation.secondaryAction)
    }

    func testSparkleUpdatePresentationShowsNotesBeforeDownload() {
        let update = UpdateTestFixtures.seamlessUpdate()
        let presentation = makePresentation(status: UpdateStatus(
            phase: .sparkleUpdateAvailable(update)
        ))

        XCTAssertEqual(presentation.title, "Update available · 0.7.0 → 0.8.0")
        XCTAssertEqual(presentation.primaryAction?.title, "Download Update")
        XCTAssertEqual(presentation.primaryAction?.action, .download)
        XCTAssertEqual(presentation.releaseNotes?.title, "What’s new in 0.8.0")
        XCTAssertTrue(presentation.releaseNotes?.text.contains("Seamless updates") == true)
        XCTAssertEqual(presentation.releaseNotes?.showsFullReleaseNotesAction, true)
    }

    func testSparkleReadyStateRequiresExplicitInstallAndOffersLater() {
        let update = UpdateTestFixtures.seamlessUpdate()
        let downloading = makePresentation(status: UpdateStatus(
            phase: .sparkleDownloading(update, progressPercent: 42)
        ))
        XCTAssertEqual(downloading.title, "Downloading md2png 0.8.0 — 42%")
        XCTAssertEqual(downloading.primaryAction?.action, .cancel)

        let ready = makePresentation(status: UpdateStatus(
            phase: .sparkleReadyToInstall(update)
        ))
        XCTAssertEqual(ready.title, "Ready to install · 0.8.0")
        XCTAssertEqual(ready.primaryAction?.title, "Install and Relaunch")
        XCTAssertEqual(ready.primaryAction?.action, .installAndRelaunch)
        XCTAssertEqual(ready.secondaryAction?.title, "Later")
        XCTAssertEqual(ready.secondaryAction?.action, .installLater)
        XCTAssertTrue(ready.detail?.contains("clipboard is unchanged") == true)
    }

    func testUpToDatePresentationMapsFeedbackAndCooldown() {
        let version = SemanticVersion("0.5.0")!
        let retryAt = Date(timeIntervalSince1970: 1_000)

        let ready = makePresentation(status: UpdateStatus(phase: .upToDate(version: version)))
        XCTAssertEqual(ready.title, "Up to Date · 0.5.0")
        XCTAssertEqual(ready.tint, .green)
        XCTAssertEqual(ready.primaryAction?.action, .checkAgain)
        XCTAssertEqual(ready.primaryAction?.title, "Check Again")
        XCTAssertEqual(ready.primaryAction?.isEnabled, true)

        let checking = makePresentation(status: UpdateStatus(
            phase: .upToDate(version: version),
            isChecking: true,
            nextManualCheckAt: retryAt,
            manualCheckFeedback: .checking
        ))
        XCTAssertEqual(checking.primaryAction?.title, "Checking…")
        XCTAssertEqual(checking.primaryAction?.isEnabled, false)
        XCTAssertEqual(checking.primaryAction?.toolTip, "Try again after 12:34.")

        let completed = makePresentation(status: UpdateStatus(
            phase: .upToDate(version: version),
            nextManualCheckAt: retryAt,
            manualCheckFeedback: .completed
        ))
        XCTAssertEqual(completed.primaryAction?.title, "Checked just now")
        XCTAssertEqual(completed.primaryAction?.isEnabled, false)
    }

    func testFailurePresentationOffersCheckRecoveryAndReleasesFallback() {
        let retryAt = Date(timeIntervalSince1970: 1_000)
        let checkFailure = makePresentation(status: UpdateStatus(
            phase: .failed(
                message: "Offline",
                releasesURL: URL(string: "https://github.com/owner/md2png/releases"),
                retryAt: retryAt
            ),
            nextManualCheckAt: retryAt
        ))
        XCTAssertEqual(checkFailure.tint, .orange)
        XCTAssertEqual(checkFailure.title, "Update check failed")
        XCTAssertEqual(checkFailure.detail, "Offline")
        XCTAssertEqual(checkFailure.primaryAction?.action, .checkAgain)
        XCTAssertEqual(checkFailure.primaryAction?.title, "Try Again Later")
        XCTAssertEqual(checkFailure.primaryAction?.isEnabled, false)
        XCTAssertEqual(checkFailure.primaryAction?.toolTip, "Try again after 12:34.")
        XCTAssertEqual(checkFailure.secondaryAction?.action, .viewReleases)
    }

    private func makePresentation(status: UpdateStatus) -> AboutUpdatePresentation {
        AboutUpdatePresentation.make(
            status: status,
            allowsInteractiveCheck: true,
            localizationBundle: english,
            retryTimeText: { _ in "12:34" }
        )
    }
}
