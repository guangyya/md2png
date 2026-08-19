import AppKit

struct StatusItemPresentation: Equatable {
    let symbolName: String?
    let accessibilityLabel: String
}

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    struct Actions {
        let menuWillOpen: () -> Void
        let renderClipboard: () -> Void
        let renderMarkdownFile: () -> Void
        let showLastRender: () -> Void
        let rerenderLastMarkdown: () -> Void
        let restoreLastMarkdown: () -> Void
        let renderExample: (ExampleKind) -> Void
        let selectWidthPreset: (RenderWidthPreset) -> Void
        let selectTheme: (RenderTheme) -> Void
        let showSettings: () -> Void
        let showWelcome: () -> Void
        let showAbout: () -> Void
        let quit: () -> Void
    }

    private let actions: Actions
    private let statusItem: NSStatusItem
    private let clipboardPreviewView = ClipboardPreviewView()
    private var statusMenuItems: [StatusMenuCommand: NSMenuItem] = [:]
    private var widthMenuItems: [RenderWidthPreset: NSMenuItem] = [:]
    private var themeMenuItems: [RenderTheme: NSMenuItem] = [:]
    private lazy var brandStatusImage = BrandIcon.statusBarImage()

#if DEBUG
    private(set) var clipboardPreviewUpdateCount = 0

    func keyEquivalentForTesting(_ command: StatusMenuCommand) -> String? {
        statusMenuItems[command]?.keyEquivalent
    }

    func keyEquivalentModifierMaskForTesting(
        _ command: StatusMenuCommand
    ) -> NSEvent.ModifierFlags? {
        statusMenuItems[command]?.keyEquivalentModifierMask
    }

    func containsMenuItemForTesting(_ command: StatusMenuCommand) -> Bool {
        statusMenuItems[command] != nil
    }

    func performCommandForTesting(_ command: StatusMenuCommand) {
        guard let item = statusMenuItems[command], let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }
#endif

    init(
        selectedWidthPreset: RenderWidthPreset,
        selectedTheme: RenderTheme,
        shortcutConfiguration: GlobalShortcutConfiguration = .default,
        actions: Actions
    ) {
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem(
            selectedWidthPreset: selectedWidthPreset,
            selectedTheme: selectedTheme,
            shortcutConfiguration: shortcutConfiguration
        )
    }

    var button: NSStatusBarButton? {
        statusItem.button
    }

    func updateClipboardPreview(_ preview: String) {
#if DEBUG
        clipboardPreviewUpdateCount += 1
#endif
        clipboardPreviewView.update(preview)
    }

    func apply(_ presentation: StatusMenuPresentation) {
        for (command, item) in statusMenuItems {
            let itemPresentation = presentation[command]
            item.title = itemPresentation.title
            item.isEnabled = itemPresentation.isEnabled
        }
    }

    func selectWidthPreset(_ selectedPreset: RenderWidthPreset) {
        for (preset, item) in widthMenuItems {
            item.state = preset == selectedPreset ? .on : .off
        }
    }

    func selectTheme(_ selectedTheme: RenderTheme) {
        for (theme, item) in themeMenuItems {
            item.state = theme == selectedTheme ? .on : .off
        }
    }

    func applyShortcuts(_ configuration: GlobalShortcutConfiguration) {
        precondition(configuration.isValid)
        applyShortcut(configuration.render, to: .renderClipboard)
        applyShortcut(configuration.showLastRender, to: .showLastRender)
    }

    func applyStatusItem(_ presentation: StatusItemPresentation) {
        guard let button = statusItem.button else { return }
        if let symbolName = presentation.symbolName,
           let image = NSImage(
               systemSymbolName: symbolName,
               accessibilityDescription: nil
           ) {
            image.isTemplate = true
            button.image = image
        } else {
            button.image = brandStatusImage
        }
        button.setAccessibilityLabel(presentation.accessibilityLabel)
    }

    func removeStatusItem() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        actions.menuWillOpen()
    }

    private func configureStatusItem(
        selectedWidthPreset: RenderWidthPreset,
        selectedTheme: RenderTheme,
        shortcutConfiguration: GlobalShortcutConfiguration
    ) {
        applyStatusItem(StatusItemPresentation(
            symbolName: nil,
            accessibilityLabel: L10n.text(
                "accessibility.app",
                defaultValue: "md2png"
            )
        ))

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let clipboardPreviewMenuItem = NSMenuItem()
        clipboardPreviewMenuItem.view = clipboardPreviewView
        menu.addItem(clipboardPreviewMenuItem)

        let renderMenuItem = NSMenuItem(
            title: StatusMenuPresentation.title(for: .renderClipboard),
            action: #selector(renderClipboard),
            keyEquivalent: ""
        )
        renderMenuItem.target = self

        let renderMarkdownFileMenuItem = NSMenuItem(
            title: StatusMenuPresentation.title(for: .renderMarkdownFile),
            action: #selector(renderMarkdownFile),
            keyEquivalent: ""
        )
        renderMarkdownFileMenuItem.target = self

        let previewMenuItem = NSMenuItem(
            title: StatusMenuPresentation.title(for: .showLastRender),
            action: #selector(showLastRender),
            keyEquivalent: ""
        )
        previewMenuItem.target = self

        let rerenderLastMarkdownMenuItem = NSMenuItem(
            title: StatusMenuPresentation.title(for: .rerenderLastMarkdown),
            action: #selector(rerenderLastMarkdown),
            keyEquivalent: ""
        )
        rerenderLastMarkdownMenuItem.target = self

        let restoreLastMarkdownMenuItem = NSMenuItem(
            title: StatusMenuPresentation.title(for: .restoreLastMarkdown),
            action: #selector(restoreLastMarkdown),
            keyEquivalent: ""
        )
        restoreLastMarkdownMenuItem.target = self

        let renderWidthTitle = StatusMenuPresentation.title(for: .outputWidth)
        let renderWidthMenuItem = NSMenuItem(
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
            widthMenuItems[preset] = item
        }
        renderWidthMenuItem.submenu = renderWidthMenu

        let renderThemeTitle = StatusMenuPresentation.title(for: .theme)
        let renderThemeMenuItem = NSMenuItem(
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
            themeMenuItems[theme] = item
        }
        renderThemeMenuItem.submenu = renderThemeMenu

        let examplesTitle = StatusMenuPresentation.title(for: .examples)
        let examplesMenuItem = NSMenuItem(
            title: examplesTitle,
            action: nil,
            keyEquivalent: ""
        )
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

        let settingsItem = NSMenuItem(
            title: StatusMenuPresentation.title(for: .settings),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self

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
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self

        statusMenuItems = [
            .renderClipboard: renderMenuItem,
            .renderMarkdownFile: renderMarkdownFileMenuItem,
            .showLastRender: previewMenuItem,
            .rerenderLastMarkdown: rerenderLastMarkdownMenuItem,
            .restoreLastMarkdown: restoreLastMarkdownMenuItem,
            .theme: renderThemeMenuItem,
            .outputWidth: renderWidthMenuItem,
            .examples: examplesMenuItem,
            .settings: settingsItem,
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
        selectWidthPreset(selectedWidthPreset)
        selectTheme(selectedTheme)
        applyShortcuts(shortcutConfiguration)
    }

    private func applyShortcut(
        _ shortcut: GlobalShortcut,
        to command: StatusMenuCommand
    ) {
        guard let item = statusMenuItems[command] else { return }
        item.keyEquivalent = shortcut.key.keyEquivalent
        item.keyEquivalentModifierMask = shortcut.menuModifierMask
    }

    @objc private func renderClipboard() {
        actions.renderClipboard()
    }

    @objc private func renderMarkdownFile() {
        actions.renderMarkdownFile()
    }

    @objc private func showLastRender() {
        actions.showLastRender()
    }

    @objc private func rerenderLastMarkdown() {
        actions.rerenderLastMarkdown()
    }

    @objc private func restoreLastMarkdown() {
        actions.restoreLastMarkdown()
    }

    @objc private func renderExample(_ sender: NSMenuItem) {
        guard let kind = ExampleKind(rawValue: sender.tag) else { return }
        actions.renderExample(kind)
    }

    @objc private func selectRenderWidthPreset(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let preset = RenderWidthPreset(rawValue: rawValue) else {
            return
        }
        actions.selectWidthPreset(preset)
    }

    @objc private func selectRenderTheme(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let theme = RenderTheme(rawValue: rawValue) else {
            return
        }
        actions.selectTheme(theme)
    }

    @objc private func showSettings() {
        actions.showSettings()
    }

    @objc private func showWelcome() {
        actions.showWelcome()
    }

    @objc private func showAbout() {
        actions.showAbout()
    }

    @objc private func quit() {
        actions.quit()
    }
}
