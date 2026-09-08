import AppKit
import XCTest
@testable import MD2PNG

final class WindowPresentationCoordinatorTests: XCTestCase {
    @MainActor
    func testActivationPolicyTracksEveryWindowSurfaceWithoutRedundantUpdates() {
        var policies: [NSApplication.ActivationPolicy] = []
        let coordinator = WindowActivationCoordinator {
            policies.append($0)
            return true
        }

        coordinator.prepareForApplicationLaunch()
        coordinator.setVisible(true, surface: .preview)
        coordinator.setVisible(true, surface: .about)
        coordinator.setVisible(false, surface: .preview)
        coordinator.setVisible(false, surface: .about)

        XCTAssertEqual(policies, [.accessory, .regular, .accessory])
        XCTAssertTrue(coordinator.visibleSurfaces.isEmpty)
    }

    @MainActor
    func testClosingOneOfSeveralWindowsKeepsRegularActivationPolicy() {
        var policies: [NSApplication.ActivationPolicy] = []
        let coordinator = WindowActivationCoordinator {
            policies.append($0)
            return true
        }
        coordinator.prepareForApplicationLaunch()

        coordinator.setVisible(true, surface: .welcome)
        coordinator.setVisible(true, surface: .settings)
        coordinator.setVisible(false, surface: .welcome)

        XCTAssertEqual(policies, [.accessory, .regular])
        XCTAssertEqual(coordinator.visibleSurfaces, [.settings])
        XCTAssertTrue(coordinator.isVisible(.settings))
    }

    @MainActor
    func testFailedActivationPolicyApplicationIsRetried() {
        var policies: [NSApplication.ActivationPolicy] = []
        var shouldSucceed = false
        let coordinator = WindowActivationCoordinator { policy in
            policies.append(policy)
            defer { shouldSucceed = true }
            return shouldSucceed
        }

        coordinator.prepareForApplicationLaunch()
        coordinator.reconcilePresentedSurfaces { _ in false }

        XCTAssertEqual(policies, [.accessory, .accessory])
    }

    @MainActor
    func testReconciliationRemovesStaleSurfacesAndReappliesPolicy() {
        var policies: [NSApplication.ActivationPolicy] = []
        let coordinator = WindowActivationCoordinator { policy in
            policies.append(policy)
            return true
        }

        coordinator.prepareForApplicationLaunch()
        coordinator.setVisible(true, surface: .preview)
        coordinator.reconcilePresentedSurfaces { _ in false }

        XCTAssertEqual(policies, [.accessory, .regular, .accessory])
        XCTAssertTrue(coordinator.visibleSurfaces.isEmpty)
    }
}
