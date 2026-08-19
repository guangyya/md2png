import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let diagnosticLogger: DiagnosticLogger
    private lazy var updateController: UpdateController = UpdateController(
        diagnosticLogger: diagnosticLogger,
        updateDriver: SparkleUpdateDriver {
            UpdateChannel.current().repository?.appcastURL
        },
        beforeInstallAndRelaunch: { [weak self] update in
            guard let self else { return false }
            return self.feedbackPresenter.approveInstallAndRelaunch(
                update,
                canBeginUpdateInstall: self.renderCoordinator.canBeginUpdateInstall,
                hasTransientContent: self.renderCoordinator.hasTransientContent
            )
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
    private lazy var feedbackPresenter: ApplicationFeedbackPresenter =
        ApplicationFeedbackPresenter(
            actions: ApplicationFeedbackPresenter.Actions(
                statusItemButton: { [weak self] in
                    self?.menuCoordinator.button
                },
                saveFailedRenderAsSplitPNGs: { [weak self] in
                    self?.renderCoordinator.saveFailedRenderAsSplitPNGs()
                }
            )
        )
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
    private lazy var globalShortcutCoordinator: GlobalShortcutCoordinator =
        GlobalShortcutCoordinator(
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
    private lazy var windowPresentationCoordinator: WindowPresentationCoordinator =
        WindowPresentationCoordinator(
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
                    self?.feedbackPresenter.show(error)
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
    private lazy var renderCoordinator: RenderCoordinator =
        RenderCoordinator(
            diagnosticLogger: diagnosticLogger,
            confirmClipboardOverwrite: { [weak self] action in
                self?.feedbackPresenter.confirmClipboardOverwrite(action) ?? false
            },
            onStateChange: { [weak self] state in
                self?.applyRenderState(state)
            },
            onNotice: { [weak self] notice in
                self?.feedbackPresenter.show(notice)
            },
            onError: { [weak self] error in
                self?.feedbackPresenter.show(error)
            },
            onPreviewRequested: { [weak self] lastRender in
                self?.showPreview(lastRender)
            }
        )
    private lazy var updateStatusPresenter: UpdateStatusPresenter =
        UpdateStatusPresenter(
            showHUD: { [weak self] message, symbol, style in
                self?.feedbackPresenter.showHUD(
                    message,
                    symbol: symbol,
                    style: style
                )
            },
            applyStatusItem: { [weak self] presentation in
                self?.menuCoordinator.applyStatusItem(presentation)
            },
            isAboutVisible: { [weak self] in
                self?.isAboutVisible() == true
            },
            announce: { [weak self] message in
                self?.feedbackPresenter.announce(message, priority: .medium)
            }
        )
    private lazy var menuCoordinator: ApplicationMenuCoordinator =
        ApplicationMenuCoordinator(
            updateController: updateController,
            updateStatusPresenter: updateStatusPresenter,
            currentRenderState: { [weak self] in
                self?.renderCoordinator.state ?? RenderCoordinatorState(
                    isRendering: false,
                    hasLastSource: false,
                    hasLastRender: false,
                    isUpdateInstallPending: false,
                    isPresentingClipboardConfirmation: false,
                    selectedWidthPreset: .standard,
                    selectedTheme: .cleanLight
                )
            },
            currentShortcutConfiguration: { [weak self] in
                self?.globalShortcutCoordinator.configuration ?? .default
            },
            actions: ApplicationMenuCoordinator.Actions(
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
                dismissTransientPresentation: { [weak self] in
                    self?.sampleGuidePresenter.dismiss()
                },
                quit: { NSApp.terminate(nil) }
            )
        )
    private lazy var terminationCoordinator: ApplicationTerminationCoordinator =
        ApplicationTerminationCoordinator(
            dependencies: ApplicationTerminationCoordinator.Dependencies(
                isUpdateInstallPending: { [weak self] in
                    self?.renderCoordinator.isUpdateInstallPending == true
                },
                cancelPreparedInstallation: { [weak self] completion in
                    self?.updateController
                        .cancelPreparedInstallationForApplicationTermination(
                            completion: completion
                        ) ?? false
                }
            ),
            diagnosticLogger: diagnosticLogger
        )
    private lazy var markdownFileServiceProvider: MarkdownFileServiceProvider =
        MarkdownFileServiceProvider(
            onOpen: { [weak self] urls in
                self?.receiveMarkdownFileOpenRequest(urls)
            }
        )

    private var isSampleGuidePresentationScheduled = false
    private var isReadyForFileOpen = false
    private var hasReceivedFileOpenRequest = false
    private var deferredFileOpenRequests: [[URL]] = []

#if DEBUG
    var clipboardMenuRefreshCountForTesting: Int {
        menuCoordinator.clipboardPreviewUpdateCountForTesting
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
        menuCoordinator.applyShortcuts(state.configuration)
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
        feedbackPresenter.showPreviewCopied()
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
        NSApp.servicesProvider = markdownFileServiceProvider
        menuCoordinator.configure()
        updateStatusPresenter.presentRelaunchResultIfNeeded()

        let failedRegistrationIDs = globalShortcutCoordinator.start()

        if welcomePreference.shouldShowOnLaunch && !hasReceivedFileOpenRequest {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !self.hasReceivedFileOpenRequest else { return }
                self.windowPresentationCoordinator.showWelcomeIfNeeded(
                    shortcuts: self.globalShortcutCoordinator.welcomeShortcuts
                )
            }
        } else if !failedRegistrationIDs.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.feedbackPresenter.showShortcutConflict()
            }
        }
        diagnosticLogger.record(
            category: .appLifecycle,
            stage: .applicationLaunch,
            result: .succeeded
        )

        isReadyForFileOpen = true
        let requests = deferredFileOpenRequests
        deferredFileOpenRequests.removeAll()
        for request in requests {
            openMarkdownFiles(request)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receiveMarkdownFileOpenRequest(urls)
    }

    private func receiveMarkdownFileOpenRequest(_ urls: [URL]) {
        hasReceivedFileOpenRequest = true
        guard isReadyForFileOpen else {
            deferredFileOpenRequests.append(urls)
            return
        }
        openMarkdownFiles(urls)
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
        terminationCoordinator.shouldTerminate {
            sender.reply(toApplicationShouldTerminate: true)
        }
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
            feedbackPresenter.show(error)
        }
    }

    private func openMarkdownFiles(_ urls: [URL]) {
        do {
            let fileURL = try MarkdownFileOpenRequest.singleFileURL(from: urls)
            guard renderCoordinator.canStartRenderAction else {
                throw AppError.markdownFileOpenBusy
            }
            let markdown = try MarkdownFileInput.load(from: fileURL)
            renderCoordinator.previewMarkdownFile(markdown)
        } catch {
            feedbackPresenter.show(error)
        }
    }

    private func applyRenderState(_ state: RenderCoordinatorState) {
        menuCoordinator.apply(state)
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
              let button = menuCoordinator.button else {
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
        menuCoordinator.configure()
        windowPresentationCoordinator.setVisibleForTesting(true, surface: .welcome)
    }

    func triggerWelcomeSampleGuideForTesting() {
        windowPresentationCoordinator.triggerWelcomeSampleGuideForTesting()
    }

    func cleanUpWelcomeSampleGuidePathForTesting() {
        windowPresentationCoordinator.setVisibleForTesting(false, surface: .welcome)
        menuCoordinator.tearDown()
    }
#endif

    private func setUpdateInstallPending(_ isPending: Bool) {
        renderCoordinator.setUpdateInstallPending(isPending)
    }

}
