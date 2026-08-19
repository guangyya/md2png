import SwiftUI

@MainActor
final class WelcomeShortcutVerificationState: ObservableObject {
    @Published private(set) var shortcuts: [WelcomeShortcutStatus] = []

    func reset(shortcuts: [WelcomeShortcutStatus]) {
        self.shortcuts = shortcuts.map { shortcut in
            var shortcut = shortcut
            shortcut.resetVerification()
            return shortcut
        }
    }

    @discardableResult
    func verify(id: UInt32) -> WelcomeShortcutStatus? {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }),
              shortcuts[index].verify() else { return nil }
        return shortcuts[index]
    }
}

@MainActor
final class WelcomeLaunchAtLoginState: ObservableObject {
    @Published private(set) var presentation: LaunchAtLoginPresentation

    private let controller: LaunchAtLoginController
    private let onError: (Error) -> Void

    init(
        controller: LaunchAtLoginController,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.controller = controller
        self.onError = onError
        presentation = controller.presentation
    }

    func refresh() {
        presentation = controller.presentation
    }

    func performPrimaryAction() {
        do {
            let result = try controller.performPrimaryAction()
            if result == .statusChanged(.requiresApproval) {
                controller.openSystemSettings()
            }
        } catch {
            onError(error)
        }
        refresh()
    }
}
