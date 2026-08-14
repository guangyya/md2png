import AppKit
import XCTest
@testable import MD2PNG

final class RendererRecoveryStateTests: XCTestCase {
    func testIdleTerminationReloadsAndRunsARequestQueuedDuringRecovery() throws {
        var state = RendererRecoveryState()
        XCTAssertTrue(state.rendererDidLoad().isEmpty)
        XCTAssertEqual(state.phase, .ready)

        XCTAssertEqual(state.contentProcessTerminated(), [.loadRenderer])
        XCTAssertEqual(state.phase, .recoveryLoad)

        let requestID = makeID(1)
        XCTAssertTrue(state.enqueue(requestID).isEmpty)
        XCTAssertEqual(state.pendingRequestIDs, [requestID])

        let execution = try startExecution(from: state.rendererDidLoad())
        XCTAssertEqual(execution.requestID, requestID)
        XCTAssertEqual(state.activeRequestID, requestID)
        XCTAssertTrue(state.pendingRequestIDs.isEmpty)
    }

    func testActiveRequestRetriesOnceAndPreservesQueueOrder() throws {
        var state = readyState()
        let firstID = makeID(1)
        let secondID = makeID(2)
        let firstExecution = try startExecution(from: state.enqueue(firstID))
        XCTAssertTrue(state.enqueue(secondID).isEmpty)

        XCTAssertEqual(state.contentProcessTerminated(), [.loadRenderer])
        XCTAssertEqual(state.activeRequestID, firstID)
        XCTAssertEqual(state.pendingRequestIDs, [secondID])

        let staleFinish = state.finish(firstExecution)
        XCTAssertNil(staleFinish.completedRequestID)
        XCTAssertTrue(staleFinish.actions.isEmpty)

        let retryExecution = try startExecution(from: state.rendererDidLoad())
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
        var state = readyState()
        let firstID = makeID(1)
        let secondID = makeID(2)
        _ = try startExecution(from: state.enqueue(firstID))
        XCTAssertTrue(state.enqueue(secondID).isEmpty)

        XCTAssertEqual(state.contentProcessTerminated(), [.loadRenderer])
        _ = try startExecution(from: state.rendererDidLoad())

        XCTAssertEqual(
            state.contentProcessTerminated(),
            [.fail(requestIDs: [firstID, secondID], failure: .recoveryFailed)]
        )
        XCTAssertEqual(state.phase, .needsReload)
        XCTAssertNil(state.activeRequestID)
        XCTAssertTrue(state.pendingRequestIDs.isEmpty)

        let laterID = makeID(3)
        XCTAssertEqual(state.enqueue(laterID), [.loadRenderer])
        XCTAssertEqual(state.phase, .recoveryLoad)
        let laterExecution = try startExecution(from: state.rendererDidLoad())
        XCTAssertEqual(laterExecution.requestID, laterID)
    }

    func testTerminationDuringRecoveryLoadFailsWithoutStartingASecondReload() throws {
        var state = readyState()
        let firstID = makeID(1)
        let secondID = makeID(2)
        _ = try startExecution(from: state.enqueue(firstID))
        XCTAssertTrue(state.enqueue(secondID).isEmpty)

        XCTAssertEqual(state.contentProcessTerminated(), [.loadRenderer])
        XCTAssertEqual(
            state.contentProcessTerminated(),
            [.fail(requestIDs: [firstID, secondID], failure: .recoveryFailed)]
        )
        XCTAssertEqual(state.phase, .needsReload)
    }

    func testRecoveryLoadFailureReturnsStructuredFailureInQueueOrder() throws {
        var state = readyState()
        let firstID = makeID(1)
        let secondID = makeID(2)
        _ = try startExecution(from: state.enqueue(firstID))
        XCTAssertTrue(state.enqueue(secondID).isEmpty)
        XCTAssertEqual(state.contentProcessTerminated(), [.loadRenderer])

        XCTAssertEqual(
            state.rendererLoadFailed(),
            [.fail(requestIDs: [firstID, secondID], failure: .recoveryFailed)]
        )
        XCTAssertEqual(state.phase, .needsReload)
    }

    func testInitialLoadFailureUsesRendererUnavailableFailure() {
        var state = RendererRecoveryState()
        let requestID = makeID(1)
        XCTAssertTrue(state.enqueue(requestID).isEmpty)

        XCTAssertEqual(
            state.rendererLoadFailed(),
            [.fail(requestIDs: [requestID], failure: .rendererUnavailable)]
        )
        XCTAssertEqual(state.phase, .unavailable(.rendererUnavailable))
    }

    @MainActor
    func testRendererReloadsAfterSimulatedInitialProcessTermination() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        renderer.simulateContentProcessTerminationForTesting()

        let completion = expectation(description: "renderer reload completed")
        var capturedResult: Result<NSImage, Error>?
        renderer.render("# Recovery\n\nThe renderer reloaded locally.") {
            capturedResult = $0
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 5)

        let result = try XCTUnwrap(capturedResult)
        let image = try result.get()
        XCTAssertGreaterThanOrEqual(image.size.width, 520)
        XCTAssertGreaterThan(image.size.height, 80)
    }

    @MainActor
    func testNextRequestReloadsAfterRepeatedSimulatedTermination() async throws {
        _ = NSApplication.shared
        let renderer = MarkdownRenderer()
        renderer.simulateContentProcessTerminationForTesting()
        renderer.simulateContentProcessTerminationForTesting()

        let completion = expectation(description: "fresh renderer load completed")
        var capturedResult: Result<NSImage, Error>?
        renderer.render("# Fresh request after recovery failure") {
            capturedResult = $0
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 5)

        let result = try XCTUnwrap(capturedResult)
        let image = try result.get()
        XCTAssertGreaterThanOrEqual(image.size.width, 520)
        XCTAssertGreaterThan(image.size.height, 80)
    }

    func testRecoveryFailureMessagesInviteAnotherRender() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))

        XCTAssertEqual(
            L10n.text(
                "error.renderer_recovery_failed",
                defaultValue: "fallback",
                bundle: english
            ),
            "The local renderer stopped and could not recover. Try rendering again."
        )
        XCTAssertEqual(
            L10n.text(
                "error.renderer_recovery_failed",
                defaultValue: "fallback",
                bundle: chinese
            ),
            "本地渲染器已停止且无法恢复。请重新渲染。"
        )
    }

    private func readyState() -> RendererRecoveryState {
        var state = RendererRecoveryState()
        XCTAssertTrue(state.rendererDidLoad().isEmpty)
        return state
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
        case expectedStartAction
    }
}
