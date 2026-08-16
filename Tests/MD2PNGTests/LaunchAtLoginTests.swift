import XCTest
@testable import MD2PNG

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testPresentationReflectsEveryEffectiveSystemStatus() {
        let notRegistered = LaunchAtLoginPresentation(status: .notRegistered)
        XCTAssertEqual(notRegistered.menuAction, .enable)
        XCTAssertTrue(notRegistered.canToggle)
        XCTAssertFalse(notRegistered.showsSystemSettingsAction)

        let enabled = LaunchAtLoginPresentation(status: .enabled)
        XCTAssertEqual(enabled.menuAction, .disable)
        XCTAssertTrue(enabled.canToggle)
        XCTAssertFalse(enabled.showsSystemSettingsAction)

        let requiresApproval = LaunchAtLoginPresentation(status: .requiresApproval)
        XCTAssertEqual(requiresApproval.menuAction, .disable)
        XCTAssertTrue(requiresApproval.canToggle)
        XCTAssertTrue(requiresApproval.showsSystemSettingsAction)

        let notFound = LaunchAtLoginPresentation(status: .notFound)
        XCTAssertEqual(notFound.menuAction, .enable)
        XCTAssertTrue(notFound.canToggle)
        XCTAssertFalse(notFound.showsSystemSettingsAction)

        let unknown = LaunchAtLoginPresentation(status: .unknown)
        XCTAssertEqual(unknown.menuAction, .unavailable)
        XCTAssertFalse(unknown.canToggle)
        XCTAssertFalse(unknown.showsSystemSettingsAction)
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
        XCTAssertEqual(controller.presentation.menuAction, .enable)

        service.status = .requiresApproval

        XCTAssertEqual(controller.presentation.menuAction, .disable)
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
            L10n.text("menu.enable_launch_at_login", defaultValue: "", bundle: english),
            "Enable Launch at Login"
        )
        XCTAssertEqual(
            L10n.text("menu.disable_launch_at_login", defaultValue: "", bundle: english),
            "Disable Launch at Login"
        )
        XCTAssertEqual(
            L10n.text("menu.enable_launch_at_login", defaultValue: "", bundle: chinese),
            "启用登录时启动"
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
