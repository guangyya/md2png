import AppKit
import XCTest
@testable import MD2PNG

@MainActor
final class RenderCoordinatorTests: XCTestCase {
    func testSuccessfulRenderTracksSourceAndPublishesPreview() throws {
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = "# First"
        let coordinator = harness.makeCoordinator()

        coordinator.renderClipboard()

        XCTAssertTrue(coordinator.state.isRendering)
        XCTAssertEqual(harness.renderRequests.count, 1)
        XCTAssertEqual(harness.renderRequests[0].markdown, "# First")
        XCTAssertEqual(harness.renderRequests[0].widthPreset, .standard)
        XCTAssertEqual(harness.renderRequests[0].theme, .cleanLight)

        let image = NSImage(size: NSSize(width: 640, height: 480))
        harness.completeNextRender(with: .success(image))

        XCTAssertFalse(coordinator.state.isRendering)
        XCTAssertTrue(coordinator.state.hasLastRender)
        XCTAssertTrue(coordinator.state.hasLastSource)
        XCTAssertEqual(harness.notices, [.imageCopied])
        XCTAssertEqual(harness.writtenImages.count, 1)

        coordinator.showLastRender()
        let preview = try XCTUnwrap(harness.previews.last)
        XCTAssertTrue(preview.image === image)
        XCTAssertEqual(preview.widthPreset, .standard)
        XCTAssertEqual(preview.markdown, "# First")
    }

    func testRenderFailurePreservesClipboardAndLastSuccessfulSource() throws {
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = "Successful source"
        let coordinator = harness.makeCoordinator()
        let successfulImage = NSImage(size: NSSize(width: 640, height: 480))
        coordinator.renderClipboard()
        harness.completeNextRender(with: .success(successfulImage))

        harness.clipboardMarkdown = "Invalid source"
        coordinator.renderClipboard()
        harness.completeNextRender(with: .failure(TestFailure.renderer))

        XCTAssertEqual(harness.writtenImages.count, 1)
        XCTAssertTrue(harness.writtenMarkdown.isEmpty)
        XCTAssertEqual(harness.errors.count, 1)
        XCTAssertTrue(coordinator.state.hasLastSource)

        coordinator.showLastRender()
        let preview = try XCTUnwrap(harness.previews.last)
        XCTAssertTrue(preview.image === successfulImage)
        XCTAssertEqual(preview.markdown, "Successful source")
    }

    func testRenderRejectsReentryUntilCompletion() {
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = "# Source"
        let coordinator = harness.makeCoordinator()

        coordinator.renderClipboard()
        coordinator.renderClipboard()

        XCTAssertEqual(harness.renderRequests.count, 1)
        XCTAssertTrue(coordinator.state.isRendering)

        harness.completeNextRender(with: .failure(TestFailure.renderer))
        coordinator.renderClipboard()

        XCTAssertEqual(harness.renderRequests.count, 1)
        XCTAssertTrue(coordinator.state.isRendering)
    }

    func testExternalClipboardChangeRequiresConfirmationBeforeRestore() {
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = "Private source"
        let coordinator = harness.makeCoordinator()
        coordinator.renderClipboard()
        harness.completeNextRender(with: .success(NSImage(size: NSSize(width: 10, height: 10))))

        harness.clipboardChangeCount += 1
        harness.confirmationResult = false
        coordinator.restoreLastMarkdown()

        XCTAssertEqual(harness.confirmedActions, [.restoreLastMarkdown])
        XCTAssertTrue(harness.writtenMarkdown.isEmpty)

        harness.confirmationResult = true
        coordinator.restoreLastMarkdown()

        XCTAssertEqual(harness.confirmedActions, [
            .restoreLastMarkdown,
            .restoreLastMarkdown
        ])
        XCTAssertEqual(harness.writtenMarkdown, ["Private source"])
        XCTAssertEqual(harness.notices, [.imageCopied, .markdownRestored])

        coordinator.restoreLastMarkdown()
        XCTAssertEqual(harness.confirmedActions.count, 2)
        XCTAssertEqual(harness.writtenMarkdown, ["Private source", "Private source"])
    }

    func testPreferencesAndInstallPendingStateBlockRenderingChanges() {
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = "# Source"
        let coordinator = harness.makeCoordinator()

        coordinator.selectWidthPreset(.wide)
        coordinator.selectTheme(.dark)
        XCTAssertEqual(coordinator.state.selectedWidthPreset, .wide)
        XCTAssertEqual(coordinator.state.selectedTheme, .dark)
        XCTAssertEqual(harness.selectedWidthPresets, [.wide])
        XCTAssertEqual(harness.selectedThemes, [.dark])

        coordinator.setUpdateInstallPending(true)
        coordinator.selectWidthPreset(.compact)
        coordinator.selectTheme(.warmPaper)
        coordinator.renderClipboard()

        XCTAssertTrue(coordinator.state.isUpdateInstallPending)
        XCTAssertEqual(coordinator.state.selectedWidthPreset, .wide)
        XCTAssertEqual(coordinator.state.selectedTheme, .dark)
        XCTAssertTrue(harness.renderRequests.isEmpty)
    }
}

@MainActor
private final class RenderCoordinatorHarness {
    struct RenderRequest {
        let markdown: String
        let widthPreset: RenderWidthPreset
        let theme: RenderTheme
        let completion: RenderCoordinator.RenderCompletion
    }

    var clipboardMarkdown = ""
    var clipboardChangeCount = 10
    var confirmationResult = true
    private(set) var renderRequests: [RenderRequest] = []
    private(set) var writtenImages: [NSImage] = []
    private(set) var writtenMarkdown: [String] = []
    private(set) var selectedWidthPresets: [RenderWidthPreset] = []
    private(set) var selectedThemes: [RenderTheme] = []
    private(set) var confirmedActions: [ClipboardOverwriteAction] = []
    private(set) var notices: [RenderCoordinatorNotice] = []
    private(set) var errors: [Error] = []
    private(set) var previews: [LastRender] = []
    private(set) var states: [RenderCoordinatorState] = []

    func makeCoordinator() -> RenderCoordinator {
        RenderCoordinator(
            dependencies: RenderCoordinator.Dependencies(
                render: { [weak self] markdown, widthPreset, theme, completion in
                    self?.renderRequests.append(RenderRequest(
                        markdown: markdown,
                        widthPreset: widthPreset,
                        theme: theme,
                        completion: completion
                    ))
                },
                readClipboardMarkdown: { [weak self] in
                    self?.clipboardMarkdown ?? ""
                },
                clipboardChangeCount: { [weak self] in
                    self?.clipboardChangeCount ?? 0
                },
                writeImage: { [weak self] image in
                    guard let self else { throw TestFailure.missingHarness }
                    self.writtenImages.append(image)
                    self.clipboardChangeCount += 1
                    return self.clipboardChangeCount
                },
                writeMarkdown: { [weak self] markdown in
                    guard let self else { throw TestFailure.missingHarness }
                    self.writtenMarkdown.append(markdown)
                    self.clipboardChangeCount += 1
                    return self.clipboardChangeCount
                },
                loadExample: { kind in kind.menuTitle },
                selectWidthPreset: { [weak self] preset in
                    self?.selectedWidthPresets.append(preset)
                },
                selectTheme: { [weak self] theme in
                    self?.selectedThemes.append(theme)
                }
            ),
            confirmClipboardOverwrite: { [weak self] action in
                guard let self else { return false }
                self.confirmedActions.append(action)
                return self.confirmationResult
            },
            onStateChange: { [weak self] state in
                self?.states.append(state)
            },
            onNotice: { [weak self] notice in
                self?.notices.append(notice)
            },
            onError: { [weak self] error in
                self?.errors.append(error)
            },
            onPreviewRequested: { [weak self] lastRender in
                self?.previews.append(lastRender)
            }
        )
    }

    func completeNextRender(with result: Result<NSImage, Error>) {
        let request = renderRequests.removeFirst()
        request.completion(result)
    }
}

private enum TestFailure: Error {
    case renderer
    case missingHarness
}
