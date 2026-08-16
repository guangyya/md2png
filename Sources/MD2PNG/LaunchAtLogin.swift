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
    case unavailable
}

struct LaunchAtLoginPresentation: Equatable {
    let menuAction: LaunchAtLoginMenuAction
    let canToggle: Bool
    let showsSystemSettingsAction: Bool

    init(status: LaunchAtLoginStatus) {
        switch status {
        case .notRegistered, .notFound:
            menuAction = .enable
            canToggle = true
            showsSystemSettingsAction = false
        case .enabled:
            menuAction = .disable
            canToggle = true
            showsSystemSettingsAction = false
        case .requiresApproval:
            menuAction = .disable
            canToggle = true
            showsSystemSettingsAction = true
        case .unknown:
            menuAction = .unavailable
            canToggle = false
            showsSystemSettingsAction = false
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
    func toggle() throws -> LaunchAtLoginStatus {
        switch status {
        case .notRegistered, .notFound:
            try service.register()
        case .enabled, .requiresApproval:
            try service.unregister()
        case .unknown:
            throw LaunchAtLoginError.unavailable
        }
        return status
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
