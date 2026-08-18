import Combine

@MainActor
final class LaunchAtLoginSettingsModel: ObservableObject {
    @Published private(set) var status: LaunchAtLoginStatus
    @Published private(set) var errorMessage: String?

    private let controller: LaunchAtLoginController
    private let onStatusChange: () -> Void

    init(
        controller: LaunchAtLoginController,
        onStatusChange: @escaping () -> Void = {}
    ) {
        self.controller = controller
        self.onStatusChange = onStatusChange
        status = controller.status
    }

    var isEnabled: Bool {
        status == .enabled
    }

    var canChange: Bool {
        status != .unknown
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = controller.status
        errorMessage = nil
    }

    func setEnabled(_ isEnabled: Bool) {
        do {
            status = try controller.setEnabled(isEnabled)
            errorMessage = nil
            if status == .requiresApproval {
                controller.openSystemSettings()
            }
            onStatusChange()
        } catch {
            status = controller.status
            errorMessage = error.localizedDescription
        }
    }

    func performPrimaryAction() {
        switch status {
        case .notRegistered, .notFound:
            setEnabled(true)
        case .enabled:
            setEnabled(false)
        case .requiresApproval:
            controller.openSystemSettings()
        case .unknown:
            break
        }
    }

    func openSystemSettings() {
        controller.openSystemSettings()
    }
}
