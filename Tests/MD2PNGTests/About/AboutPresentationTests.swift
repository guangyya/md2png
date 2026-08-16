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

    func testSparkleUpdatePresentationReopensTheStandardWindow() {
        let presentation = makePresentation(status: UpdateStatus(
            phase: .sparkleUpdateAvailable(displayVersion: "0.7.0")
        ))

        XCTAssertEqual(presentation.title, "Update available · 0.7.0")
        XCTAssertEqual(presentation.primaryAction?.title, "Show Update")
        XCTAssertEqual(presentation.primaryAction?.action, .showUpdate)
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

    func testDownloadAndActiveProgressPresentExpectedActions() {
        let update = UpdateTestFixtures.availableUpdate()
        let unavailable = makePresentation(
            status: UpdateStatus(phase: .updateAvailable(update)),
            canDownload: false
        )
        XCTAssertEqual(unavailable.symbolName, "arrow.down.circle.fill")
        XCTAssertEqual(unavailable.primaryAction?.action, .download)
        XCTAssertEqual(unavailable.primaryAction?.title, "Download Update")
        XCTAssertEqual(unavailable.primaryAction?.isEnabled, false)
        XCTAssertEqual(unavailable.primaryAction?.isEmphasized, true)

        let downloading = makePresentation(status: UpdateStatus(
            phase: .downloading(update, progressPercent: 42)
        ))
        XCTAssertEqual(downloading.title, "Downloading md2png 0.2.0 — 42%")
        XCTAssertEqual(downloading.primaryAction?.action, .cancel)
        XCTAssertEqual(downloading.primaryAction?.title, "Cancel")

        let verifying = makePresentation(status: UpdateStatus(phase: .verifying(update)))
        XCTAssertEqual(verifying.primaryAction?.action, .cancel)

        let opening = makePresentation(status: UpdateStatus(phase: .opening(update)))
        XCTAssertNil(opening.primaryAction)
    }

    func testReadyToInstallHasOpenAndFinderActions() {
        let update = UpdateTestFixtures.availableUpdate()
        let presentation = makePresentation(status: UpdateStatus(phase: .readyToInstall(
            update: update,
            fileURL: URL(fileURLWithPath: "/tmp/update.dmg")
        )))

        XCTAssertEqual(presentation.tint, .green)
        XCTAssertEqual(presentation.title, "Ready to install · 0.2.0")
        XCTAssertEqual(
            presentation.detail,
            "Downloaded — open the DMG and drag md2png into Applications."
        )
        XCTAssertEqual(presentation.primaryAction?.action, .openDownloadedUpdate)
        XCTAssertEqual(presentation.primaryAction?.title, "Open")
        XCTAssertEqual(presentation.secondaryAction?.action, .revealDownloadedUpdate)
        XCTAssertEqual(presentation.secondaryAction?.title, "Show in Finder")
    }

    func testFailurePresentationDistinguishesCheckAndDownloadRecovery() {
        let retryAt = Date(timeIntervalSince1970: 1_000)
        let checkFailure = makePresentation(status: UpdateStatus(
            phase: .failed(
                message: "Offline",
                releasesURL: URL(string: "https://github.com/owner/md2png/releases"),
                retryAt: retryAt,
                availableUpdate: nil
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

        let update = UpdateTestFixtures.availableUpdate()
        let downloadFailure = makePresentation(
            status: UpdateStatus(phase: .failed(
                message: "Invalid download",
                releasesURL: nil,
                retryAt: nil,
                availableUpdate: update
            )),
            canDownload: true
        )
        XCTAssertEqual(downloadFailure.title, "Download failed")
        XCTAssertEqual(downloadFailure.primaryAction?.action, .download)
        XCTAssertEqual(downloadFailure.primaryAction?.title, "Retry Download")
        XCTAssertEqual(downloadFailure.primaryAction?.isEnabled, true)
        XCTAssertNil(downloadFailure.secondaryAction)
    }

    private func makePresentation(
        status: UpdateStatus,
        canDownload: Bool = true
    ) -> AboutUpdatePresentation {
        AboutUpdatePresentation.make(
            status: status,
            allowsInteractiveCheck: true,
            canDownload: { _ in canDownload },
            localizationBundle: english,
            retryTimeText: { _ in "12:34" }
        )
    }
}
