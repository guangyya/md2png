import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
}

enum LaunchAtLoginMenuAction: Equatable {
    case enable
    case disable
    case allowInSystemSettings
    case unavailable
}

enum LaunchAtLoginActionResult: Equatable {
    case statusChanged(LaunchAtLoginStatus)
    case openedSystemSettings
}

struct LaunchAtLoginPresentation: Equatable {
    let menuAction: LaunchAtLoginMenuAction
    let canPerformAction: Bool

    init(status: LaunchAtLoginStatus) {
        switch status {
        case .notRegistered, .notFound:
            menuAction = .enable
            canPerformAction = true
        case .enabled:
            menuAction = .disable
            canPerformAction = true
        case .requiresApproval:
            menuAction = .allowInSystemSettings
            canPerformAction = true
        case .unknown:
            menuAction = .unavailable
            canPerformAction = false
        }
    }
}

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
final class SystemLaunchAtLoginService: LaunchAtLoginServicing {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .unknown
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

enum LaunchAtLoginError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return L10n.text(
                "error.launch_at_login_unavailable",
                defaultValue: "Launch at Login is unavailable for this copy of md2png."
            )
        }
    }
}

@MainActor
final class LaunchAtLoginController {
    private let service: LaunchAtLoginServicing

    init(service: LaunchAtLoginServicing = SystemLaunchAtLoginService()) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        service.status
    }

    var presentation: LaunchAtLoginPresentation {
        LaunchAtLoginPresentation(status: status)
    }

    @discardableResult
    func performPrimaryAction() throws -> LaunchAtLoginActionResult {
        switch status {
        case .notRegistered, .notFound:
            try service.register()
            return .statusChanged(status)
        case .enabled:
            try service.unregister()
            return .statusChanged(status)
        case .requiresApproval:
            openSystemSettings()
            return .openedSystemSettings
        case .unknown:
            throw LaunchAtLoginError.unavailable
        }
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
