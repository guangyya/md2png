import AppKit

private enum ClipboardOverwriteAction {
    case rerenderLastMarkdown
    case restoreLastMarkdown
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let renderer = MarkdownRenderer()
    private let renderWidthPreference: RenderWidthPreference
    private let renderThemePreference: RenderThemePreference
    private let hud = HUDController()
    private lazy var previewController = PreviewController(
        onCopied: { [weak self] changeCount in
            guard let self else { return }
            self.lastSource.recordOwnedClipboardWrite(changeCount: changeCount)
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
        }
    )
    private lazy var updateController = UpdateController(
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
    private lazy var aboutController = AboutController(updateController: updateController)
    private let launchAtLoginController = LaunchAtLoginController()
    private let welcomePreference = WelcomePreference()
    private lazy var welcomeController = WelcomeController(
        preference: welcomePreference,
        launchAtLoginController: launchAtLoginController,
        onLaunchAtLoginError: { [weak self] error in
            self?.show(error)
        },
        onVisibilityChange: { [weak self] isVisible in
            self?.setWelcomeWindowVisible(isVisible)
        },
        onTrySample: { [weak self] in self?.showSampleGuide() }
    )
    private lazy var sampleGuideController = SampleGuideController(
        onChoose: { [weak self] kind in
            self?.renderBundledExample(kind)
        }
    )
    private lazy var globalShortcutRouter = GlobalShortcutRouter(
        verify: { [weak self] command in
            self?.welcomeController.verifyShortcut(command) ?? false
        },
        perform: { [weak self] command in
            guard let self else { return }
            switch command {
            case .render:
                self.renderClipboard()
            case .showLastRender:
                self.showLastRender()
            }
        }
    )
    private var statusItem: NSStatusItem!
    private var hotKey: GlobalHotKey?
    private var welcomeShortcutStatuses: [WelcomeShortcutStatus] = []
    private var lastImage: NSImage?
    private var lastRenderWidthPreset: RenderWidthPreset?
    private var lastSource = LastSourceState()
    private let clipboardPreviewView = ClipboardPreviewView()
    private var statusMenuItems: [StatusMenuCommand: NSMenuItem] = [:]
    private var renderMenuItem: NSMenuItem!
    private var rerenderLastMarkdownMenuItem: NSMenuItem!
    private var restoreLastMarkdownMenuItem: NSMenuItem!
    private var previewMenuItem: NSMenuItem!
    private var examplesMenuItem: NSMenuItem!
    private var renderWidthMenuItem: NSMenuItem!
    private var renderWidthMenuItems: [RenderWidthPreset: NSMenuItem] = [:]
    private var renderThemeMenuItem: NSMenuItem!
    private var renderThemeMenuItems: [RenderTheme: NSMenuItem] = [:]
    private var launchAtLoginMenuItem: NSMenuItem!
    private var renderWidthPreset: RenderWidthPreset
    private var renderTheme: RenderTheme
    private var renderActivity = RenderActivityState()
    private var clipboardContainsMarkdown = false
    private var isPresentingClipboardConfirmation = false
    private var isUpdateInstallPending = false
    private var isWaitingForUpdateDeferralBeforeTermination = false
    private var currentUpdateStatus = UpdateStatus()
    private var updateStatusObserverID: UUID?
    private var isPreviewWindowVisible = false
    private var isWelcomeWindowVisible = false
    private lazy var brandStatusImage = BrandIcon.statusBarImage()

    override init() {
        let renderWidthPreference = RenderWidthPreference()
        self.renderWidthPreference = renderWidthPreference
        renderWidthPreset = renderWidthPreference.selectedPreset
        let renderThemePreference = RenderThemePreference()
        self.renderThemePreference = renderThemePreference
        renderTheme = renderThemePreference.selectedTheme
        super.init()
    }

    private func setPreviewWindowVisible(_ isVisible: Bool) {
        isPreviewWindowVisible = isVisible
        updateWindowedActivationPolicy()
    }

    private func setWelcomeWindowVisible(_ isVisible: Bool) {
        isWelcomeWindowVisible = isVisible
        updateWindowedActivationPolicy()
    }

    private func updateWindowedActivationPolicy() {
        NSApp.setActivationPolicy(
            isPreviewWindowVisible || isWelcomeWindowVisible ? .regular : .accessory
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        presentRelaunchResultIfNeeded()
        let registrations: [GlobalHotKey.Registration] = [
            .render { [weak self] in self?.globalShortcutRouter.handle(.render) },
            .showLastRender { [weak self] in
                self?.globalShortcutRouter.handle(.showLastRender)
            }
        ]
        let hotKey = GlobalHotKey(registrations: registrations)
        self.hotKey = hotKey
        let failedRegistrationIDs = Set(hotKey.failedRegistrations.map(\.id))
        welcomeShortcutStatuses = registrations.map {
            WelcomeShortcutStatus(
                registration: $0,
                failedRegistrationIDs: failedRegistrationIDs
            )
        }

        if welcomePreference.shouldShowOnLaunch {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.welcomeController.showIfNeeded(
                    shortcuts: self.welcomeShortcutStatuses
                )
            }
        } else if !hotKey.failedRegistrations.isEmpty {
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
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard statusItem != nil else { return }
        updateLaunchAtLoginMenu()
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if isUpdateInstallPending {
            return .terminateNow
        }
        if isWaitingForUpdateDeferralBeforeTermination {
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
                    sender.reply(toApplicationShouldTerminate: true)
                }
            }
        if waitsForDeferral {
            return .terminateLater
        }
        isWaitingForUpdateDeferralBeforeTermination = false
        return .terminateNow
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = brandStatusImage
        statusItem.button?.setAccessibilityLabel(
            L10n.text("accessibility.app", defaultValue: "md2png")
        )

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let clipboardPreviewMenuItem = NSMenuItem()
        clipboardPreviewMenuItem.view = clipboardPreviewView
        menu.addItem(clipboardPreviewMenuItem)

        renderMenuItem = NSMenuItem(
            title: StatusMenuPresentation.title(for: .renderClipboard),
            action: #selector(renderClipboard),
            keyEquivalent: "x"
        )
        renderMenuItem.keyEquivalentModifierMask = [.command, .control]
        renderMenuItem.target = self

        previewMenuItem = NSMenuItem(
            title: StatusMenuPresentation.title(for: .showLastRender),
            action: #selector(showLastRender),
            keyEquivalent: "z"
        )
        previewMenuItem.keyEquivalentModifierMask = [.command, .control]
        previewMenuItem.target = self
        rerenderLastMarkdownMenuItem = NSMenuItem(
            title: StatusMenuPresentation.title(for: .rerenderLastMarkdown),
            action: #selector(rerenderLastMarkdown),
            keyEquivalent: ""
        )
        rerenderLastMarkdownMenuItem.target = self

        restoreLastMarkdownMenuItem = NSMenuItem(
            title: StatusMenuPresentation.title(for: .restoreLastMarkdown),
            action: #selector(restoreLastMarkdown),
            keyEquivalent: ""
        )
        restoreLastMarkdownMenuItem.target = self

        let renderWidthTitle = StatusMenuPresentation.title(for: .outputWidth)
        renderWidthMenuItem = NSMenuItem(
            title: renderWidthTitle,
            action: nil,
            keyEquivalent: ""
        )
        let renderWidthMenu = NSMenu(title: renderWidthTitle)
        for preset in RenderWidthPreset.allCases {
            let item = renderWidthMenu.addItem(
                withTitle: preset.menuTitle,
                action: #selector(selectRenderWidthPreset(_:)),
                keyEquivalent: ""
            )
            item.representedObject = preset.rawValue
            item.target = self
            renderWidthMenuItems[preset] = item
        }
        renderWidthMenuItem.submenu = renderWidthMenu
        updateRenderWidthMenuSelection()

        let renderThemeTitle = StatusMenuPresentation.title(for: .theme)
        renderThemeMenuItem = NSMenuItem(
            title: renderThemeTitle,
            action: nil,
            keyEquivalent: ""
        )
        let renderThemeMenu = NSMenu(title: renderThemeTitle)
        for theme in RenderTheme.allCases {
            let item = renderThemeMenu.addItem(
                withTitle: theme.menuTitle,
                action: #selector(selectRenderTheme(_:)),
                keyEquivalent: ""
            )
            item.representedObject = theme.rawValue
            item.target = self
            renderThemeMenuItems[theme] = item
        }
        renderThemeMenuItem.submenu = renderThemeMenu
        updateRenderThemeMenuSelection()

        let examplesTitle = StatusMenuPresentation.title(for: .examples)
        examplesMenuItem = NSMenuItem(title: examplesTitle, action: nil, keyEquivalent: "")
        let examplesMenu = NSMenu(title: examplesTitle)
        for kind in ExampleKind.allCases {
            if kind.startsMenuSection { examplesMenu.addItem(.separator()) }
            let item = examplesMenu.addItem(
                withTitle: kind.menuTitle,
                action: #selector(renderExample(_:)),
                keyEquivalent: ""
            )
            item.tag = kind.rawValue
            item.target = self
        }
        examplesMenuItem.submenu = examplesMenu

        launchAtLoginMenuItem = NSMenuItem(
            title: StatusMenuPresentation.title(for: .launchAtLogin),
            action: #selector(performLaunchAtLoginAction),
            keyEquivalent: ""
        )
        launchAtLoginMenuItem.target = self

        let welcomeItem = NSMenuItem(
            title: StatusMenuPresentation.title(for: .showWelcome),
            action: #selector(showWelcome),
            keyEquivalent: ""
        )
        welcomeItem.target = self

        let aboutItem = NSMenuItem(
            title: StatusMenuPresentation.title(for: .about),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self

        let quitItem = NSMenuItem(
            title: StatusMenuPresentation.title(for: .quit),
            action: #selector(terminateFromStatusMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self

        statusMenuItems = [
            .renderClipboard: renderMenuItem,
            .showLastRender: previewMenuItem,
            .rerenderLastMarkdown: rerenderLastMarkdownMenuItem,
            .restoreLastMarkdown: restoreLastMarkdownMenuItem,
            .theme: renderThemeMenuItem,
            .outputWidth: renderWidthMenuItem,
            .examples: examplesMenuItem,
            .launchAtLogin: launchAtLoginMenuItem,
            .showWelcome: welcomeItem,
            .about: aboutItem,
            .quit: quitItem
        ]
        for section in StatusMenuLayout.sections {
            menu.addItem(.separator())
            for command in section {
                guard let item = statusMenuItems[command] else { continue }
                item.identifier = NSUserInterfaceItemIdentifier(command.rawValue)
                menu.addItem(item)
            }
        }

        statusItem.menu = menu
        refreshClipboardMenuState()
        updateLaunchAtLoginMenu()

        updateStatusObserverID = updateController.observeStatus { [weak self] status in
            self?.applyUpdateStatus(status)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        sampleGuideController.dismiss()
        refreshClipboardMenuState()
        updateLaunchAtLoginMenu()
    }

    @objc private func renderClipboard() {
        guard !renderActivity.isRendering,
              !isUpdateInstallPending,
              !isPresentingClipboardConfirmation else { return }
        do {
            let markdown = try Clipboard.markdownText()
            render(markdown)
        } catch {
            show(error)
        }
    }

    @objc private func showLastRender() {
        guard let lastImage else { return }
        previewController.show(
            image: lastImage,
            widthPreset: lastRenderWidthPreset,
            markdown: lastSource.markdown
        )
    }

    @objc private func rerenderLastMarkdown() {
        guard !renderActivity.isRendering,
              !isUpdateInstallPending,
              !isPresentingClipboardConfirmation,
              let markdown = lastSource.markdown,
              confirmClipboardOverwriteIfNeeded(for: .rerenderLastMarkdown) else { return }
        render(markdown)
    }

    @objc private func restoreLastMarkdown() {
        guard !renderActivity.isRendering,
              !isUpdateInstallPending,
              !isPresentingClipboardConfirmation,
              let markdown = lastSource.markdown,
              confirmClipboardOverwriteIfNeeded(for: .restoreLastMarkdown) else { return }
        do {
            let changeCount = try Clipboard.write(markdown: markdown)
            lastSource.recordOwnedClipboardWrite(changeCount: changeCount)
            hud.show(
                L10n.text(
                    "hud.markdown_restored",
                    defaultValue: "Markdown restored — paste with Command-V"
                ),
                symbol: "doc.on.clipboard.fill"
            )
        } catch {
            show(error)
        }
    }

    @objc private func renderExample(_ sender: NSMenuItem) {
        guard let kind = ExampleKind(rawValue: sender.tag) else { return }
        renderBundledExample(kind)
    }

    private func renderBundledExample(_ kind: ExampleKind) {
        guard !renderActivity.isRendering,
              !isUpdateInstallPending,
              !isPresentingClipboardConfirmation else { return }
        do {
            let example = try AppResources.exampleMarkdown(for: kind)
            let changeCount = try Clipboard.write(markdown: example)
            lastSource.recordOwnedClipboardWrite(changeCount: changeCount)
            render(example, showsPreviewOnSuccess: true)
        } catch {
            show(error)
        }
    }

    @objc private func selectRenderWidthPreset(_ sender: NSMenuItem) {
        guard !renderActivity.isRendering,
              let rawValue = sender.representedObject as? String,
              let preset = RenderWidthPreset(rawValue: rawValue) else { return }
        renderWidthPreset = preset
        renderWidthPreference.select(preset)
        updateRenderWidthMenuSelection()
    }

    private func updateRenderWidthMenuSelection() {
        for (preset, item) in renderWidthMenuItems {
            item.state = preset == renderWidthPreset ? .on : .off
        }
    }

    @objc private func selectRenderTheme(_ sender: NSMenuItem) {
        guard !renderActivity.isRendering,
              let rawValue = sender.representedObject as? String,
              let theme = RenderTheme(rawValue: rawValue) else { return }
        renderTheme = theme
        renderThemePreference.select(theme)
        updateRenderThemeMenuSelection()
    }

    private func updateRenderThemeMenuSelection() {
        for (theme, item) in renderThemeMenuItems {
            item.state = theme == renderTheme ? .on : .off
        }
    }

    private func render(
        _ markdown: String,
        showsPreviewOnSuccess: Bool = false
    ) {
        guard !isUpdateInstallPending, renderActivity.begin() else { return }
        let requestedWidthPreset = renderWidthPreset
        let requestedTheme = renderTheme
        updateRenderingUI(isRendering: true)
        statusItem.button?.image = NSImage(
            systemSymbolName: "hourglass",
            accessibilityDescription: L10n.text(
                "accessibility.rendering",
                defaultValue: "Rendering"
            )
        )

        renderer.render(
            markdown,
            widthPreset: requestedWidthPreset,
            theme: requestedTheme
        ) { [weak self] result in
            guard let self else { return }
            defer {
                self.renderActivity.finish()
                self.updateRenderingUI(isRendering: false)
            }

            switch result {
            case let .success(image):
                do {
                    let changeCount = try Clipboard.write(image: image)
                    self.lastImage = image
                    self.lastRenderWidthPreset = requestedWidthPreset
                    self.lastSource.recordSuccessfulRender(
                        markdown: markdown,
                        clipboardChangeCount: changeCount
                    )
                    self.hud.show(
                        L10n.text(
                            "hud.png_copied",
                            defaultValue: "PNG copied — paste with Command-V"
                        ),
                        symbol: "checkmark.circle.fill"
                    )
                    if showsPreviewOnSuccess {
                        self.previewController.show(
                            image: image,
                            widthPreset: requestedWidthPreset,
                            markdown: markdown
                        )
                    }
                } catch {
                    self.show(error)
                }
            case let .failure(error):
                self.show(error)
            }
        }
    }

    private func updateRenderingUI(isRendering: Bool) {
        assert(isRendering == renderActivity.isRendering)
        applyStatusMenuPresentation()
        updateStatusItemAppearance()
    }

    private func refreshClipboardMenuState() {
        let state = Clipboard.menuState(includeLabel: false)
        clipboardContainsMarkdown = state.containsMarkdown
        clipboardPreviewView.update(state.preview)
        applyStatusMenuPresentation()
    }

    private func applyStatusMenuPresentation() {
        guard !statusMenuItems.isEmpty else { return }
        let presentation = StatusMenuPresentation(state: StatusMenuState(
            clipboardContainsMarkdown: clipboardContainsMarkdown,
            hasLastSource: lastSource.isAvailable,
            hasLastRender: lastImage != nil,
            isRendering: renderActivity.isRendering,
            isUpdateInstallPending: isUpdateInstallPending
        ))
        for (command, item) in statusMenuItems where command != .launchAtLogin {
            let itemPresentation = presentation[command]
            item.title = itemPresentation.title
            item.isEnabled = itemPresentation.isEnabled
        }
    }

    private func confirmClipboardOverwriteIfNeeded(
        for action: ClipboardOverwriteAction
    ) -> Bool {
        guard lastSource.requiresConfirmation(
            currentClipboardChangeCount: Clipboard.changeCount
        ) else {
            return true
        }
        guard !isPresentingClipboardConfirmation else { return false }
        isPresentingClipboardConfirmation = true
        defer { isPresentingClipboardConfirmation = false }

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
        alert.addButton(withTitle: primaryButtonTitle)
        let cancelButton = alert.addButton(withTitle: L10n.text(
            "common.cancel",
            defaultValue: "Cancel"
        ))
        cancelButton.keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func showAbout() {
        aboutController.show()
    }

    @objc private func showWelcome() {
        welcomeController.show(shortcuts: welcomeShortcutStatuses)
    }

    @objc private func performLaunchAtLoginAction() {
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
        launchAtLoginMenuItem.title = switch presentation.menuAction {
        case .enable:
            L10n.text(
                "menu.enable_launch_at_login",
                defaultValue: "Enable Launch at Login"
            )
        case .disable:
            L10n.text(
                "menu.disable_launch_at_login",
                defaultValue: "Disable Launch at Login"
            )
        case .allowInSystemSettings:
            L10n.text(
                "menu.allow_launch_at_login",
                defaultValue: "Allow Launch at Login…"
            )
        case .unavailable:
            L10n.text(
                "menu.launch_at_login_unavailable",
                defaultValue: "Launch at Login Unavailable"
            )
        }
        launchAtLoginMenuItem.badge = presentation.menuAction == .allowInSystemSettings
            ? NSMenuItemBadge(string: "!")
            : nil
        launchAtLoginMenuItem.toolTip = presentation.menuAction == .allowInSystemSettings
            ? L10n.text(
                "accessibility.launch_at_login_requires_approval",
                defaultValue: "Approval required in System Settings"
            )
            : nil
        launchAtLoginMenuItem.isEnabled = presentation.canPerformAction
        if isWelcomeWindowVisible {
            welcomeController.refreshLaunchAtLogin()
        }
    }

    private func showSampleGuide() {
        guard !renderActivity.isRendering,
              !isUpdateInstallPending,
              !isPresentingClipboardConfirmation,
              let button = statusItem.button else { return }
        refreshClipboardMenuState()
        updateLaunchAtLoginMenu()
        sampleGuideController.show(
            relativeTo: button,
            menuState: SampleGuideMenuState(
                canRestoreLastMarkdown: restoreLastMarkdownMenuItem.isEnabled,
                canShowLastRender: previewMenuItem.isEnabled,
                canRenderClipboard: renderMenuItem.isEnabled,
                canRerenderLastMarkdown: rerenderLastMarkdownMenuItem.isEnabled,
                launchAtLoginAction: launchAtLoginController.presentation.menuAction,
                canUseLaunchAtLogin: launchAtLoginMenuItem.isEnabled
            )
        )
    }

    @objc private func terminateFromStatusMenu() {
        NSApp.terminate(nil)
    }

    private func show(_ error: Error) {
        hud.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill", style: .error)
    }

    private func approveInstallAndRelaunch(_ update: SeamlessUpdate) -> Bool {
        guard !renderActivity.isRendering,
              !isUpdateInstallPending,
              !isPresentingClipboardConfirmation else {
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
        guard lastImage != nil || lastSource.isAvailable else { return true }

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
        alert.addButton(withTitle: L10n.text(
            "about.update_install_relaunch",
            defaultValue: "Install and Relaunch"
        ))
        alert.addButton(withTitle: L10n.text(
            "about.update_later",
            defaultValue: "Later"
        ))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func setUpdateInstallPending(_ isPending: Bool) {
        isUpdateInstallPending = isPending
        guard renderMenuItem != nil else { return }
        updateRenderingUI(isRendering: renderActivity.isRendering)
    }

    private func presentRelaunchResultIfNeeded() {
        let runningVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? ""
        guard let result = UpdateRelaunchMarker().reconcile(
            runningVersion: runningVersion
        ) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch result {
            case let .updated(version):
                self.hud.show(
                    L10n.format(
                        "update.updated_to_version",
                        defaultValue: "Updated to version %@",
                        version
                    ),
                    symbol: "checkmark.circle.fill"
                )
            case let .notUpdated(expectedVersion, runningVersion):
                self.hud.show(
                    L10n.format(
                        "update.relaunch_not_updated",
                        defaultValue: "Update to %1$@ did not complete — still running %2$@. Open About md2png to retry.",
                        expectedVersion,
                        runningVersion
                    ),
                    symbol: "exclamationmark.triangle.fill",
                    style: .error
                )
            }
        }
    }

    private func applyUpdateStatus(_ status: UpdateStatus) {
        let previousStatus = currentUpdateStatus
        currentUpdateStatus = status
        updateStatusItemAppearance()
        guard previousStatus.phase != status.phase else { return }
        presentUpdateTransition(from: previousStatus.phase, to: status.phase)
    }

    private func presentUpdateTransition(from previousPhase: UpdatePhase, to phase: UpdatePhase) {
        switch phase {
        case .unknown:
            break
        case let .upToDate(version):
            announceUpdate(L10n.format(
                "update.accessibility.up_to_date",
                defaultValue: "md2png %@ is up to date.",
                version.description
            ))
        case .runningNewerVersion:
            announceUpdate(L10n.text(
                "update.accessibility.running_newer",
                defaultValue: "This md2png build is newer than the latest published version."
            ))
        case let .sparkleUpdateAvailable(update):
            announceUpdate(L10n.format(
                "update.accessibility.available",
                defaultValue: "md2png %@ is available.",
                update.displayVersion
            ))
        case let .sparkleDownloading(update, _):
            if case .sparkleDownloading = previousPhase { return }
            announceUpdate(L10n.format(
                "update.accessibility.downloading",
                defaultValue: "Downloading md2png %@.",
                update.displayVersion
            ))
        case let .sparkleExtracting(update, _):
            announceUpdate(L10n.format(
                "update.accessibility.preparing",
                defaultValue: "Preparing md2png %@ for installation.",
                update.displayVersion
            ))
        case let .sparkleReadyToInstall(update):
            let message = L10n.format(
                "update.accessibility.ready_to_relaunch",
                defaultValue: "md2png %@ is ready to install and relaunch.",
                update.displayVersion
            )
            if aboutController.window?.isVisible != true {
                hud.show(message, symbol: "arrow.down.app.fill")
            }
            announceUpdate(message)
        case let .sparkleInstalling(update):
            announceUpdate(L10n.format(
                "update.accessibility.installing",
                defaultValue: "Installing md2png %@ and relaunching.",
                update.displayVersion
            ))
        case let .sparkleFailed(message, _):
            if previousPhase.isDownloadActive,
               aboutController.window?.isVisible != true {
                let recoveryMessage = L10n.format(
                    "update.hud.failed",
                    defaultValue: "%@ Open About md2png to retry.",
                    message
                )
                hud.show(
                    recoveryMessage,
                    symbol: "exclamationmark.triangle.fill",
                    style: .error
                )
            }
            announceUpdate(message)
        case let .updateAvailable(update):
            if previousPhase.isDownloadActive {
                let message = L10n.text(
                    "update.accessibility.cancelled",
                    defaultValue: "Update cancelled"
                )
                if aboutController.window?.isVisible != true {
                    hud.show(message, symbol: "xmark.circle.fill")
                }
                announceUpdate(message)
            } else {
                announceUpdate(L10n.format(
                    "update.accessibility.available",
                    defaultValue: "md2png %@ is available.",
                    update.version.description
                ))
            }
        case let .downloading(update, _):
            if case .downloading = previousPhase { return }
            announceUpdate(L10n.format(
                "update.accessibility.downloading",
                defaultValue: "Downloading md2png %@.",
                update.version.description
            ))
        case let .verifying(update):
            announceUpdate(L10n.format(
                "update.accessibility.verifying",
                defaultValue: "Verifying md2png %@.",
                update.version.description
            ))
        case let .opening(update):
            announceUpdate(L10n.format(
                "update.accessibility.opening",
                defaultValue: "Opening md2png %@.",
                update.version.description
            ))
        case let .readyToInstall(update, _):
            let message = L10n.format(
                "update.accessibility.ready",
                defaultValue: "md2png %@ DMG opened — drag it into Applications",
                update.version.description
            )
            if aboutController.window?.isVisible != true {
                hud.show(message, symbol: "arrow.down.app.fill")
            }
            announceUpdate(message)
        case let .failed(message, _, _, _):
            if previousPhase.isDownloadActive,
               aboutController.window?.isVisible != true {
                let recoveryMessage = L10n.format(
                    "update.hud.failed",
                    defaultValue: "%@ Open About md2png to retry.",
                    message
                )
                hud.show(
                    recoveryMessage,
                    symbol: "exclamationmark.triangle.fill",
                    style: .error
                )
            }
            announceUpdate(message)
        }
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }
        if renderActivity.isRendering {
            button.image = NSImage(
                systemSymbolName: "hourglass",
                accessibilityDescription: nil
            )
            button.setAccessibilityLabel(L10n.text(
                "accessibility.rendering",
                defaultValue: "Rendering"
            ))
            return
        }
        if isUpdateInstallPending {
            button.image = NSImage(
                systemSymbolName: "arrow.triangle.2.circlepath",
                accessibilityDescription: nil
            )
            button.setAccessibilityLabel(L10n.text(
                "update.install_pending_accessibility",
                defaultValue: "md2png — update installation is starting"
            ))
            return
        }

        let symbolName: String?
        switch currentUpdateStatus.phase {
        case .sparkleDownloading, .downloading:
            symbolName = "arrow.down.circle"
        case .sparkleExtracting, .verifying:
            symbolName = "checkmark.shield"
        case .sparkleInstalling:
            symbolName = "arrow.triangle.2.circlepath"
        case .opening:
            symbolName = "opticaldiscdrive"
        case .unknown, .upToDate, .runningNewerVersion,
             .sparkleUpdateAvailable, .sparkleReadyToInstall, .sparkleFailed,
             .updateAvailable, .readyToInstall, .failed:
            symbolName = nil
        }

        if let symbolName,
           let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            image.isTemplate = true
            button.image = image
            button.setAccessibilityLabel(L10n.format(
                "accessibility.update_status",
                defaultValue: "md2png — %@",
                updateAccessibilityStatus
            ))
        } else {
            button.image = brandStatusImage
            button.setAccessibilityLabel(L10n.text(
                "accessibility.app",
                defaultValue: "md2png"
            ))
        }
    }

    private var updateAccessibilityStatus: String {
        switch currentUpdateStatus.phase {
        case let .sparkleDownloading(update, progressPercent):
            if let progressPercent {
                return L10n.format(
                    "about.update_downloading_progress",
                    defaultValue: "Downloading md2png %1$@ — %2$ld%%",
                    update.displayVersion,
                    progressPercent
                )
            }
            return L10n.format(
                "about.update_downloading_version",
                defaultValue: "Downloading md2png %@…",
                update.displayVersion
            )
        case let .sparkleExtracting(update, progressPercent):
            if let progressPercent {
                return L10n.format(
                    "about.update_preparing_progress",
                    defaultValue: "Preparing md2png %1$@ — %2$ld%%",
                    update.displayVersion,
                    progressPercent
                )
            }
            return L10n.format(
                "about.update_preparing_version",
                defaultValue: "Preparing md2png %@…",
                update.displayVersion
            )
        case let .sparkleInstalling(update):
            return L10n.format(
                "about.update_installing_version",
                defaultValue: "Installing md2png %@…",
                update.displayVersion
            )
        case let .downloading(update, progressPercent):
            return L10n.format(
                "about.update_downloading_progress",
                defaultValue: "Downloading md2png %1$@ — %2$ld%%",
                update.version.description,
                progressPercent
            )
        case let .verifying(update):
            return L10n.format(
                "about.update_verifying_version",
                defaultValue: "Verifying md2png %@…",
                update.version.description
            )
        case let .opening(update):
            return L10n.format(
                "about.update_opening_version",
                defaultValue: "Opening md2png %@…",
                update.version.description
            )
        case .unknown, .upToDate, .runningNewerVersion,
             .sparkleUpdateAvailable, .sparkleReadyToInstall, .sparkleFailed,
             .updateAvailable, .readyToInstall, .failed:
            return L10n.text("accessibility.app", defaultValue: "md2png")
        }
    }

    private func announceUpdate(_ message: String) {
        guard let button = statusItem.button else { return }
        NSAccessibility.post(
            element: button,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }
}

struct RenderActivityState {
    private(set) var isRendering = false

    mutating func begin() -> Bool {
        guard !isRendering else { return false }
        isRendering = true
        return true
    }

    mutating func finish() {
        isRendering = false
    }
}
