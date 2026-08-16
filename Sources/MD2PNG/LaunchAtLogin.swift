import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
}

enum LaunchAtLoginToggleState: Equatable {
    case off
    case on
    case mixed
}

struct LaunchAtLoginPresentation: Equatable {
    let toggleState: LaunchAtLoginToggleState
    let canToggle: Bool
    let showsSystemSettingsAction: Bool
    let showsUnavailableStatus: Bool

    init(status: LaunchAtLoginStatus) {
        switch status {
        case .notRegistered:
            toggleState = .off
            canToggle = true
            showsSystemSettingsAction = false
            showsUnavailableStatus = false
        case .enabled:
            toggleState = .on
            canToggle = true
            showsSystemSettingsAction = false
            showsUnavailableStatus = false
        case .requiresApproval:
            toggleState = .mixed
            canToggle = true
            showsSystemSettingsAction = true
            showsUnavailableStatus = false
        case .notFound:
            toggleState = .off
            canToggle = true
            showsSystemSettingsAction = false
            showsUnavailableStatus = false
        case .unknown:
            toggleState = .off
            canToggle = false
            showsSystemSettingsAction = false
            showsUnavailableStatus = true
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
