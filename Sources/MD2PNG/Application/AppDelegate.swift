import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let diagnosticLogger: DiagnosticLogger
    private let splitImageExportCompletionPresenter = SplitImageExportCompletionPresenter()
    private lazy var hud = HUDController(announce: { [weak self] message, priority in
        self?.announce(message, priority: priority)
    })
    private let rendererErrorDetailsPresenter = RendererErrorDetailsPresenter()
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
    private let launchAtLoginController = LaunchAtLoginController()
    private let welcomePreference = WelcomePreference()
    private let globalShortcutPreference: GlobalShortcutPreference
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
    private lazy var globalShortcutCoordinator = GlobalShortcutCoordinator(
        preference: globalShortcutPreference,
        diagnosticLogger: diagnosticLogger,
        verify: { [weak self] command in
            self?.verifyGlobalShortcut(command) ?? false
        },
        perform: { [weak self] command in
            self?.performGlobalShortcut(command)
        },
        onStateChange: { [weak self] state in
            self?.applyGlobalShortcutState(state)
        }
    )
    private lazy var windowPresentationCoordinator = WindowPresentationCoordinator(
        updateController: updateController,
        diagnosticLogger: diagnosticLogger,
        launchAtLoginController: launchAtLoginController,
        welcomePreference: welcomePreference,
        globalShortcutPreference: globalShortcutPreference,
        shortcutState: { [weak self] in
            self?.currentShortcutWindowState() ?? .init(
                configuration: .default,
                failedRegistrationIDs: []
            )
        },
        actions: WindowPresentationCoordinator.Actions(
            previewCopied: { [weak self] changeCount in
                self?.previewDidCopy(changeCount: changeCount)
            },
            showError: { [weak self] error in
                self?.show(error)
            },
            applyShortcuts: { [weak self] configuration in
                self?.applyGlobalShortcuts(configuration) ?? []
            },
            suspendShortcuts: { [weak self] in
                self?.suspendGlobalShortcuts()
            },
            restoreShortcuts: { [weak self] in
                self?.restoreGlobalShortcuts()
            },
            trySample: { [weak self] in
                self?.showSampleGuide()
            },
            dismissTransientPresentation: { [weak self] in
                self?.sampleGuidePresenter.dismiss()
            }
        )
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
            self?.showPreview(lastRender)
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
            self?.isAboutVisible() == true
        },
        announce: { [weak self] message in
            self?.announce(message, priority: .medium)
        }
    )

    private var statusMenuController: StatusMenuController?
    private var clipboardContainsMarkdown = false
    private var isSampleGuidePresentationScheduled = false
    private var isWaitingForUpdateDeferralBeforeTermination = false
    private var updateStatusObserverID: UUID?

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

    private func verifyGlobalShortcut(_ command: GlobalShortcutCommand) -> Bool {
        windowPresentationCoordinator.verifyShortcut(command)
    }

    private func performGlobalShortcut(_ command: GlobalShortcutCommand) {
        switch command {
        case .render:
            renderCoordinator.renderClipboard()
        case .showLastRender:
            renderCoordinator.showLastRender()
        }
    }

    private func applyGlobalShortcutState(_ state: GlobalShortcutCoordinator.State) {
        statusMenuController?.applyShortcuts(state.configuration)
        windowPresentationCoordinator.refreshWelcomeShortcutsIfVisible(
            state.welcomeShortcuts
        )
    }

    private func currentShortcutWindowState() -> WindowPresentationCoordinator.ShortcutState {
        WindowPresentationCoordinator.ShortcutState(
            configuration: globalShortcutCoordinator.configuration,
            failedRegistrationIDs: globalShortcutCoordinator.failedRegistrationIDs
        )
    }

    private func applyGlobalShortcuts(
        _ configuration: GlobalShortcutConfiguration
    ) -> Set<UInt32> {
        globalShortcutCoordinator.apply(configuration)
    }

    private func suspendGlobalShortcuts() {
        globalShortcutCoordinator.suspendForRecording()
    }

    private func restoreGlobalShortcuts() {
        globalShortcutCoordinator.restoreAfterCancelledRecording()
    }

    private func previewDidCopy(changeCount: Int) {
        renderCoordinator.recordOwnedClipboardWrite(changeCount: changeCount)
        hud.show(
            L10n.text(
                "hud.png_copied_again",
                defaultValue: "PNG copied again — paste with Command-V"
            ),
            symbol: "doc.on.clipboard.fill",
            accessibilityAnnouncement: L10n.text(
                "hud.png_copied_again_accessibility",
                defaultValue: "PNG copied again and ready to paste with Command-V"
            )
        )
    }

    private func showPreview(_ lastRender: LastRender) {
        windowPresentationCoordinator.showPreview(lastRender)
    }

    private func isAboutVisible() -> Bool {
        windowPresentationCoordinator.isVisible(.about)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        diagnosticLogger.record(
            category: .appLifecycle,
            stage: .applicationLaunch,
            result: .started
        )
        windowPresentationCoordinator.prepareForApplicationLaunch()
        configureStatusItem()
        updateStatusPresenter.presentRelaunchResultIfNeeded()

        let failedRegistrationIDs = globalShortcutCoordinator.start()

        if welcomePreference.shouldShowOnLaunch {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.windowPresentationCoordinator.showWelcomeIfNeeded(
                    shortcuts: self.globalShortcutCoordinator.welcomeShortcuts
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

    func applicationDidBecomeActive(_ notification: Notification) {
        diagnosticLogger.record(
            category: .appLifecycle,
            stage: .applicationActive,
            result: .succeeded,
            level: .verbose
        )
        windowPresentationCoordinator.refreshLaunchAtLoginIfVisible()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowPresentationCoordinator.prepareForApplicationTermination()
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
            shortcutConfiguration: globalShortcutCoordinator.configuration,
            actions: StatusMenuController.Actions(
                menuWillOpen: { [weak self] in self?.statusMenuWillOpen() },
                renderClipboard: { [weak self] in
                    self?.renderCoordinator.renderClipboard()
                },
                renderMarkdownFile: { [weak self] in
                    self?.renderMarkdownFile()
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
                showSettings: { [weak self] in
                    self?.windowPresentationCoordinator.showSettings()
                },
                showWelcome: { [weak self] in
                    guard let self else { return }
                    self.windowPresentationCoordinator.showWelcome(
                        shortcuts: self.globalShortcutCoordinator.welcomeShortcuts
                    )
                },
                showAbout: { [weak self] in
                    self?.windowPresentationCoordinator.showAbout()
                },
                quit: { NSApp.terminate(nil) }
            )
        )
        statusMenuController = controller
        refreshClipboardMenuState()
        applyRenderState(renderState)

        updateStatusObserverID = updateController.observeStatus { [weak self] status in
            self?.updateStatusPresenter.apply(status)
        }
    }

    private func statusMenuWillOpen() {
        sampleGuidePresenter.dismiss()
        refreshClipboardMenuState()
    }

    private func renderMarkdownFile() {
        guard renderCoordinator.canStartRenderAction,
              let fileURL = MarkdownFilePicker.choose() else {
            return
        }
        do {
            let markdown = try MarkdownFileInput.load(from: fileURL)
            renderCoordinator.renderMarkdownFile(markdown)
        } catch {
            show(error)
        }
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
                symbol: "checkmark.circle.fill",
                accessibilityAnnouncement: L10n.text(
                    "hud.png_copied_accessibility",
                    defaultValue: "PNG copied and ready to paste with Command-V"
                )
            )
        case .markdownRestored:
            hud.show(
                L10n.text(
                    "hud.markdown_restored",
                    defaultValue: "Markdown restored — paste with Command-V"
                ),
                symbol: "doc.on.clipboard.fill",
                accessibilityAnnouncement: L10n.text(
                    "hud.markdown_restored_accessibility",
                    defaultValue: "Markdown restored and ready to paste with Command-V"
                )
            )
        case let .splitImagesSaved(count, directoryURL):
            splitImageExportCompletionPresenter.show(
                count: count,
                directoryURL: directoryURL
            )
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
                statusMenuPresentation: statusMenuPresentation
            )
        )
    }

#if DEBUG
    func prepareWelcomeSampleGuidePathForTesting() {
        configureStatusItem()
        windowPresentationCoordinator.setVisibleForTesting(true, surface: .welcome)
    }

    func triggerWelcomeSampleGuideForTesting() {
        windowPresentationCoordinator.triggerWelcomeSampleGuideForTesting()
    }

    func cleanUpWelcomeSampleGuidePathForTesting() {
        windowPresentationCoordinator.setVisibleForTesting(false, surface: .welcome)
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
            switch rendererErrorDetailsPresenter.show(report) {
            case .detailsCopied:
                hud.show(
                    L10n.text(
                        "renderer_error.details_copied",
                        defaultValue: "Error details copied"
                    ),
                    symbol: "doc.on.clipboard.fill",
                    style: .informational
                )
            case .splitExportRequested:
                renderCoordinator.saveFailedRenderAsSplitPNGs()
            case .dismissed:
                break
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
