import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let renderer = MarkdownRenderer()
    private let renderWidthPreference: RenderWidthPreference
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
    private let updateController = UpdateController()
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
    private var renderMenuItem: NSMenuItem!
    private var restoreLastMarkdownMenuItem: NSMenuItem!
    private var previewMenuItem: NSMenuItem!
    private var examplesMenuItem: NSMenuItem!
    private var renderWidthMenuItem: NSMenuItem!
    private var renderWidthMenuItems: [RenderWidthPreset: NSMenuItem] = [:]
    private var launchAtLoginMenuItem: NSMenuItem!
    private var renderWidthPreset: RenderWidthPreset
    private var renderActivity = RenderActivityState()
    private var isPresentingClipboardConfirmation = false
    private var currentUpdateStatus = UpdateStatus()
    private var updateStatusObserverID: UUID?
    private var isPreviewWindowVisible = false
    private var isWelcomeWindowVisible = false
    private lazy var brandStatusImage = BrandIcon.statusBarImage()

    override init() {
        let renderWidthPreference = RenderWidthPreference()
        self.renderWidthPreference = renderWidthPreference
        renderWidthPreset = renderWidthPreference.selectedPreset
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

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = brandStatusImage
        statusItem.button?.setAccessibilityLabel(
            L10n.text("accessibility.app", defaultValue: "md2png")
        )

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        clipboardPreviewView.update(Clipboard.menuPreview(includeLabel: false))
        let clipboardPreviewMenuItem = NSMenuItem()
        clipboardPreviewMenuItem.view = clipboardPreviewView
        menu.addItem(clipboardPreviewMenuItem)
        menu.addItem(.separator())

        renderMenuItem = menu.addItem(
            withTitle: L10n.text(
                "menu.render",
                defaultValue: "Render Clipboard as Image"
            ),
            action: #selector(renderClipboard),
            keyEquivalent: "x"
        )
        renderMenuItem.keyEquivalentModifierMask = [.command, .control]
        renderMenuItem.target = self

        restoreLastMarkdownMenuItem = menu.addItem(
            withTitle: L10n.text(
                "menu.restore_last_markdown",
                defaultValue: "Restore Last Markdown"
            ),
            action: #selector(restoreLastMarkdown),
            keyEquivalent: ""
        )
        restoreLastMarkdownMenuItem.target = self
        restoreLastMarkdownMenuItem.isEnabled = false

        previewMenuItem = menu.addItem(
            withTitle: L10n.text("menu.show_last_render", defaultValue: "Show Last Render"),
            action: #selector(showLastRender),
            keyEquivalent: "z"
        )
        previewMenuItem.keyEquivalentModifierMask = [.command, .control]
        previewMenuItem.target = self
        previewMenuItem.isEnabled = false

        menu.addItem(.separator())
        let renderWidthTitle = L10n.text(
            "menu.render_width",
            defaultValue: "Output Width"
        )
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
        menu.addItem(renderWidthMenuItem)

        let examplesTitle = L10n.text("menu.examples", defaultValue: "Examples")
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
        menu.addItem(examplesMenuItem)

        menu.addItem(.separator())
        launchAtLoginMenuItem = menu.addItem(
            withTitle: L10n.text(
                "menu.enable_launch_at_login",
                defaultValue: "Enable Launch at Login"
            ),
            action: #selector(performLaunchAtLoginAction),
            keyEquivalent: ""
        )
        launchAtLoginMenuItem.target = self
        updateLaunchAtLoginMenu()

        menu.addItem(.separator())
        let welcomeItem = menu.addItem(
            withTitle: L10n.text("menu.show_welcome", defaultValue: "Show Welcome"),
            action: #selector(showWelcome),
            keyEquivalent: ""
        )
        welcomeItem.target = self

        let aboutItem = menu.addItem(
            withTitle: L10n.text("menu.about", defaultValue: "About md2png"),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self

        menu.addItem(.separator())
        let quitItem = menu.addItem(
            withTitle: L10n.text("menu.quit", defaultValue: "Quit md2png"),
            action: #selector(terminateFromStatusMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        statusItem.menu = menu

        updateStatusObserverID = updateController.observeStatus { [weak self] status in
            self?.applyUpdateStatus(status)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        sampleGuideController.dismiss()
        clipboardPreviewView.update(Clipboard.menuPreview(includeLabel: false))
        updateLaunchAtLoginMenu()
    }

    @objc private func renderClipboard() {
        guard !renderActivity.isRendering,
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

    @objc private func restoreLastMarkdown() {
        guard !renderActivity.isRendering,
              !isPresentingClipboardConfirmation,
              let markdown = lastSource.markdown,
              confirmClipboardOverwriteIfNeeded() else { return }
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

    private func render(
        _ markdown: String,
        showsPreviewOnSuccess: Bool = false
    ) {
        guard renderActivity.begin() else { return }
        let requestedWidthPreset = renderWidthPreset
        updateRenderingUI(isRendering: true)
        statusItem.button?.image = NSImage(
            systemSymbolName: "hourglass",
            accessibilityDescription: L10n.text(
                "accessibility.rendering",
                defaultValue: "Rendering"
            )
        )

        renderer.render(markdown, widthPreset: requestedWidthPreset) { [weak self] result in
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
                    self.previewMenuItem.isEnabled = true
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
        renderMenuItem.isEnabled = !isRendering
        renderMenuItem.title = isRendering
            ? L10n.text("menu.rendering", defaultValue: "Rendering…")
            : L10n.text("menu.render", defaultValue: "Render Clipboard as Image")
        examplesMenuItem.isEnabled = !isRendering
        renderWidthMenuItem.isEnabled = !isRendering
        updateLastSourceActionAvailability()
        updateStatusItemAppearance()
    }

    private func updateLastSourceActionAvailability() {
        let isEnabled = lastSource.isAvailable && !renderActivity.isRendering
        restoreLastMarkdownMenuItem.isEnabled = isEnabled
    }

    private func confirmClipboardOverwriteIfNeeded() -> Bool {
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
        alert.informativeText = L10n.text(
            "confirmation.clipboard_changed.restore",
            defaultValue: "Another app changed the clipboard. Replace it with the last Markdown?"
        )
        alert.addButton(withTitle: L10n.text(
            "common.replace",
            defaultValue: "Replace"
        ))
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
              !isPresentingClipboardConfirmation,
              let button = statusItem.button else { return }
        sampleGuideController.show(
            relativeTo: button,
            menuState: SampleGuideMenuState(
                canRestoreLastMarkdown: restoreLastMarkdownMenuItem.isEnabled,
                canShowLastRender: previewMenuItem.isEnabled
            )
        )
    }

    @objc private func terminateFromStatusMenu() {
        NSApp.terminate(nil)
    }

    private func show(_ error: Error) {
        hud.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill", style: .error)
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

        let symbolName: String?
        switch currentUpdateStatus.phase {
        case .downloading:
            symbolName = "arrow.down.circle"
        case .verifying:
            symbolName = "checkmark.shield"
        case .opening:
            symbolName = "opticaldiscdrive"
        case .unknown, .upToDate, .updateAvailable, .readyToInstall, .failed:
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
        case let .downloading(update, progressPercent):
            return L10n.format(
                "about.update_downloading_progress",
                defaultValue: "Downloading md2png %@ — %ld%%",
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
        case .unknown, .upToDate, .updateAvailable, .readyToInstall, .failed:
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
