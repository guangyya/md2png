import AppKit

enum AppWindowSurface: Hashable {
    case preview
    case welcome
    case settings
    case about
}

@MainActor
final class WindowActivationCoordinator {
    private let applyPolicy: (NSApplication.ActivationPolicy) -> Void
    private(set) var visibleSurfaces: Set<AppWindowSurface> = []
    private var appliedPolicy: NSApplication.ActivationPolicy?

    init(
        applyPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = {
            NSApp.setActivationPolicy($0)
        }
    ) {
        self.applyPolicy = applyPolicy
    }

    func prepareForApplicationLaunch() {
        apply(.accessory)
    }

    func setVisible(_ isVisible: Bool, surface: AppWindowSurface) {
        if isVisible {
            visibleSurfaces.insert(surface)
        } else {
            visibleSurfaces.remove(surface)
        }
        apply(visibleSurfaces.isEmpty ? .accessory : .regular)
    }

    func isVisible(_ surface: AppWindowSurface) -> Bool {
        visibleSurfaces.contains(surface)
    }

    private func apply(_ policy: NSApplication.ActivationPolicy) {
        guard policy != appliedPolicy else { return }
        appliedPolicy = policy
        applyPolicy(policy)
    }
}

@MainActor
final class WindowPresentationCoordinator {
    struct ShortcutState {
        let configuration: GlobalShortcutConfiguration
        let failedRegistrationIDs: Set<UInt32>
    }

    struct Actions {
        let previewCopied: (Int) -> Void
        let showError: (Error) -> Void
        let applyShortcuts: (GlobalShortcutConfiguration) -> Set<UInt32>
        let suspendShortcuts: () -> Void
        let restoreShortcuts: () -> Void
        let trySample: () -> Void
        let dismissTransientPresentation: () -> Void
    }

    private let updateController: UpdateController
    private let diagnosticLogger: DiagnosticLogger
    private let launchAtLoginController: LaunchAtLoginController
    private let welcomePreference: WelcomePreference
    private let globalShortcutPreference: GlobalShortcutPreference
    private let shortcutState: () -> ShortcutState
    private let actions: Actions
    private let activationCoordinator: WindowActivationCoordinator
    private let previewDragExportStore: PreviewDragExportStore

    private lazy var previewController = PreviewController(
        onCopied: { [weak self] changeCount in
            self?.actions.previewCopied(changeCount)
        },
        onError: { [weak self] error in
            self?.actions.showError(error)
        },
        onVisibilityChange: { [weak self] isVisible in
            self?.setVisible(isVisible, surface: .preview)
        },
        onShowSettings: { [weak self] in
            self?.showSettings()
        },
        dragExportStore: previewDragExportStore
    )
    private lazy var aboutController = AboutController(
        updateController: updateController,
        diagnosticLogger: diagnosticLogger,
        onVisibilityChange: { [weak self] isVisible in
            self?.setVisible(isVisible, surface: .about)
        },
        onShowSettings: { [weak self] in
            self?.showSettings()
        }
    )
    private lazy var settingsController = SettingsController(
        preference: globalShortcutPreference,
        launchAtLoginController: launchAtLoginController,
        onApply: { [weak self] configuration in
            self?.actions.applyShortcuts(configuration) ?? []
        },
        onRecordingBegan: { [weak self] in
            self?.actions.suspendShortcuts()
        },
        onRecordingCancelled: { [weak self] in
            self?.actions.restoreShortcuts()
        },
        onLaunchAtLoginChange: { [weak self] in
            self?.refreshWelcomeLaunchAtLoginIfVisible()
        },
        onVisibilityChange: { [weak self] isVisible in
            self?.setVisible(isVisible, surface: .settings)
        }
    )
    private lazy var welcomeController = WelcomeController(
        preference: welcomePreference,
        launchAtLoginController: launchAtLoginController,
        onLaunchAtLoginError: { [weak self] error in
            self?.actions.showError(error)
        },
        onVisibilityChange: { [weak self] isVisible in
            self?.setVisible(isVisible, surface: .welcome)
        },
        onShowSettings: { [weak self] in
            self?.showSettings()
        },
        onTrySample: { [weak self] in
            self?.actions.trySample()
        }
    )

    init(
        updateController: UpdateController,
        diagnosticLogger: DiagnosticLogger,
        launchAtLoginController: LaunchAtLoginController,
        welcomePreference: WelcomePreference,
        globalShortcutPreference: GlobalShortcutPreference,
        shortcutState: @escaping () -> ShortcutState,
        actions: Actions,
        activationCoordinator: WindowActivationCoordinator = WindowActivationCoordinator(),
        previewDragExportStore: PreviewDragExportStore = PreviewDragExportStore()
    ) {
        self.updateController = updateController
        self.diagnosticLogger = diagnosticLogger
        self.launchAtLoginController = launchAtLoginController
        self.welcomePreference = welcomePreference
        self.globalShortcutPreference = globalShortcutPreference
        self.shortcutState = shortcutState
        self.actions = actions
        self.activationCoordinator = activationCoordinator
        self.previewDragExportStore = previewDragExportStore
    }

    func prepareForApplicationLaunch() {
        activationCoordinator.prepareForApplicationLaunch()
    }

    func prepareForApplicationTermination() {
        previewDragExportStore.clear()
    }

    func showPreview(_ lastRender: LastRender) {
        previewController.show(
            image: lastRender.image,
            widthPreset: lastRender.widthPreset,
            markdown: lastRender.markdown
        )
    }

    func showAbout() {
        aboutController.show()
    }

    func showSettings() {
        actions.dismissTransientPresentation()
        let state = shortcutState()
        settingsController.show(
            configuration: state.configuration,
            failedRegistrationIDs: state.failedRegistrationIDs
        )
    }

    func showWelcome(shortcuts: [WelcomeShortcutStatus]) {
        welcomeController.show(shortcuts: shortcuts)
    }

    @discardableResult
    func showWelcomeIfNeeded(shortcuts: [WelcomeShortcutStatus]) -> Bool {
        welcomeController.showIfNeeded(shortcuts: shortcuts)
    }

    func verifyShortcut(_ command: GlobalShortcutCommand) -> Bool {
        guard isVisible(.welcome) else { return false }
        return welcomeController.verifyShortcut(command)
    }

    func refreshWelcomeShortcutsIfVisible(_ shortcuts: [WelcomeShortcutStatus]) {
        guard isVisible(.welcome) else { return }
        welcomeController.refreshShortcuts(shortcuts)
    }

    func refreshLaunchAtLoginIfVisible() {
        if isVisible(.welcome) {
            welcomeController.refreshLaunchAtLogin()
        }
        if isVisible(.settings) {
            settingsController.refreshLaunchAtLogin()
        }
    }

    func isVisible(_ surface: AppWindowSurface) -> Bool {
        activationCoordinator.isVisible(surface)
    }

    private func setVisible(_ isVisible: Bool, surface: AppWindowSurface) {
        activationCoordinator.setVisible(isVisible, surface: surface)
    }

    private func refreshWelcomeLaunchAtLoginIfVisible() {
        guard isVisible(.welcome) else { return }
        welcomeController.refreshLaunchAtLogin()
    }

#if DEBUG
    func setVisibleForTesting(_ isVisible: Bool, surface: AppWindowSurface) {
        setVisible(isVisible, surface: surface)
    }

    func triggerWelcomeSampleGuideForTesting() {
        welcomeController.trySampleForTesting()
    }
#endif
}
