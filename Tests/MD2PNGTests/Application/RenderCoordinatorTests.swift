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

    func testMarkdownFileUsesTheExistingRenderClipboardAndHistoryFlow() throws {
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = "# Clipboard stays unread"
        let coordinator = harness.makeCoordinator()

        coordinator.renderMarkdownFile("# File source\n")

        XCTAssertEqual(harness.clipboardReadCount, 0)
        XCTAssertEqual(harness.renderRequests.map(\.markdown), ["# File source\n"])
        XCTAssertTrue(harness.writtenImages.isEmpty)
        XCTAssertTrue(harness.writtenMarkdown.isEmpty)

        let image = NSImage(size: NSSize(width: 640, height: 480))
        harness.completeNextRender(with: .success(image))

        XCTAssertEqual(harness.writtenImages.count, 1)
        XCTAssertTrue(harness.writtenMarkdown.isEmpty)
        XCTAssertEqual(harness.notices, [.imageCopied])
        coordinator.showLastRender()
        let preview = try XCTUnwrap(harness.previews.last)
        XCTAssertTrue(preview.image === image)
        XCTAssertEqual(preview.markdown, "# File source\n")
    }

    func testFinderOpenedMarkdownFileShowsPreviewAfterSuccessfulRender() throws {
        let harness = RenderCoordinatorHarness()
        let coordinator = harness.makeCoordinator()

        coordinator.renderMarkdownFile(
            "# Finder source\n",
            showsPreviewOnSuccess: true
        )
        XCTAssertTrue(harness.previews.isEmpty)

        let image = NSImage(size: NSSize(width: 640, height: 480))
        harness.completeNextRender(with: .success(image))

        XCTAssertEqual(harness.previews.count, 1)
        let preview = try XCTUnwrap(harness.previews.first)
        XCTAssertTrue(preview.image === image)
        XCTAssertEqual(preview.markdown, "# Finder source\n")
        XCTAssertEqual(harness.writtenImages.count, 1)
    }

    func testMarkdownFileRenderFailureLeavesClipboardAndHistoryUntouched() {
        let harness = RenderCoordinatorHarness()
        let initialChangeCount = harness.clipboardChangeCount
        let coordinator = harness.makeCoordinator()

        coordinator.renderMarkdownFile("# Invalid file source")
        harness.completeNextRender(with: .failure(TestFailure.renderer))

        XCTAssertEqual(harness.clipboardReadCount, 0)
        XCTAssertEqual(harness.clipboardChangeCount, initialChangeCount)
        XCTAssertTrue(harness.writtenImages.isEmpty)
        XCTAssertTrue(harness.writtenMarkdown.isEmpty)
        XCTAssertFalse(coordinator.state.hasLastRender)
        XCTAssertFalse(coordinator.state.hasLastSource)
    }

    func testRoundedRenderWritesAndPreviewsTheStyledImage() throws {
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = "# Rounded"
        harness.renderCornerStyle = .rounded
        let coordinator = harness.makeCoordinator()
        let image = NSImage(
            size: NSSize(width: 64, height: 48),
            flipped: false
        ) { bounds in
            NSColor.systemRed.setFill()
            bounds.fill()
            return true
        }

        coordinator.renderClipboard()
        harness.completeNextRender(with: .success(image))
        coordinator.showLastRender()

        let written = try XCTUnwrap(harness.writtenImages.first)
        let preview = try XCTUnwrap(harness.previews.first?.image)
        XCTAssertTrue(written === preview)
        XCTAssertFalse(written === image)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            data: RenderedImageExport.pngData(for: written)
        ))
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.05)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 32, y: 24)).alphaComponent, 0.95)
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
        let report = try XCTUnwrap(harness.errors.first as? RendererErrorReport)
        XCTAssertEqual(report.failure.kind, .unknown)
        XCTAssertEqual(report.operationID.rawValue.count, 12)
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

    func testSizeLimitErrorCanStartSplitRecoveryFromErrorCallback() {
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = "# Tall source"
        harness.splitExportDestinationURL = URL(fileURLWithPath: "/tmp/export")
        let coordinator = harness.makeCoordinator()

        harness.startSplitRecovery(using: coordinator) {
            harness.clipboardMarkdown = "# New clipboard content"
        }

        XCTAssertEqual(harness.splitRenderRequests.count, 1)
        XCTAssertEqual(harness.splitRenderRequests.first?.markdown, "# Tall source")
        XCTAssertTrue(harness.chosenSplitExportDestinations.isEmpty)
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
        coordinator.renderMarkdownFile("# File source")
        coordinator.saveFailedRenderAsSplitPNGs()

        XCTAssertTrue(coordinator.state.isUpdateInstallPending)
        XCTAssertEqual(coordinator.state.selectedWidthPreset, .wide)
        XCTAssertEqual(coordinator.state.selectedTheme, .dark)
        XCTAssertTrue(harness.renderRequests.isEmpty)
        XCTAssertTrue(harness.splitRenderRequests.isEmpty)
        XCTAssertTrue(harness.chosenSplitExportDestinations.isEmpty)
    }

    func testSplitExportUsesCurrentPresentationWithoutChangingClipboardOrHistory() async throws {
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = "# Tall release notes"
        harness.splitExportDestinationURL = URL(
            fileURLWithPath: "/tmp/Tall-release-notes-split",
            isDirectory: true
        )
        let coordinator = harness.makeCoordinator()
        coordinator.selectWidthPreset(.wide)
        coordinator.selectTheme(.dark)

        harness.startSplitRecovery(using: coordinator)

        XCTAssertTrue(coordinator.state.isRendering)
        XCTAssertTrue(harness.chosenSplitExportDestinations.isEmpty)
        let request = try XCTUnwrap(harness.splitRenderRequests.first)
        XCTAssertEqual(request.markdown, "# Tall release notes")
        XCTAssertEqual(request.widthPreset, .wide)
        XCTAssertEqual(request.theme, .dark)
        XCTAssertTrue(harness.renderRequests.isEmpty)

        let result = try makeSplitResult()
        harness.completeNextSplitRender(with: .success(result))
        XCTAssertEqual(harness.chosenSplitExportDestinations, [
            .init(suggestedName: "Tall release notes-split", fileCount: 2)
        ])
        await waitForRenderActionToFinish(coordinator)

        XCTAssertEqual(harness.splitExportWrites.count, 1)
        XCTAssertEqual(
            harness.splitExportWrites.first?.1,
            harness.splitExportDestinationURL
        )
        XCTAssertEqual(harness.notices, [.splitImagesSaved(
            count: 2,
            directoryURL: try XCTUnwrap(harness.splitExportDestinationURL)
        )])
        XCTAssertTrue(harness.writtenImages.isEmpty)
        XCTAssertTrue(harness.writtenMarkdown.isEmpty)
        XCTAssertFalse(coordinator.state.hasLastRender)
        XCTAssertFalse(coordinator.state.hasLastSource)
    }

    func testCancellingSplitExportAfterCountIsKnownDoesNotWriteOrChangeClipboard() throws {
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = "# Keep me"
        let coordinator = harness.makeCoordinator()

        harness.startSplitRecovery(using: coordinator)
        XCTAssertTrue(coordinator.state.isRendering)
        XCTAssertEqual(harness.splitRenderRequests.count, 1)

        harness.completeNextSplitRender(with: .success(try makeSplitResult()))

        XCTAssertFalse(coordinator.state.isRendering)
        XCTAssertEqual(harness.chosenSplitExportDestinations, [
            .init(suggestedName: "Keep me-split", fileCount: 2)
        ])
        XCTAssertTrue(harness.splitRenderRequests.isEmpty)
        XCTAssertTrue(harness.writtenImages.isEmpty)
        XCTAssertTrue(harness.writtenMarkdown.isEmpty)
        XCTAssertTrue(harness.notices.isEmpty)
        XCTAssertEqual(harness.errors.count, 1)
    }

    func testSplitRenderFailureUsesSafeRendererDetailsAndWritesNothing() throws {
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = "# Too tall"
        harness.splitExportDestinationURL = URL(
            fileURLWithPath: "/tmp/Too-tall-split",
            isDirectory: true
        )
        let coordinator = harness.makeCoordinator()

        harness.startSplitRecovery(using: coordinator)
        harness.completeNextSplitRender(with: .failure(AppError.rendererTimedOut))

        XCTAssertFalse(coordinator.state.isRendering)
        let report = try XCTUnwrap(harness.errors.last as? RendererErrorReport)
        XCTAssertEqual(report.failure.kind, .timeout)
        XCTAssertTrue(harness.splitExportWrites.isEmpty)
        XCTAssertTrue(harness.writtenImages.isEmpty)
        XCTAssertTrue(harness.writtenMarkdown.isEmpty)
    }

    func testSplitSizeLimitDoesNotSuggestStartingTheSameExportAgain() throws {
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = "# Extremely tall"
        harness.splitExportDestinationURL = URL(
            fileURLWithPath: "/tmp/Extremely-tall-split",
            isDirectory: true
        )
        let coordinator = harness.makeCoordinator()

        harness.startSplitRecovery(using: coordinator)
        harness.completeNextSplitRender(with: .failure(AppError.contentTooLarge(
            width: 1_120,
            height: 80_000
        )))

        let error = try XCTUnwrap(harness.errors.last as? AppError)
        guard case let .splitExportContentTooLarge(width, height) = error else {
            return XCTFail("Expected splitExportContentTooLarge")
        }
        XCTAssertEqual(width, 1_120)
        XCTAssertEqual(height, 80_000)
        XCTAssertFalse(error.localizedDescription.contains("Save Clipboard as Split PNGs"))
        XCTAssertFalse(coordinator.state.isRendering)
        XCTAssertTrue(harness.splitExportWrites.isEmpty)
    }

    func testSplitExportWriteFailureRestoresIdleState() async throws {
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = "# Cannot save"
        harness.splitExportDestinationURL = URL(
            fileURLWithPath: "/tmp/Cannot-save-split",
            isDirectory: true
        )
        harness.splitExportWriteError = AppError.splitExportWriteFailed
        let coordinator = harness.makeCoordinator()

        harness.startSplitRecovery(using: coordinator)
        harness.completeNextSplitRender(with: .success(try makeSplitResult()))
        await waitForRenderActionToFinish(coordinator)

        XCTAssertEqual(harness.errors.count, 2)
        guard case .splitExportWriteFailed = harness.errors.last as? AppError else {
            return XCTFail("Expected splitExportWriteFailed")
        }
        XCTAssertTrue(harness.notices.isEmpty)
        XCTAssertTrue(harness.splitExportWrites.isEmpty)
    }

    func testSplitExportDiagnosticsNeverPersistMarkdownOrDestinationPath() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "md2png-split-export-diagnostics-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let now = Date(timeIntervalSince1970: 1_787_000_000)
        let logger = DiagnosticLogger(configuration: DiagnosticLoggerConfiguration(
            directoryURL: directoryURL,
            retentionPolicy: .standard,
            includesVerboseEvents: true,
            isEnabled: true,
            now: { now },
            applicationInfo: DiagnosticApplicationInfo(
                name: "md2png",
                version: "0.10.0",
                build: "10",
                sourceCommit: nil,
                configuration: "debug"
            ),
            systemInfo: DiagnosticSystemInfo(
                macOSVersion: "26.0.0",
                architecture: "arm64"
            )
        ))
        let markdownCanary = "# PRIVATE SPLIT MARKDOWN"
        let pathCanary = "/Users/private/Secret-export-split"
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = markdownCanary
        harness.splitExportDestinationURL = URL(
            fileURLWithPath: pathCanary,
            isDirectory: true
        )
        let coordinator = harness.makeCoordinator(diagnosticLogger: logger)

        harness.startSplitRecovery(using: coordinator)
        harness.completeNextSplitRender(with: .success(try makeSplitResult()))
        await waitForRenderActionToFinish(coordinator)
        await logger.flush()

        let export = try await logger.export(window: .lastHour, now: now)
        let encoded = try export.encodedString()
        XCTAssertTrue(export.events.contains {
            $0.stage == .renderCompletion
                && $0.result == .succeeded
                && $0.itemCount == 2
        })
        XCTAssertFalse(encoded.contains(markdownCanary))
        XCTAssertFalse(encoded.contains(pathCanary))
        XCTAssertFalse(encoded.contains("/Users/private"))
    }

    func testDiagnosticsCorrelateRenderStagesWithoutPersistingMarkdownOrErrors() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "md2png-render-diagnostics-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let now = Date(timeIntervalSince1970: 1_787_000_000)
        let logger = DiagnosticLogger(configuration: DiagnosticLoggerConfiguration(
            directoryURL: directoryURL,
            retentionPolicy: .standard,
            includesVerboseEvents: true,
            isEnabled: true,
            now: { now },
            applicationInfo: DiagnosticApplicationInfo(
                name: "md2png",
                version: "0.9.0",
                build: "9",
                sourceCommit: nil,
                configuration: "debug"
            ),
            systemInfo: DiagnosticSystemInfo(
                macOSVersion: "26.0.0",
                architecture: "arm64"
            )
        ))
        let canary = "# PRIVATE MARKDOWN /Users/private/secret.md"
        let harness = RenderCoordinatorHarness()
        harness.clipboardMarkdown = canary
        let coordinator = harness.makeCoordinator(diagnosticLogger: logger)

        coordinator.renderClipboard()
        let operationID = try XCTUnwrap(harness.renderRequests.first?.operationID)
        harness.completeNextRender(with: .failure(NSError(
            domain: "PrivateErrorDomain",
            code: 91,
            userInfo: [NSLocalizedDescriptionKey: canary]
        )))
        await logger.flush()

        let export = try await logger.export(window: .lastHour, now: now)
        let encoded = try export.encodedString()
        XCTAssertGreaterThanOrEqual(
            export.events.filter { $0.operationID == operationID }.count,
            2
        )
        XCTAssertFalse(encoded.contains(canary))
        XCTAssertFalse(encoded.contains("/Users/private"))
        XCTAssertFalse(encoded.contains("PrivateErrorDomain"))
    }

    private func makeSplitResult() throws -> SplitRenderResult {
        let geometry = try XCTUnwrap(RenderSplitGeometry(
            contentHeight: 200,
            preferredBreakOffsets: [100],
            protectedRanges: []
        ))
        return SplitRenderResult(
            contentSize: NSSize(width: 100, height: 200),
            geometry: geometry,
            parts: [
                SplitRenderResult.Part(
                    image: NSImage(size: NSSize(width: 100, height: 100)),
                    slice: RenderSnapshotSlice(
                        range: 0 ..< 100,
                        ending: .preferredBoundary
                    )
                ),
                SplitRenderResult.Part(
                    image: NSImage(size: NSSize(width: 100, height: 100)),
                    slice: RenderSnapshotSlice(
                        range: 100 ..< 200,
                        ending: .contentEnd
                    )
                )
            ]
        )
    }

    private func waitForRenderActionToFinish(
        _ coordinator: RenderCoordinator
    ) async {
        for _ in 0 ..< 100 where coordinator.state.isRendering {
            await Task.yield()
        }
        XCTAssertFalse(coordinator.state.isRendering)
    }
}

@MainActor
private final class RenderCoordinatorHarness {
    struct SplitDestinationRequest: Equatable {
        let suggestedName: String
        let fileCount: Int
    }

    struct RenderRequest {
        let markdown: String
        let widthPreset: RenderWidthPreset
        let theme: RenderTheme
        let operationID: DiagnosticOperationID
        let completion: RenderCoordinator.RenderCompletion
    }

    struct SplitRenderRequest {
        let markdown: String
        let widthPreset: RenderWidthPreset
        let theme: RenderTheme
        let operationID: DiagnosticOperationID
        let completion: RenderCoordinator.SplitRenderCompletion
    }

    var clipboardMarkdown = ""
    var clipboardChangeCount = 10
    private(set) var clipboardReadCount = 0
    var confirmationResult = true
    var splitExportDestinationURL: URL?
    var splitExportWriteError: Error?
    var renderCornerStyle: RenderCornerStyle = .square
    private(set) var renderRequests: [RenderRequest] = []
    private(set) var splitRenderRequests: [SplitRenderRequest] = []
    private(set) var chosenSplitExportDestinations: [SplitDestinationRequest] = []
    private(set) var writtenImages: [NSImage] = []
    private(set) var writtenMarkdown: [String] = []
    private(set) var selectedWidthPresets: [RenderWidthPreset] = []
    private(set) var selectedThemes: [RenderTheme] = []
    private(set) var confirmedActions: [ClipboardOverwriteAction] = []
    private(set) var notices: [RenderCoordinatorNotice] = []
    private(set) var errors: [Error] = []
    var onErrorHook: ((Error) -> Void)?
    private(set) var previews: [LastRender] = []
    private(set) var states: [RenderCoordinatorState] = []
    private(set) var splitExportWrites: [(SplitRenderResult, URL)] = []

    func makeCoordinator(
        diagnosticLogger: DiagnosticLogger = .disabled
    ) -> RenderCoordinator {
        RenderCoordinator(
            dependencies: RenderCoordinator.Dependencies(
                render: { [weak self] markdown, widthPreset, theme, operationID, completion in
                    self?.renderRequests.append(RenderRequest(
                        markdown: markdown,
                        widthPreset: widthPreset,
                        theme: theme,
                        operationID: operationID,
                        completion: completion
                    ))
                },
                renderSplit: { [weak self] markdown, widthPreset, theme, operationID, completion in
                    self?.splitRenderRequests.append(SplitRenderRequest(
                        markdown: markdown,
                        widthPreset: widthPreset,
                        theme: theme,
                        operationID: operationID,
                        completion: completion
                    ))
                },
                readClipboardMarkdown: { [weak self] in
                    self?.clipboardReadCount += 1
                    return self?.clipboardMarkdown ?? ""
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
                },
                chooseSplitExportDestination: { [weak self] suggestedName, fileCount in
                    self?.chosenSplitExportDestinations.append(.init(
                        suggestedName: suggestedName,
                        fileCount: fileCount
                    ))
                    return self?.splitExportDestinationURL
                },
                writeSplitExport: { [weak self] result, destinationURL in
                    if let error = self?.splitExportWriteError { throw error }
                    self?.splitExportWrites.append((result, destinationURL))
                }
            ),
            renderCornerStyle: { [weak self] in
                self?.renderCornerStyle ?? .square
            },
            diagnosticLogger: diagnosticLogger,
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
                self?.onErrorHook?(error)
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

    func startSplitRecovery(
        using coordinator: RenderCoordinator,
        beforeRecovery: @escaping () -> Void = {}
    ) {
        onErrorHook = { error in
            guard let report = error as? RendererErrorReport,
                  report.failure.supportsSplitExportRecovery else { return }
            beforeRecovery()
            coordinator.saveFailedRenderAsSplitPNGs()
        }
        coordinator.renderClipboard()
        completeNextRender(with: .failure(AppError.contentTooLarge(
            width: 1_120,
            height: 20_000
        )))
        onErrorHook = nil
    }

    func completeNextSplitRender(with result: Result<SplitRenderResult, Error>) {
        let request = splitRenderRequests.removeFirst()
        request.completion(result)
    }
}

private enum TestFailure: Error {
    case renderer
    case missingHarness
}
