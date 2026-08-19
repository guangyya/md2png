import AppKit
import WebKit
import XCTest
@testable import MD2PNG

final class RendererRecoveryStateTests: XCTestCase {
    private let rendererIntegrationTimeout: TimeInterval = 10

    func testIdleTerminationReloadsAndRunsARequestQueuedDuringRecovery() throws {
        var state = try readyState()

        let recoveryLoad = try loadAttempt(
            from: handledActions(try terminateCurrentGeneration(in: &state))
        )
        XCTAssertEqual(state.phase, .recoveryLoad(recoveryLoad))

        let requestID = makeID(1)
        XCTAssertTrue(state.enqueue(requestID).isEmpty)
        XCTAssertEqual(state.pendingRequestIDs, [requestID])

        let execution = try startExecution(from: state.rendererDidLoad(recoveryLoad))
        XCTAssertEqual(execution.requestID, requestID)
        XCTAssertEqual(state.activeRequestID, requestID)
        XCTAssertTrue(state.pendingRequestIDs.isEmpty)
    }

    func testActiveRequestRetriesOnceAndPreservesQueueOrder() throws {
        var state = try readyState()
        let firstID = makeID(1)
        let secondID = makeID(2)
        let firstExecution = try startExecution(from: state.enqueue(firstID))
        XCTAssertTrue(state.enqueue(secondID).isEmpty)

        let recoveryLoad = try loadAttempt(
            from: handledActions(try terminateCurrentGeneration(in: &state))
        )
        XCTAssertEqual(state.activeRequestID, firstID)
        XCTAssertEqual(state.pendingRequestIDs, [secondID])

        let staleFinish = state.finish(firstExecution)
        XCTAssertNil(staleFinish.completedRequestID)
        XCTAssertTrue(staleFinish.actions.isEmpty)

        let retryExecution = try startExecution(from: state.rendererDidLoad(recoveryLoad))
        XCTAssertEqual(retryExecution.requestID, firstID)
        XCTAssertNotEqual(retryExecution.attemptID, firstExecution.attemptID)

        let firstFinish = state.finish(retryExecution)
        XCTAssertEqual(firstFinish.completedRequestID, firstID)
        let secondExecution = try startExecution(from: firstFinish.actions)
        XCTAssertEqual(secondExecution.requestID, secondID)

        let secondFinish = state.finish(secondExecution)
        XCTAssertEqual(secondFinish.completedRequestID, secondID)
        XCTAssertTrue(secondFinish.actions.isEmpty)
        XCTAssertEqual(state.phase, .ready)
    }

    func testSecondTerminationDuringRetriedRequestFailsActiveAndQueuedRequests() throws {
        var state = try readyState()
        let firstID = makeID(1)
        let secondID = makeID(2)
        _ = try startExecution(from: state.enqueue(firstID))
        XCTAssertTrue(state.enqueue(secondID).isEmpty)

        let recoveryLoad = try loadAttempt(
            from: handledActions(try terminateCurrentGeneration(in: &state))
        )
        _ = try startExecution(from: state.rendererDidLoad(recoveryLoad))

        XCTAssertEqual(
            try terminateCurrentGeneration(in: &state),
            .handled([.fail(requestIDs: [firstID, secondID], failure: .recoveryFailed)])
        )
        XCTAssertEqual(state.phase, .needsReload)
        XCTAssertNil(state.activeRequestID)
        XCTAssertTrue(state.pendingRequestIDs.isEmpty)

        let laterID = makeID(3)
        let laterLoad = try loadAttempt(from: state.enqueue(laterID))
        XCTAssertEqual(state.phase, .recoveryLoad(laterLoad))
        let laterExecution = try startExecution(from: state.rendererDidLoad(laterLoad))
        XCTAssertEqual(laterExecution.requestID, laterID)
    }

    func testTerminationDuringRecoveryLoadFailsWithoutStartingASecondReload() throws {
        var state = try readyState()
        let firstID = makeID(1)
        let secondID = makeID(2)
        _ = try startExecution(from: state.enqueue(firstID))
        XCTAssertTrue(state.enqueue(secondID).isEmpty)

        _ = try loadAttempt(
            from: handledActions(try terminateCurrentGeneration(in: &state))
        )
        XCTAssertEqual(
            try terminateCurrentGeneration(in: &state),
            .handled([.fail(requestIDs: [firstID, secondID], failure: .recoveryFailed)])
        )
        XCTAssertEqual(state.phase, .needsReload)
    }

    func testRecoveryLoadFailureReturnsStructuredFailureInQueueOrder() throws {
        var state = try readyState()
        let firstID = makeID(1)
        let secondID = makeID(2)
        _ = try startExecution(from: state.enqueue(firstID))
        XCTAssertTrue(state.enqueue(secondID).isEmpty)
        let recoveryLoad = try loadAttempt(
            from: handledActions(try terminateCurrentGeneration(in: &state))
        )

        XCTAssertEqual(
            state.rendererLoadFailed(recoveryLoad),
            [.fail(requestIDs: [firstID, secondID], failure: .recoveryFailed)]
        )
        XCTAssertEqual(state.phase, .needsReload)
    }

    func testInitialLoadFailureUsesRendererUnavailableFailure() throws {
        var state = RendererRecoveryState()
        let initialLoad = try loadAttempt(from: state.initialActions)
        let requestID = makeID(1)
        XCTAssertTrue(state.enqueue(requestID).isEmpty)

        XCTAssertEqual(
            state.rendererLoadFailed(initialLoad),
            [.fail(requestIDs: [requestID], failure: .rendererUnavailable)]
        )
        XCTAssertEqual(state.phase, .unavailable)
    }

    func testInitialLoadTimeoutFailsQueuedWorkAndLaterRequestCanRecover() throws {
        var state = RendererRecoveryState()
        let initialLoad = try loadAttempt(from: state.initialActions)
        let firstID = makeID(1)
        let secondID = makeID(2)
        XCTAssertTrue(state.enqueue(firstID).isEmpty)
        XCTAssertTrue(state.enqueue(secondID).isEmpty)

        XCTAssertEqual(
            state.timedOut(.load(initialLoad)),
            [.fail(requestIDs: [firstID, secondID], failure: .timedOut)]
        )
        XCTAssertEqual(state.phase, .needsReload)
        XCTAssertTrue(state.rendererDidLoad(initialLoad).isEmpty)

        let laterID = makeID(3)
        let laterLoad = try loadAttempt(from: state.enqueue(laterID))
        XCTAssertEqual(state.phase, .recoveryLoad(laterLoad))
        XCTAssertTrue(state.timedOut(.load(initialLoad)).isEmpty)
        let laterExecution = try startExecution(from: state.rendererDidLoad(laterLoad))
        XCTAssertEqual(laterExecution.requestID, laterID)
    }

    func testRecoveryLoadTimeoutFailsInterruptedAndQueuedWork() throws {
        var state = try readyState()
        let firstID = makeID(1)
        let secondID = makeID(2)
        _ = try startExecution(from: state.enqueue(firstID))
        XCTAssertTrue(state.enqueue(secondID).isEmpty)
        let recoveryLoad = try loadAttempt(
            from: handledActions(try terminateCurrentGeneration(in: &state))
        )

        XCTAssertEqual(
            state.timedOut(.load(recoveryLoad)),
            [.fail(requestIDs: [firstID, secondID], failure: .timedOut)]
        )
        XCTAssertEqual(state.phase, .needsReload)
        XCTAssertTrue(state.rendererDidLoad(recoveryLoad).isEmpty)
    }

    func testJavaScriptTimeoutFailsActiveAndQueuedWorkAndIgnoresLateCallbacks() throws {
        var state = try readyState()
        let firstID = makeID(1)
        let secondID = makeID(2)
        let execution = try startExecution(from: state.enqueue(firstID))
        XCTAssertEqual(state.phase, .rendering(execution, stage: .javaScript))
        XCTAssertTrue(state.enqueue(secondID).isEmpty)

        XCTAssertEqual(
            state.timedOut(.render(execution)),
            [.fail(requestIDs: [firstID, secondID], failure: .timedOut)]
        )
        XCTAssertEqual(state.phase, .needsReload)
        XCTAssertFalse(state.renderDidStartSnapshot(execution))
        XCTAssertNil(state.finish(execution).completedRequestID)
        XCTAssertTrue(state.timedOut(.render(execution)).isEmpty)
    }

    func testSnapshotTimeoutFailsOnceAndIgnoresLateSnapshotCompletion() throws {
        var state = try readyState()
        let firstID = makeID(1)
        let secondID = makeID(2)
        let execution = try startExecution(from: state.enqueue(firstID))
        XCTAssertTrue(state.renderDidStartSnapshot(execution))
        XCTAssertEqual(state.phase, .rendering(execution, stage: .snapshot))
        XCTAssertTrue(state.enqueue(secondID).isEmpty)

        XCTAssertEqual(
            state.timedOut(.render(execution)),
            [.fail(requestIDs: [firstID, secondID], failure: .timedOut)]
        )
        XCTAssertNil(state.finish(execution).completedRequestID)
        XCTAssertTrue(state.timedOut(.render(execution)).isEmpty)
    }

    func testExecutionErrorThenDelegateIsHandledAsOneTermination() throws {
        var state = try readyState()
        let requestID = makeID(1)
        let execution = try startExecution(from: state.enqueue(requestID))

        let recoveryLoad = try loadAttempt(
            from: handledActions(
                state.contentProcessTerminated(from: .executionError(execution))
            )
        )
        XCTAssertEqual(
            state.contentProcessTerminated(
                from: .delegate(
                    rendererGenerationID: execution.rendererGenerationID
                )
            ),
            .ignored
        )
        XCTAssertEqual(state.phase, .recoveryLoad(recoveryLoad))

        let retryExecution = try startExecution(from: state.rendererDidLoad(recoveryLoad))
        XCTAssertEqual(retryExecution.requestID, requestID)
        XCTAssertNotEqual(retryExecution.attemptID, execution.attemptID)
    }

    func testMissingDelegateDoesNotSwallowLaterIdleTermination() throws {
        var state = try readyState()
        let requestID = makeID(1)
        let execution = try startExecution(from: state.enqueue(requestID))
        let recoveryLoad = try loadAttempt(
            from: handledActions(
                state.contentProcessTerminated(from: .executionError(execution))
            )
        )

        let retryExecution = try startExecution(from: state.rendererDidLoad(recoveryLoad))
        XCTAssertEqual(state.finish(retryExecution).completedRequestID, requestID)
        XCTAssertEqual(
            state.currentRendererGenerationID,
            retryExecution.rendererGenerationID
        )

        let nextRecoveryLoad = try loadAttempt(
            from: handledActions(try terminateCurrentGeneration(in: &state))
        )
        XCTAssertNotEqual(nextRecoveryLoad.id, recoveryLoad.id)
        XCTAssertEqual(state.phase, .recoveryLoad(nextRecoveryLoad))
    }

    func testDelayedDelegateFromObsoleteGenerationIsIgnoredAfterRetryStarts() throws {
        var state = try readyState()
        let requestID = makeID(1)
        let firstExecution = try startExecution(from: state.enqueue(requestID))
        let obsoleteGenerationID = firstExecution.rendererGenerationID
        let recoveryLoad = try loadAttempt(
            from: handledActions(
                state.contentProcessTerminated(from: .executionError(firstExecution))
            )
        )
        let retryExecution = try startExecution(from: state.rendererDidLoad(recoveryLoad))

        XCTAssertEqual(
            state.contentProcessTerminated(
                from: .delegate(rendererGenerationID: obsoleteGenerationID)
            ),
            .ignored
        )
        XCTAssertEqual(state.phase, .rendering(retryExecution, stage: .javaScript))
        XCTAssertEqual(state.finish(retryExecution).completedRequestID, requestID)
    }

    func testSuccessfulIdleReloadRetiresThePreviousGeneration() throws {
        var state = try readyState()
        let obsoleteGenerationID = try XCTUnwrap(state.currentRendererGenerationID)
        let recoveryLoad = try loadAttempt(
            from: handledActions(try terminateCurrentGeneration(in: &state))
        )
        XCTAssertTrue(state.rendererDidLoad(recoveryLoad).isEmpty)
        XCTAssertEqual(state.phase, .ready)

        XCTAssertEqual(
            state.contentProcessTerminated(
                from: .delegate(rendererGenerationID: obsoleteGenerationID)
            ),
            .ignored
        )
        XCTAssertEqual(state.phase, .ready)

        let nextRecoveryLoad = try loadAttempt(
            from: handledActions(try terminateCurrentGeneration(in: &state))
        )
        XCTAssertNotEqual(nextRecoveryLoad.id, recoveryLoad.id)
    }

    func testLateTerminationSignalsStayObsoleteAcrossNeedsReloadAndFreshLoad() throws {
        var state = try readyState()
        let firstGenerationID = try XCTUnwrap(state.currentRendererGenerationID)
        let recoveryLoad = try loadAttempt(
            from: handledActions(try terminateCurrentGeneration(in: &state))
        )
        let recoveryGenerationID = recoveryLoad.id

        XCTAssertEqual(
            try terminateCurrentGeneration(in: &state),
            .handled([])
        )
        XCTAssertEqual(state.phase, .needsReload)
        for obsoleteGenerationID in [firstGenerationID, recoveryGenerationID] {
            XCTAssertEqual(
                state.contentProcessTerminated(
                    from: .delegate(rendererGenerationID: obsoleteGenerationID)
                ),
                .ignored
            )
        }

        let laterID = makeID(2)
        let freshLoad = try loadAttempt(from: state.enqueue(laterID))
        let freshExecution = try startExecution(from: state.rendererDidLoad(freshLoad))
        XCTAssertNotEqual(freshExecution.rendererGenerationID, recoveryGenerationID)
        XCTAssertEqual(
            state.contentProcessTerminated(
                from: .delegate(rendererGenerationID: firstGenerationID)
            ),
            .ignored
        )

        _ = try loadAttempt(
            from: handledActions(try terminateCurrentGeneration(in: &state))
        )
    }

    func testDelegateThenExecutionErrorIsHandledAsOneTermination() throws {
        var state = try readyState()
        let requestID = makeID(1)
        let execution = try startExecution(from: state.enqueue(requestID))

        let recoveryLoad = try loadAttempt(
            from: handledActions(try terminateCurrentGeneration(in: &state))
        )
        XCTAssertEqual(
            state.contentProcessTerminated(from: .executionError(execution)),
            .ignored
        )
        XCTAssertEqual(state.phase, .recoveryLoad(recoveryLoad))
    }

    func testWebKitContentProcessTerminationErrorClassification() {
        let terminationError = NSError(
            domain: WKErrorDomain,
            code: WKError.Code.webContentProcessTerminated.rawValue
        )
        let otherWebKitError = NSError(
            domain: WKErrorDomain,
            code: WKError.Code.javaScriptExceptionOccurred.rawValue
        )
        let sameCodeFromAnotherDomain = NSError(
            domain: NSCocoaErrorDomain,
            code: WKError.Code.webContentProcessTerminated.rawValue
        )

        XCTAssertTrue(MarkdownRenderer.isContentProcessTermination(terminationError))
        XCTAssertFalse(MarkdownRenderer.isContentProcessTermination(otherWebKitError))
        XCTAssertFalse(MarkdownRenderer.isContentProcessTermination(sameCodeFromAnotherDomain))
    }

    @MainActor
    func testRendererReloadsAfterSimulatedInitialProcessTermination() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        let initialGenerationID = try XCTUnwrap(renderer.rendererGenerationIDForTesting)
        let initialWebViewIdentity = renderer.webViewIdentityForTesting
        renderer.simulateContentProcessTerminationForTesting()
        XCTAssertNotEqual(renderer.rendererGenerationIDForTesting, initialGenerationID)
        XCTAssertNotEqual(renderer.webViewIdentityForTesting, initialWebViewIdentity)

        let completion = expectation(description: "renderer reload completed")
        var capturedResult: Result<NSImage, Error>?
        renderer.render("# Recovery\n\nThe renderer reloaded locally.") {
            capturedResult = $0
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: rendererIntegrationTimeout)

        let result = try XCTUnwrap(capturedResult)
        let image = try result.get()
        XCTAssertGreaterThanOrEqual(image.size.width, 520)
        XCTAssertGreaterThan(image.size.height, 80)
    }

    @MainActor
    func testInitialLoadWatchdogTimeoutFailsOnceAndNextRenderStartsRecovery() throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        let initialGenerationID = try XCTUnwrap(renderer.rendererGenerationIDForTesting)
        let initialWebViewIdentity = renderer.webViewIdentityForTesting
        var timedOutResults: [Result<NSImage, Error>] = []
        renderer.render("# Waiting during initial load") {
            timedOutResults.append($0)
        }
        renderer.simulateWatchdogTimeoutForTesting()

        XCTAssertEqual(timedOutResults.count, 1)
        let firstResult = try XCTUnwrap(timedOutResults.first)
        guard case let .failure(error) = firstResult,
              let appError = error as? AppError,
              case .rendererTimedOut = appError else {
            XCTFail("Expected rendererTimedOut, got \(firstResult)")
            return
        }

        renderer.render("# Fresh request after timeout") { _ in }

        XCTAssertNotEqual(renderer.rendererGenerationIDForTesting, initialGenerationID)
        XCTAssertNotEqual(renderer.webViewIdentityForTesting, initialWebViewIdentity)
        guard case .recoveryLoad = renderer.recoveryPhaseForTesting else {
            XCTFail("Expected a fresh renderer load, got \(renderer.recoveryPhaseForTesting)")
            return
        }
    }

    @MainActor
    func testScheduledWatchdogAutomaticallyTimesOutMatchingAttempt() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer(watchdogTimeout: 0)
        let completion = expectation(description: "scheduled watchdog fired")
        var capturedResult: Result<NSImage, Error>?

        renderer.render("# Scheduled timeout") {
            capturedResult = $0
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 1)

        let result = try XCTUnwrap(capturedResult)
        guard case let .failure(error) = result,
              let appError = error as? AppError,
              case .rendererTimedOut = appError else {
            XCTFail("Expected rendererTimedOut, got \(result)")
            return
        }
    }

    @MainActor
    func testCompletionReentrancyCannotStartAnObsoleteQueuedExecution() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        let firstCompleted = expectation(description: "first render completed")
        let queuedCompleted = expectation(description: "queued render recovered")
        var queuedResult: Result<NSImage, Error>?

        renderer.render("# First render") { result in
            if case let .failure(error) = result {
                XCTFail("First render failed: \(error)")
            }
            renderer.simulateContentProcessTerminationForTesting()
            firstCompleted.fulfill()
        }
        renderer.render("# Queued render") {
            queuedResult = $0
            queuedCompleted.fulfill()
        }

        await fulfillment(of: [firstCompleted, queuedCompleted], timeout: 10)
        let image = try XCTUnwrap(queuedResult).get()
        XCTAssertGreaterThanOrEqual(image.size.width, 520)
        XCTAssertGreaterThan(image.size.height, 80)
    }

    @MainActor
    func testRepeatedSimulatedTerminationFailsInterruptedRequestAndReloadsForNextRequest() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()

        let ready = expectation(description: "initial renderer load completed")
        renderer.render("# Ready") { result in
            if case let .failure(error) = result {
                XCTFail("Initial render failed: \(error)")
            }
            ready.fulfill()
        }
        await fulfillment(of: [ready], timeout: rendererIntegrationTimeout)

        let interrupted = expectation(description: "interrupted render failed")
        var interruptedResult: Result<NSImage, Error>?
        renderer.render("# Interrupted request") {
            interruptedResult = $0
            interrupted.fulfill()
        }
        renderer.simulateContentProcessTerminationForTesting()
        renderer.simulateContentProcessTerminationForTesting()
        await fulfillment(of: [interrupted], timeout: rendererIntegrationTimeout)

        let interruptedOutcome = try XCTUnwrap(interruptedResult)
        guard case let .failure(error) = interruptedOutcome,
              let appError = error as? AppError else {
            XCTFail("Expected rendererRecoveryFailed, got \(interruptedOutcome)")
            return
        }
        guard case .rendererRecoveryFailed = appError else {
            XCTFail("Expected rendererRecoveryFailed, got \(appError)")
            return
        }

        let completion = expectation(description: "fresh renderer load completed")
        var capturedResult: Result<NSImage, Error>?
        renderer.render("# Fresh request after recovery failure") {
            capturedResult = $0
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: rendererIntegrationTimeout)

        let result = try XCTUnwrap(capturedResult)
        let image = try result.get()
        XCTAssertGreaterThanOrEqual(image.size.width, 520)
        XCTAssertGreaterThan(image.size.height, 80)
    }

    func testRecoveryAndTimeoutMessagesInviteAnotherRender() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))

        for key in ["error.renderer_recovery_failed", "error.renderer_timed_out"] {
            let fallback = "missing \(key) localization"
            XCTAssertNotEqual(
                L10n.text(key, defaultValue: fallback, bundle: english),
                fallback
            )
            XCTAssertNotEqual(
                L10n.text(key, defaultValue: fallback, bundle: chinese),
                fallback
            )
        }
    }

    private func readyState() throws -> RendererRecoveryState {
        var state = RendererRecoveryState()
        let initialLoad = try loadAttempt(from: state.initialActions)
        XCTAssertTrue(state.rendererDidLoad(initialLoad).isEmpty)
        return state
    }

    private func handledActions(
        _ transition: RendererRecoveryState.TerminationTransition
    ) throws -> [RendererRecoveryState.Action] {
        guard case let .handled(actions) = transition else {
            throw TestError.expectedHandledTransition
        }
        return actions
    }

    private func terminateCurrentGeneration(
        in state: inout RendererRecoveryState
    ) throws -> RendererRecoveryState.TerminationTransition {
        let generationID = try XCTUnwrap(state.currentRendererGenerationID)
        return state.contentProcessTerminated(
            from: .delegate(rendererGenerationID: generationID)
        )
    }

    private func loadAttempt(
        from actions: [RendererRecoveryState.Action]
    ) throws -> RendererRecoveryState.LoadAttempt {
        XCTAssertEqual(actions.count, 1)
        guard case let .loadRenderer(attempt) = try XCTUnwrap(actions.first) else {
            throw TestError.expectedLoadAction
        }
        return attempt
    }

    private func startExecution(
        from actions: [RendererRecoveryState.Action]
    ) throws -> RendererRecoveryState.Execution {
        XCTAssertEqual(actions.count, 1)
        guard case let .start(execution) = try XCTUnwrap(actions.first) else {
            throw TestError.expectedStartAction
        }
        return execution
    }

    private func makeID(_ value: UInt8) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0,
            0, 0,
            0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        ))
    }

    private enum TestError: Error {
        case expectedHandledTransition
        case expectedLoadAction
        case expectedStartAction
    }
}
