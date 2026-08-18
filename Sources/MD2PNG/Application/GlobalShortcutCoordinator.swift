import Foundation

@MainActor
final class GlobalShortcutCoordinator {
    struct State: Equatable {
        let configuration: GlobalShortcutConfiguration
        let failedRegistrationIDs: Set<UInt32>
        let welcomeShortcuts: [WelcomeShortcutStatus]
    }

    private let registrar: GlobalHotKeyRegistrar
    private let diagnosticLogger: DiagnosticLogger
    private let router: GlobalShortcutRouter
    private let onStateChange: (State) -> Void
    private(set) var state: State

    init(
        preference: GlobalShortcutPreference = GlobalShortcutPreference(),
        registrar: GlobalHotKeyRegistrar = GlobalHotKeyRegistrar(),
        diagnosticLogger: DiagnosticLogger = .disabled,
        verify: @escaping (GlobalShortcutCommand) -> Bool,
        perform: @escaping (GlobalShortcutCommand) -> Void,
        onStateChange: @escaping (State) -> Void = { _ in }
    ) {
        let configuration = preference.configuration
        self.registrar = registrar
        self.diagnosticLogger = diagnosticLogger
        router = GlobalShortcutRouter(verify: verify, perform: perform)
        self.onStateChange = onStateChange
        state = State(
            configuration: configuration,
            failedRegistrationIDs: [],
            welcomeShortcuts: []
        )
    }

    var configuration: GlobalShortcutConfiguration {
        state.configuration
    }

    var failedRegistrationIDs: Set<UInt32> {
        state.failedRegistrationIDs
    }

    var welcomeShortcuts: [WelcomeShortcutStatus] {
        state.welcomeShortcuts
    }

    @discardableResult
    func start() -> Set<UInt32> {
        apply(configuration)
    }

    @discardableResult
    func apply(_ configuration: GlobalShortcutConfiguration) -> Set<UInt32> {
        precondition(configuration.isValid)
        let registrations: [GlobalHotKey.Registration] = [
            .render(shortcut: configuration.render) { [weak self] in
                self?.handle(.render)
            },
            .showLastRender(shortcut: configuration.showLastRender) { [weak self] in
                self?.handle(.showLastRender)
            }
        ]
        let failedRegistrationIDs = registrar.replace(registrations: registrations)
        state = State(
            configuration: configuration,
            failedRegistrationIDs: failedRegistrationIDs,
            welcomeShortcuts: registrations.map {
                WelcomeShortcutStatus(
                    registration: $0,
                    failedRegistrationIDs: failedRegistrationIDs
                )
            }
        )
        onStateChange(state)
        diagnosticLogger.record(
            category: .shortcut,
            stage: .shortcutRegistration,
            result: failedRegistrationIDs.isEmpty ? .succeeded : .failed,
            level: failedRegistrationIDs.isEmpty ? .info : .error,
            itemCount: registrations.count,
            failureCount: failedRegistrationIDs.count
        )
        return failedRegistrationIDs
    }

    func suspendForRecording() {
        // Carbon hot keys consume their matching event before the focused
        // recorder can capture it, so suspend them for the recording session.
        registrar.invalidate()
    }

    func restoreAfterCancelledRecording() {
        apply(configuration)
    }

    private func handle(_ command: GlobalShortcutCommand) {
        router.handle(command)
    }
}
