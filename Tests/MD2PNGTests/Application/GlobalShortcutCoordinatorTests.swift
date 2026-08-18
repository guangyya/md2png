import AppKit
import XCTest
@testable import MD2PNG

final class GlobalShortcutCoordinatorTests: XCTestCase {
    @MainActor
    func testStartPublishesRegistrationStateAndRoutesAvailableCommands() {
        var capturedRegistrations: [GlobalHotKey.Registration] = []
        let registrar = GlobalHotKeyRegistrar { registrations in
            capturedRegistrations = registrations
            return CoordinatorGlobalHotKeySession(failedRegistrationIDs: [
                GlobalShortcutCommand.showLastRender.rawValue
            ])
        }
        var verifiesShortcut = false
        var performedCommands: [GlobalShortcutCommand] = []
        var publishedStates: [GlobalShortcutCoordinator.State] = []
        let coordinator = GlobalShortcutCoordinator(
            registrar: registrar,
            verify: { _ in verifiesShortcut },
            perform: { performedCommands.append($0) },
            onStateChange: { publishedStates.append($0) }
        )

        let failures = coordinator.start()

        XCTAssertEqual(failures, [GlobalShortcutCommand.showLastRender.rawValue])
        XCTAssertEqual(capturedRegistrations.count, 2)
        XCTAssertEqual(coordinator.configuration, .default)
        XCTAssertEqual(coordinator.failedRegistrationIDs, failures)
        XCTAssertEqual(coordinator.welcomeShortcuts.map(\.isRegistered), [true, false])
        XCTAssertEqual(publishedStates, [coordinator.state])

        capturedRegistrations[0].action()
        verifiesShortcut = true
        capturedRegistrations[1].action()

        XCTAssertEqual(performedCommands, [.render])
    }

    @MainActor
    func testRecordingSuspendsAndRestoresCurrentConfiguration() {
        var sessions: [CoordinatorGlobalHotKeySession] = []
        let registrar = GlobalHotKeyRegistrar { _ in
            let session = CoordinatorGlobalHotKeySession(failedRegistrationIDs: [])
            sessions.append(session)
            return session
        }
        let coordinator = GlobalShortcutCoordinator(
            registrar: registrar,
            verify: { _ in false },
            perform: { _ in }
        )
        coordinator.start()

        coordinator.suspendForRecording()
        coordinator.restoreAfterCancelledRecording()

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].invalidationCount, 1)
        XCTAssertEqual(sessions[1].invalidationCount, 0)
        XCTAssertEqual(coordinator.configuration, .default)
    }
}

@MainActor
private final class CoordinatorGlobalHotKeySession: GlobalHotKeySession {
    let failedRegistrationIDs: Set<UInt32>
    private(set) var invalidationCount = 0

    init(failedRegistrationIDs: Set<UInt32>) {
        self.failedRegistrationIDs = failedRegistrationIDs
    }

    func invalidate() {
        invalidationCount += 1
    }
}
