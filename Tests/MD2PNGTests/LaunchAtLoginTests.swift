import XCTest
@testable import MD2PNG

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testPresentationReflectsEveryEffectiveSystemStatus() {
        let notRegistered = LaunchAtLoginPresentation(status: .notRegistered)
        XCTAssertEqual(notRegistered.toggleState, .off)
        XCTAssertTrue(notRegistered.canToggle)
        XCTAssertFalse(notRegistered.showsSystemSettingsAction)
        XCTAssertFalse(notRegistered.showsUnavailableStatus)

        let enabled = LaunchAtLoginPresentation(status: .enabled)
        XCTAssertEqual(enabled.toggleState, .on)
        XCTAssertTrue(enabled.canToggle)
        XCTAssertFalse(enabled.showsSystemSettingsAction)
        XCTAssertFalse(enabled.showsUnavailableStatus)

        let requiresApproval = LaunchAtLoginPresentation(status: .requiresApproval)
        XCTAssertEqual(requiresApproval.toggleState, .mixed)
        XCTAssertTrue(requiresApproval.canToggle)
        XCTAssertTrue(requiresApproval.showsSystemSettingsAction)
        XCTAssertFalse(requiresApproval.showsUnavailableStatus)

        let notFound = LaunchAtLoginPresentation(status: .notFound)
        XCTAssertEqual(notFound.toggleState, .off)
        XCTAssertTrue(notFound.canToggle)
        XCTAssertFalse(notFound.showsSystemSettingsAction)
        XCTAssertFalse(notFound.showsUnavailableStatus)

        let unknown = LaunchAtLoginPresentation(status: .unknown)
        XCTAssertEqual(unknown.toggleState, .off)
        XCTAssertFalse(unknown.canToggle)
        XCTAssertFalse(unknown.showsSystemSettingsAction)
        XCTAssertTrue(unknown.showsUnavailableStatus)
    }

    func testToggleRegistersAnUnregisteredMainApp() throws {
        let service = LaunchAtLoginServiceStub(status: .notRegistered)
        service.statusAfterRegister = .enabled
        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(try controller.toggle(), .enabled)
        XCTAssertEqual(service.operations, [.register])
    }

    func testToggleUnregistersAnEnabledMainApp() throws {
        let service = LaunchAtLoginServiceStub(status: .enabled)
        service.statusAfterUnregister = .notRegistered
        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(try controller.toggle(), .notRegistered)
        XCTAssertEqual(service.operations, [.unregister])
    }

    func testToggleAttemptsRegistrationWhenNativeStatusIsNotFound() throws {
        let service = LaunchAtLoginServiceStub(status: .notFound)
        service.statusAfterRegister = .enabled
        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(try controller.toggle(), .enabled)
        XCTAssertEqual(service.operations, [.register])
    }

    func testToggleUnregistersARegistrationThatRequiresApproval() throws {
        let service = LaunchAtLoginServiceStub(status: .requiresApproval)
        service.statusAfterUnregister = .notRegistered
        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(try controller.toggle(), .notRegistered)
        XCTAssertEqual(service.operations, [.unregister])
    }

    func testToggleReportsUnavailableWithoutCallingTheSystemService() {
        let service = LaunchAtLoginServiceStub(status: .unknown)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertThrowsError(try controller.toggle()) { error in
            XCTAssertTrue(error is LaunchAtLoginError)
        }
        XCTAssertTrue(service.operations.isEmpty)
    }

    func testPresentationReadsAnExternallyChangedStatus() {
        let service = LaunchAtLoginServiceStub(status: .notRegistered)
        let controller = LaunchAtLoginController(service: service)
        XCTAssertEqual(controller.presentation.toggleState, .off)

        service.status = .requiresApproval

        XCTAssertEqual(controller.presentation.toggleState, .mixed)
        XCTAssertTrue(controller.presentation.showsSystemSettingsAction)
    }

    func testOpenSystemSettingsForwardsToNativeService() {
        let service = LaunchAtLoginServiceStub(status: .requiresApproval)
        let controller = LaunchAtLoginController(service: service)

        controller.openSystemSettings()

        XCTAssertEqual(service.operations, [.openSystemSettings])
    }

    func testLaunchAtLoginLocalizationsResolve() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))

        XCTAssertEqual(
            L10n.text("menu.launch_at_login", defaultValue: "", bundle: english),
            "Launch at Login"
        )
        XCTAssertEqual(
            L10n.text("menu.launch_at_login", defaultValue: "", bundle: chinese),
            "登录时启动"
        )
        XCTAssertEqual(
            L10n.text("menu.open_login_items_settings", defaultValue: "", bundle: chinese),
            "打开登录项设置…"
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
    private(set) var operations: [Operation] = []

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        operations.append(.register)
        if let statusAfterRegister {
            status = statusAfterRegister
        }
    }

    func unregister() throws {
        operations.append(.unregister)
        if let statusAfterUnregister {
            status = statusAfterUnregister
        }
    }

    func openSystemSettings() {
        operations.append(.openSystemSettings)
    }
}
