import AppKit
import XCTest
@testable import MD2PNG

final class WindowPresentationCoordinatorTests: XCTestCase {
    @MainActor
    func testActivationPolicyTracksEveryWindowSurfaceWithoutRedundantUpdates() {
        var policies: [NSApplication.ActivationPolicy] = []
        let coordinator = WindowActivationCoordinator {
            policies.append($0)
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
        }
        coordinator.prepareForApplicationLaunch()

        coordinator.setVisible(true, surface: .welcome)
        coordinator.setVisible(true, surface: .settings)
        coordinator.setVisible(false, surface: .welcome)

        XCTAssertEqual(policies, [.accessory, .regular])
        XCTAssertEqual(coordinator.visibleSurfaces, [.settings])
        XCTAssertTrue(coordinator.isVisible(.settings))
    }
}
