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
    case changeFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return L10n.text(
                "error.launch_at_login_unavailable",
                defaultValue: "Couldn’t change Launch at Login. Open System Settings and update Login Items manually."
            )
        case .changeFailed:
            return L10n.text(
                "error.launch_at_login_failed",
                defaultValue: "Couldn’t change Launch at Login. Reopen md2png and try again."
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
    func setEnabled(_ isEnabled: Bool) throws -> LaunchAtLoginStatus {
        switch (isEnabled, status) {
        case (true, .notRegistered), (true, .notFound):
            do {
                try service.register()
            } catch {
                throw LaunchAtLoginError.changeFailed
            }
        case (false, .enabled), (false, .requiresApproval):
            do {
                try service.unregister()
            } catch {
                throw LaunchAtLoginError.changeFailed
            }
        case (_, .unknown):
            throw LaunchAtLoginError.unavailable
        case (true, .enabled), (true, .requiresApproval),
             (false, .notRegistered), (false, .notFound):
            break
        }
        return status
    }

    @discardableResult
    func performPrimaryAction() throws -> LaunchAtLoginActionResult {
        switch status {
        case .notRegistered, .notFound:
            do {
                try service.register()
            } catch {
                throw LaunchAtLoginError.changeFailed
            }
            return .statusChanged(status)
        case .enabled:
            do {
                try service.unregister()
            } catch {
                throw LaunchAtLoginError.changeFailed
            }
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
