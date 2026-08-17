import XCTest
@testable import MD2PNG

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testPresentationReflectsEveryEffectiveSystemStatus() {
        let notRegistered = LaunchAtLoginPresentation(status: .notRegistered)
        XCTAssertEqual(notRegistered.menuAction, .enable)
        XCTAssertTrue(notRegistered.canPerformAction)

        let enabled = LaunchAtLoginPresentation(status: .enabled)
        XCTAssertEqual(enabled.menuAction, .disable)
        XCTAssertTrue(enabled.canPerformAction)

        let requiresApproval = LaunchAtLoginPresentation(status: .requiresApproval)
        XCTAssertEqual(requiresApproval.menuAction, .allowInSystemSettings)
        XCTAssertTrue(requiresApproval.canPerformAction)

        let notFound = LaunchAtLoginPresentation(status: .notFound)
        XCTAssertEqual(notFound.menuAction, .enable)
        XCTAssertTrue(notFound.canPerformAction)

        let unknown = LaunchAtLoginPresentation(status: .unknown)
        XCTAssertEqual(unknown.menuAction, .unavailable)
        XCTAssertFalse(unknown.canPerformAction)
    }

    func testPrimaryActionRegistersAnUnregisteredMainApp() throws {
        let service = LaunchAtLoginServiceStub(status: .notRegistered)
        service.statusAfterRegister = .enabled
        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(try controller.performPrimaryAction(), .statusChanged(.enabled))
        XCTAssertEqual(service.operations, [.register])
    }

    func testPrimaryActionUnregistersAnEnabledMainApp() throws {
        let service = LaunchAtLoginServiceStub(status: .enabled)
        service.statusAfterUnregister = .notRegistered
        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(try controller.performPrimaryAction(), .statusChanged(.notRegistered))
        XCTAssertEqual(service.operations, [.unregister])
    }

    func testPrimaryActionAttemptsRegistrationWhenNativeStatusIsNotFound() throws {
        let service = LaunchAtLoginServiceStub(status: .notFound)
        service.statusAfterRegister = .enabled
        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(try controller.performPrimaryAction(), .statusChanged(.enabled))
        XCTAssertEqual(service.operations, [.register])
    }

    func testPrimaryActionOpensSettingsWhenApprovalIsRequired() throws {
        let service = LaunchAtLoginServiceStub(status: .requiresApproval)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(try controller.performPrimaryAction(), .openedSystemSettings)
        XCTAssertEqual(service.operations, [.openSystemSettings])
    }

    func testPrimaryActionReturnsApprovalTransitionAfterRegistration() throws {
        let service = LaunchAtLoginServiceStub(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(
            try controller.performPrimaryAction(),
            .statusChanged(.requiresApproval)
        )
        XCTAssertEqual(service.operations, [.register])
    }

    func testPrimaryActionReportsUnavailableWithoutCallingTheSystemService() {
        let service = LaunchAtLoginServiceStub(status: .unknown)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertThrowsError(try controller.performPrimaryAction()) { error in
            XCTAssertTrue(error is LaunchAtLoginError)
        }
        XCTAssertTrue(service.operations.isEmpty)
    }

    func testPrimaryActionHidesRawSystemRegistrationFailures() {
        let service = LaunchAtLoginServiceStub(status: .notRegistered)
        service.operationError = CocoaError(.fileWriteNoPermission)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertThrowsError(try controller.performPrimaryAction()) { error in
            guard let launchError = error as? LaunchAtLoginError,
                  case .changeFailed = launchError else {
                XCTFail("Expected a privacy-safe Launch at Login error, got \(error)")
                return
            }
            XCTAssertFalse(error.localizedDescription.contains("permission"))
        }
        XCTAssertEqual(service.operations, [.register])
    }

    func testPresentationReadsAnExternallyChangedStatus() {
        let service = LaunchAtLoginServiceStub(status: .notRegistered)
        let controller = LaunchAtLoginController(service: service)
        XCTAssertEqual(controller.presentation.menuAction, .enable)

        service.status = .requiresApproval

        XCTAssertEqual(controller.presentation.menuAction, .allowInSystemSettings)
    }

    func testLaunchAtLoginLocalizationsResolve() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))

        XCTAssertEqual(
            L10n.text("menu.enable_launch_at_login", defaultValue: "", bundle: english),
            "Enable Launch at Login"
        )
        XCTAssertEqual(
            L10n.text("menu.disable_launch_at_login", defaultValue: "", bundle: english),
            "Disable Launch at Login"
        )
        XCTAssertEqual(
            L10n.text("menu.allow_launch_at_login", defaultValue: "", bundle: english),
            "Allow Launch at Login…"
        )
        XCTAssertEqual(
            L10n.text("menu.enable_launch_at_login", defaultValue: "", bundle: chinese),
            "启用登录时启动"
        )
        XCTAssertEqual(
            L10n.text("menu.allow_launch_at_login", defaultValue: "", bundle: chinese),
            "允许登录时启动…"
        )
    }
}

@MainActor
private final class LaunchAtLoginServiceStub: LaunchAtLoginServicing {
    enum Operation: Equatable {
        case register
        case unregister
        case openSystemSettings
    }

    var status: LaunchAtLoginStatus
    var statusAfterRegister: LaunchAtLoginStatus?
    var statusAfterUnregister: LaunchAtLoginStatus?
    var operationError: Error?
    private(set) var operations: [Operation] = []

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        operations.append(.register)
        if let operationError { throw operationError }
        if let statusAfterRegister {
            status = statusAfterRegister
        }
    }

    func unregister() throws {
        operations.append(.unregister)
        if let operationError { throw operationError }
        if let statusAfterUnregister {
            status = statusAfterUnregister
        }
    }

    func openSystemSettings() {
        operations.append(.openSystemSettings)
    }
}
