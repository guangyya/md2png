import XCTest
@testable import MD2PNG

@MainActor
final class UpdateStatusPresenterTests: XCTestCase {
    func testRenderAndInstallStateTakePriorityOverUpdateProgress() {
        let update = UpdateTestFixtures.seamlessUpdate()
        let updateStatus = UpdateStatus(
            phase: .sparkleDownloading(update, progressPercent: 50)
        )

        let rendering = UpdateStatusPresentation.statusItem(
            renderState: renderState(isRendering: true),
            updateStatus: updateStatus
        )
        XCTAssertEqual(rendering.symbolName, "hourglass")
        XCTAssertEqual(rendering.accessibilityLabel, "Rendering")

        let installing = UpdateStatusPresentation.statusItem(
            renderState: renderState(isUpdateInstallPending: true),
            updateStatus: updateStatus
        )
        XCTAssertEqual(installing.symbolName, "arrow.triangle.2.circlepath")
        XCTAssertTrue(installing.accessibilityLabel.contains("installation"))
    }

    func testUpdateProgressMapsToStatusItemAndAccessibleDetail() {
        let update = UpdateTestFixtures.seamlessUpdate()
        let presentation = UpdateStatusPresentation.statusItem(
            renderState: renderState(),
            updateStatus: UpdateStatus(
                phase: .sparkleDownloading(update, progressPercent: 50)
            )
        )

        XCTAssertEqual(presentation.symbolName, "arrow.down.circle")
        XCTAssertTrue(presentation.accessibilityLabel.contains("50%"))
        XCTAssertTrue(presentation.accessibilityLabel.contains(update.displayVersion))
    }

    func testPresenterAnnouncesTransitionsWithoutRepeatingProgressAnnouncements() {
        let harness = UpdateStatusPresenterHarness()
        let presenter = harness.makePresenter()
        let update = UpdateTestFixtures.seamlessUpdate()

        presenter.apply(UpdateStatus(
            phase: .sparkleDownloading(update, progressPercent: 0)
        ))
        presenter.apply(UpdateStatus(
            phase: .sparkleDownloading(update, progressPercent: 50)
        ))

        XCTAssertEqual(harness.announcements.count, 1)
        XCTAssertEqual(harness.statusItems.last?.symbolName, "arrow.down.circle")
        XCTAssertTrue(harness.statusItems.last?.accessibilityLabel.contains("50%") == true)

        presenter.apply(UpdateStatus(phase: .sparkleReadyToInstall(update)))

        XCTAssertEqual(harness.announcements.count, 2)
        XCTAssertEqual(harness.hudMessages.count, 1)
        XCTAssertEqual(harness.hudMessages[0].symbol, "arrow.down.app.fill")
        XCTAssertEqual(harness.hudMessages[0].style, .informational)
    }

    func testVisibleAboutSuppressesRedundantHUDButKeepsAnnouncement() {
        let harness = UpdateStatusPresenterHarness()
        harness.aboutIsVisible = true
        let presenter = harness.makePresenter()
        let update = UpdateTestFixtures.seamlessUpdate()

        presenter.apply(UpdateStatus(
            phase: .sparkleDownloading(update, progressPercent: 25)
        ))
        presenter.apply(UpdateStatus(
            phase: .sparkleFailed(message: "Download failed", update: update)
        ))

        XCTAssertTrue(harness.hudMessages.isEmpty)
        XCTAssertEqual(harness.announcements.last, "Download failed")
    }

    private func renderState(
        isRendering: Bool = false,
        isUpdateInstallPending: Bool = false
    ) -> RenderCoordinatorState {
        RenderCoordinatorState(
            isRendering: isRendering,
            hasLastSource: false,
            hasLastRender: false,
            isUpdateInstallPending: isUpdateInstallPending,
            isPresentingClipboardConfirmation: false,
            selectedWidthPreset: .standard,
            selectedTheme: .cleanLight
        )
    }
}

@MainActor
private final class UpdateStatusPresenterHarness {
    struct HUDMessage {
        let message: String
        let symbol: String
        let style: HUDStyle
    }

    var aboutIsVisible = false
    private(set) var hudMessages: [HUDMessage] = []
    private(set) var statusItems: [StatusItemPresentation] = []
    private(set) var announcements: [String] = []

    func makePresenter() -> UpdateStatusPresenter {
        UpdateStatusPresenter(
            showHUD: { [weak self] message, symbol, style in
                self?.hudMessages.append(HUDMessage(
                    message: message,
                    symbol: symbol,
                    style: style
                ))
            },
            applyStatusItem: { [weak self] presentation in
                self?.statusItems.append(presentation)
            },
            isAboutVisible: { [weak self] in
                self?.aboutIsVisible == true
            },
            announce: { [weak self] message in
                self?.announcements.append(message)
            }
        )
    }
}
