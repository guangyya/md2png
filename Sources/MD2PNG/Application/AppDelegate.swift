import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let diagnosticLogger: DiagnosticLogger
    private lazy var hud = HUDController { [weak self] message, priority in
        self?.announce(message, priority: priority)
    }
    private let rendererErrorDetailsPresenter = RendererErrorDetailsPresenter()
    private lazy var previewController = PreviewController(
        onCopied: { [weak self] changeCount in
            guard let self else { return }
            self.renderCoordinator.recordOwnedClipboardWrite(changeCount: changeCount)
            self.hud.show(
                L10n.text(
                    "hud.png_copied_again",
                    defaultValue: "PNG copied again — paste with Command-V"
                ),
                symbol: "doc.on.clipboard.fill"
            )
        },
        onError: { [weak self] error in
            self?.show(error)
        },
        onVisibilityChange: { [weak self] isVisible in
            self?.setPreviewWindowVisible(isVisible)
        },
        onShowSettings: { [weak self] in
            self?.showShortcutSettings()
        }
    )
    private lazy var updateController = UpdateController(
        diagnosticLogger: diagnosticLogger,
        updateDriver: SparkleUpdateDriver {
            UpdateChannel.current().repository?.appcastURL
        },
        beforeInstallAndRelaunch: { [weak self] update in
            self?.approveInstallAndRelaunch(update) ?? false
        },
        onInstallAccepted: { [weak self] in
            self?.setUpdateInstallPending(true)
        },
        onInstallEndedWithoutRelaunch: { [weak self] in
            self?.setUpdateInstallPending(false)
        }
    )
    private lazy var aboutController = AboutController(
        updateController: updateController,
        diagnosticLogger: diagnosticLogger,
        onShowSettings: { [weak self] in
            self?.showShortcutSettings()
        }
    )
    private let launchAtLoginController = LaunchAtLoginController()
    private let welcomePreference = WelcomePreference()
    private let globalShortcutPreference: GlobalShortcutPreference
    private lazy var shortcutSettingsController = ShortcutSettingsController(
        preference: globalShortcutPreference,
        onApply: { [weak self] configuration in
            self?.registerGlobalShortcuts(configuration: configuration) ?? []
        },
        onVisibilityChange: { [weak self] isVisible in
            self?.setShortcutSettingsWindowVisible(isVisible)
        }
    )
    private lazy var welcomeController = WelcomeController(
        preference: welcomePreference,
        launchAtLoginController: launchAtLoginController,
        onLaunchAtLoginError: { [weak self] error in
            self?.show(error)
        },
        onVisibilityChange: { [weak self] isVisible in
            self?.setWelcomeWindowVisible(isVisible)
        },
        onShowSettings: { [weak self] in
            self?.showShortcutSettings()
        },
        onTrySample: { [weak self] in self?.showSampleGuide() }
    )
    private let injectedSampleGuidePresenter: (any SampleGuidePresenting)?
    private lazy var sampleGuidePresenter: any SampleGuidePresenting = {
        if let injectedSampleGuidePresenter {
            return injectedSampleGuidePresenter
        }
        return SampleGuideController(
            onChoose: { [weak self] kind in
                self?.renderCoordinator.renderExample(kind)
            }
        )
    }()
    private lazy var globalShortcutRouter = GlobalShortcutRouter(
        verify: { [weak self] command in
            self?.welcomeController.verifyShortcut(command) ?? false
        },
        perform: { [weak self] command in
            guard let self else { return }
            switch command {
            case .render:
                self.renderCoordinator.renderClipboard()
            case .showLastRender:
                self.renderCoordinator.showLastRender()
            }
        }
    )
    private lazy var renderCoordinator = RenderCoordinator(
        diagnosticLogger: diagnosticLogger,
        confirmClipboardOverwrite: { [weak self] action in
            self?.confirmClipboardOverwrite(action) ?? false
        },
        onStateChange: { [weak self] state in
            self?.applyRenderState(state)
        },
        onNotice: { [weak self] notice in
            self?.show(notice)
        },
        onError: { [weak self] error in
            self?.show(error)
        },
        onPreviewRequested: { [weak self] lastRender in
            self?.show(lastRender)
        }
    )
    private lazy var updateStatusPresenter = UpdateStatusPresenter(
        showHUD: { [weak self] message, symbol, style in
            self?.hud.show(
                message,
                symbol: symbol,
                style: style,
                announces: false
            )
        },
        applyStatusItem: { [weak self] presentation in
            self?.statusMenuController?.applyStatusItem(presentation)
        },
        isAboutVisible: { [weak self] in
            self?.aboutController.window?.isVisible == true
        },
        announce: { [weak self] message in
            self?.announce(message, priority: .medium)
        }
    )

    private var statusMenuController: StatusMenuController?
    private let globalHotKeyRegistrar = GlobalHotKeyRegistrar()
    private var globalShortcutConfiguration = GlobalShortcutConfiguration.default
    private var failedGlobalShortcutRegistrationIDs: Set<UInt32> = []
    private var welcomeShortcutStatuses: [WelcomeShortcutStatus] = []
    private var clipboardContainsMarkdown = false
    private var isSampleGuidePresentationScheduled = false
    private var isWaitingForUpdateDeferralBeforeTermination = false
    private var updateStatusObserverID: UUID?
    private var isPreviewWindowVisible = false
    private var isWelcomeWindowVisible = false
    private var isShortcutSettingsWindowVisible = false

#if DEBUG
    var clipboardMenuRefreshCountForTesting: Int {
        statusMenuController?.clipboardPreviewUpdateCount ?? 0
    }
#endif

    override convenience init() {
        self.init(sampleGuidePresenter: nil, diagnosticLogger: .shared)
    }

    init(
        sampleGuidePresenter: (any SampleGuidePresenting)?,
        diagnosticLogger: DiagnosticLogger = .disabled,
        globalShortcutPreference: GlobalShortcutPreference = GlobalShortcutPreference()
    ) {
        injectedSampleGuidePresenter = sampleGuidePresenter
        self.diagnosticLogger = diagnosticLogger
        self.globalShortcutPreference = globalShortcutPreference
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        diagnosticLogger.record(
            category: .appLifecycle,
            stage: .applicationLaunch,
            result: .started
        )
        NSApp.setActivationPolicy(.accessory)
        globalShortcutConfiguration = globalShortcutPreference.configuration
        configureStatusItem()
        updateStatusPresenter.presentRelaunchResultIfNeeded()

        let failedRegistrationIDs = registerGlobalShortcuts(
            configuration: globalShortcutConfiguration
        )

        if welcomePreference.shouldShowOnLaunch {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.welcomeController.showIfNeeded(
                    shortcuts: self.welcomeShortcutStatuses
                )
            }
        } else if !failedRegistrationIDs.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.hud.show(
                    L10n.text(
                        "hud.shortcut_conflict",
                        defaultValue: "A global shortcut is already in use — menu commands still work"
                    ),
                    symbol: "keyboard.badge.ellipsis",
                    style: .error
                )
            }
        }
        diagnosticLogger.record(
            category: .appLifecycle,
            stage: .applicationLaunch,
            result: .succeeded
        )
    }

    @discardableResult
    private func registerGlobalShortcuts(
        configuration: GlobalShortcutConfiguration
    ) -> Set<UInt32> {
        precondition(configuration.isValid)
        let registrations: [GlobalHotKey.Registration] = [
            .render(shortcut: configuration.render) { [weak self] in
                self?.globalShortcutRouter.handle(.render)
            },
            .showLastRender(shortcut: configuration.showLastRender) { [weak self] in
                self?.globalShortcutRouter.handle(.showLastRender)
            }
        ]
        let failedRegistrationIDs = globalHotKeyRegistrar.replace(
            registrations: registrations
        )
        globalShortcutConfiguration = configuration
        failedGlobalShortcutRegistrationIDs = failedRegistrationIDs
        welcomeShortcutStatuses = registrations.map {
            WelcomeShortcutStatus(
                registration: $0,
                failedRegistrationIDs: failedRegistrationIDs
            )
        }
        statusMenuController?.applyShortcuts(configuration)
        if isWelcomeWindowVisible {
            welcomeController.refreshShortcuts(welcomeShortcutStatuses)
        }
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

    func applicationDidBecomeActive(_ notification: Notification) {
        diagnosticLogger.record(
            category: .appLifecycle,
            stage: .applicationActive,
            result: .succeeded,
            level: .verbose
        )
        guard statusMenuController != nil else { return }
        updateLaunchAtLoginMenu()
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if renderCoordinator.isUpdateInstallPending {
            diagnosticLogger.record(
                category: .appLifecycle,
                stage: .applicationTermination,
                result: .accepted
            )
            return .terminateNow
        }
        if isWaitingForUpdateDeferralBeforeTermination {
            diagnosticLogger.record(
                category: .appLifecycle,
                stage: .applicationTermination,
                result: .deferred,
                level: .verbose
            )
            return .terminateLater
        }

        isWaitingForUpdateDeferralBeforeTermination = true
        let waitsForDeferral = updateController
            .cancelPreparedInstallationForApplicationTermination { [weak self] in
                DispatchQueue.main.async {
                    guard let self,
                          self.isWaitingForUpdateDeferralBeforeTermination else {
                        return
                    }
                    self.isWaitingForUpdateDeferralBeforeTermination = false
                    self.diagnosticLogger.record(
                        category: .appLifecycle,
                        stage: .applicationTermination,
                        result: .accepted
                    )
                    sender.reply(toApplicationShouldTerminate: true)
                }
            }
        if waitsForDeferral {
            diagnosticLogger.record(
                category: .appLifecycle,
                stage: .applicationTermination,
                result: .deferred
            )
            return .terminateLater
        }
        isWaitingForUpdateDeferralBeforeTermination = false
        diagnosticLogger.record(
            category: .appLifecycle,
            stage: .applicationTermination,
            result: .accepted
        )
        return .terminateNow
    }

    private func configureStatusItem() {
        guard statusMenuController == nil else { return }
        let renderState = renderCoordinator.state
        let controller = StatusMenuController(
            selectedWidthPreset: renderState.selectedWidthPreset,
            selectedTheme: renderState.selectedTheme,
            shortcutConfiguration: globalShortcutConfiguration,
            actions: StatusMenuController.Actions(
                menuWillOpen: { [weak self] in self?.statusMenuWillOpen() },
                renderClipboard: { [weak self] in
                    self?.renderCoordinator.renderClipboard()
                },
                saveClipboardAsSplitPNGs: { [weak self] in
                    self?.renderCoordinator.saveClipboardAsSplitPNGs()
                },
                showLastRender: { [weak self] in
                    self?.renderCoordinator.showLastRender()
                },
                rerenderLastMarkdown: { [weak self] in
                    self?.renderCoordinator.rerenderLastMarkdown()
                },
                restoreLastMarkdown: { [weak self] in
                    self?.renderCoordinator.restoreLastMarkdown()
                },
                renderExample: { [weak self] kind in
                    self?.renderCoordinator.renderExample(kind)
                },
                selectWidthPreset: { [weak self] preset in
                    self?.renderCoordinator.selectWidthPreset(preset)
                },
                selectTheme: { [weak self] theme in
                    self?.renderCoordinator.selectTheme(theme)
                },
                performLaunchAtLoginAction: { [weak self] in
                    self?.performLaunchAtLoginAction()
                },
                showSettings: { [weak self] in self?.showShortcutSettings() },
                showWelcome: { [weak self] in self?.showWelcome() },
                showAbout: { [weak self] in self?.showAbout() },
                quit: { NSApp.terminate(nil) }
            )
        )
        statusMenuController = controller
        refreshClipboardMenuState()
        applyRenderState(renderState)
        updateLaunchAtLoginMenu()

        updateStatusObserverID = updateController.observeStatus { [weak self] status in
            self?.updateStatusPresenter.apply(status)
        }
    }

    private func statusMenuWillOpen() {
        sampleGuidePresenter.dismiss()
        refreshClipboardMenuState()
        updateLaunchAtLoginMenu()
    }

    private func applyRenderState(_ state: RenderCoordinatorState) {
        guard let statusMenuController else { return }
        statusMenuController.selectWidthPreset(state.selectedWidthPreset)
        statusMenuController.selectTheme(state.selectedTheme)
        statusMenuController.apply(StatusMenuPresentation(state: StatusMenuState(
            clipboardContainsMarkdown: clipboardContainsMarkdown,
            hasLastSource: state.hasLastSource,
            hasLastRender: state.hasLastRender,
            isRendering: state.isRendering,
            isUpdateInstallPending: state.isUpdateInstallPending
        )))
        updateStatusPresenter.apply(state)
    }

    private func refreshClipboardMenuState() {
        let state = Clipboard.menuState(includeLabel: false)
        clipboardContainsMarkdown = state.containsMarkdown
        statusMenuController?.updateClipboardPreview(state.preview)
        applyRenderState(renderCoordinator.state)
    }

    private func confirmClipboardOverwrite(_ action: ClipboardOverwriteAction) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text(
            "confirmation.clipboard_changed.title",
            defaultValue: "Clipboard Changed"
        )
        alert.informativeText = switch action {
        case .rerenderLastMarkdown:
            L10n.text(
                "confirmation.clipboard_changed.rerender",
                defaultValue: "Another app changed the clipboard. Replace it with a new PNG rendered from the last Markdown?"
            )
        case .restoreLastMarkdown:
            L10n.text(
                "confirmation.clipboard_changed.restore",
                defaultValue: "Another app changed the clipboard. Replace it with the last Markdown?"
            )
        }
        let primaryButtonTitle = switch action {
        case .rerenderLastMarkdown:
            L10n.text(
                "confirmation.render_and_replace",
                defaultValue: "Render and Replace"
            )
        case .restoreLastMarkdown:
            L10n.text(
                "common.replace",
                defaultValue: "Replace"
            )
        }
        let primaryButton = alert.addButton(withTitle: primaryButtonTitle)
        let cancelButton = alert.addButton(withTitle: L10n.text(
            "common.cancel",
            defaultValue: "Cancel"
        ))
        AlertKeyboard.configureDefaultAndCancel(
            in: alert,
            defaultButton: primaryButton,
            cancelButton: cancelButton
        )
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func show(_ notice: RenderCoordinatorNotice) {
        switch notice {
        case .imageCopied:
            hud.show(
                L10n.text(
                    "hud.png_copied",
                    defaultValue: "PNG copied — paste with Command-V"
                ),
                symbol: "checkmark.circle.fill"
            )
        case .markdownRestored:
            hud.show(
                L10n.text(
                    "hud.markdown_restored",
                    defaultValue: "Markdown restored — paste with Command-V"
                ),
                symbol: "doc.on.clipboard.fill"
            )
        case let .splitImagesSaved(count):
            let message = count == 1
                ? L10n.text(
                    "hud.split_png_saved",
                    defaultValue: "Saved 1 split PNG"
                )
                : L10n.format(
                    "hud.split_pngs_saved",
                    defaultValue: "Saved %ld split PNGs",
                    count
                )
            hud.show(
                message,
                symbol: "folder.badge.checkmark"
            )
        }
    }

    private func show(_ lastRender: LastRender) {
        previewController.show(
            image: lastRender.image,
            widthPreset: lastRender.widthPreset,
            markdown: lastRender.markdown
        )
    }

    private func showAbout() {
        aboutController.show()
    }

    private func showShortcutSettings() {
        sampleGuidePresenter.dismiss()
        shortcutSettingsController.show(
            configuration: globalShortcutConfiguration,
            failedRegistrationIDs: failedGlobalShortcutRegistrationIDs
        )
    }

    private func showWelcome() {
        welcomeController.show(shortcuts: welcomeShortcutStatuses)
    }

    private func performLaunchAtLoginAction() {
        do {
            let result = try launchAtLoginController.performPrimaryAction()
            updateLaunchAtLoginMenu()
            if result == .statusChanged(.requiresApproval) {
                hud.show(
                    L10n.text(
                        "hud.launch_at_login_requires_approval",
                        defaultValue: "Allow md2png in Login Items to finish setup"
                    ),
                    symbol: "gear.badge",
                    style: .informational
                )
            }
        } catch {
            updateLaunchAtLoginMenu()
            show(error)
        }
    }

    private func updateLaunchAtLoginMenu() {
        let presentation = launchAtLoginController.presentation
        statusMenuController?.applyLaunchAtLogin(presentation)
        if isWelcomeWindowVisible {
            welcomeController.refreshLaunchAtLogin()
        }
    }

    private func showSampleGuide() {
        guard !isSampleGuidePresentationScheduled else { return }
        isSampleGuidePresentationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSampleGuidePresentationScheduled = false
            self.presentSampleGuide()
        }
    }

    private func presentSampleGuide() {
        let renderState = renderCoordinator.state
        guard !renderState.isRendering,
              !renderState.isUpdateInstallPending,
              !renderState.isPresentingClipboardConfirmation,
              let button = statusMenuController?.button else {
            return
        }
        let clipboardState = Clipboard.menuState(includeLabel: false)
        let statusMenuPresentation = StatusMenuPresentation(state: StatusMenuState(
            clipboardContainsMarkdown: clipboardState.containsMarkdown,
            hasLastSource: renderState.hasLastSource,
            hasLastRender: renderState.hasLastRender,
            isRendering: false,
            isUpdateInstallPending: false
        ))
        sampleGuidePresenter.show(
            relativeTo: button,
            menuState: SampleGuideMenuState(
                statusMenuPresentation: statusMenuPresentation,
                launchAtLoginPresentation: launchAtLoginController.presentation
            )
        )
    }

    private func setPreviewWindowVisible(_ isVisible: Bool) {
        isPreviewWindowVisible = isVisible
        updateWindowedActivationPolicy()
    }

    private func setWelcomeWindowVisible(_ isVisible: Bool) {
        isWelcomeWindowVisible = isVisible
        updateWindowedActivationPolicy()
    }

    private func setShortcutSettingsWindowVisible(_ isVisible: Bool) {
        isShortcutSettingsWindowVisible = isVisible
        updateWindowedActivationPolicy()
    }

    private func updateWindowedActivationPolicy() {
        NSApp.setActivationPolicy(
            isPreviewWindowVisible
                || isWelcomeWindowVisible
                || isShortcutSettingsWindowVisible
                ? .regular
                : .accessory
        )
    }

#if DEBUG
    func prepareWelcomeSampleGuidePathForTesting() {
        configureStatusItem()
        isWelcomeWindowVisible = true
    }

    func triggerWelcomeSampleGuideForTesting() {
        welcomeController.trySampleForTesting()
    }

    var welcomeLaunchAtLoginRefreshCountForTesting: Int {
        welcomeController.launchAtLoginRefreshCountForTesting
    }

    func cleanUpWelcomeSampleGuidePathForTesting() {
        isWelcomeWindowVisible = false
        if let updateStatusObserverID {
            updateController.removeStatusObserver(updateStatusObserverID)
            self.updateStatusObserverID = nil
        }
        statusMenuController?.removeStatusItem()
        statusMenuController = nil
    }
#endif

    private func show(_ error: Error) {
        if let report = error as? RendererErrorReport {
            if rendererErrorDetailsPresenter.show(report) {
                hud.show(
                    L10n.text(
                        "renderer_error.details_copied",
                        defaultValue: "Error details copied"
                    ),
                    symbol: "doc.on.clipboard.fill",
                    style: .informational
                )
            }
            return
        }
        hud.show(
            error.localizedDescription,
            symbol: "exclamationmark.triangle.fill",
            style: .error
        )
    }

    private func announce(
        _ message: String,
        priority: NSAccessibilityPriorityLevel
    ) {
        guard let button = statusMenuController?.button else { return }
        NSAccessibility.post(
            element: button,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: priority.rawValue
            ]
        )
    }

    private func approveInstallAndRelaunch(_ update: SeamlessUpdate) -> Bool {
        guard renderCoordinator.canBeginUpdateInstall else {
            hud.show(
                L10n.text(
                    "update.finish_render_before_install",
                    defaultValue: "Finish the current render, then choose Install and Relaunch again."
                ),
                symbol: "hourglass",
                style: .error
            )
            return false
        }
        guard renderCoordinator.hasTransientContent else { return true }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.format(
            "update.confirm_relaunch_title",
            defaultValue: "Install md2png %@ and relaunch?",
            update.displayVersion
        )
        alert.informativeText = L10n.text(
            "update.confirm_relaunch_detail",
            defaultValue: "Relaunching clears Last Render and Last Markdown because they exist only in memory. Your clipboard will not be changed."
        )
        let installButton = alert.addButton(withTitle: L10n.text(
            "about.update_install_relaunch",
            defaultValue: "Install and Relaunch"
        ))
        let laterButton = alert.addButton(withTitle: L10n.text(
            "about.update_later",
            defaultValue: "Later"
        ))
        AlertKeyboard.configureDefaultAndCancel(
            in: alert,
            defaultButton: installButton,
            cancelButton: laterButton
        )
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func setUpdateInstallPending(_ isPending: Bool) {
        renderCoordinator.setUpdateInstallPending(isPending)
    }

}
