import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let renderer = MarkdownRenderer()
    private let hud = HUDController()
    private let previewController = PreviewController()
    private lazy var aboutController = AboutController()
    private var statusItem: NSStatusItem!
    private var hotKey: GlobalHotKey?
    private var lastImage: NSImage?
    private let clipboardPreviewView = ClipboardPreviewView()
    private var renderMenuItem: NSMenuItem!
    private var previewMenuItem: NSMenuItem!
    private var examplesMenuItem: NSMenuItem!
    private var renderActivity = RenderActivityState()
    private lazy var brandStatusImage = BrandIcon.statusBarImage()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        let hotKey = GlobalHotKey(registrations: [
            .render { [weak self] in self?.renderClipboard() },
            .showLastRender { [weak self] in self?.showLastRender() }
        ])
        self.hotKey = hotKey
        if !hotKey.failedRegistrations.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.hud.show(
                    L10n.text(
                        "hud.shortcut_conflict",
                        defaultValue: "A global shortcut is already in use — menu commands still work"
                    ),
                    symbol: "keyboard.badge.ellipsis",
                    isError: true
                )
            }
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = brandStatusImage
        statusItem.button?.setAccessibilityLabel(
            L10n.text("accessibility.app", defaultValue: "md2png")
        )

        let menu = NSMenu()
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

        previewMenuItem = menu.addItem(
            withTitle: L10n.text("menu.show_last_render", defaultValue: "Show Last Render"),
            action: #selector(showLastRender),
            keyEquivalent: "z"
        )
        previewMenuItem.keyEquivalentModifierMask = [.command, .control]
        previewMenuItem.target = self
        previewMenuItem.isEnabled = false

        menu.addItem(.separator())
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
    }

    func menuWillOpen(_ menu: NSMenu) {
        clipboardPreviewView.update(Clipboard.menuPreview(includeLabel: false))
    }

    @objc private func renderClipboard() {
        guard !renderActivity.isRendering else { return }
        do {
            let markdown = try Clipboard.markdownText()
            render(markdown)
        } catch {
            show(error)
        }
    }

    @objc private func showLastRender() {
        guard let lastImage else { return }
        previewController.show(image: lastImage)
    }

    @objc private func renderExample(_ sender: NSMenuItem) {
        guard !renderActivity.isRendering else { return }
        guard let kind = ExampleKind(rawValue: sender.tag) else { return }
        do {
            let example = try AppResources.exampleMarkdown(for: kind)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(example, forType: .string)
            render(example)
        } catch {
            show(error)
        }
    }

    private func render(_ markdown: String) {
        guard renderActivity.begin() else { return }
        updateRenderingUI(isRendering: true)
        statusItem.button?.image = NSImage(
            systemSymbolName: "hourglass",
            accessibilityDescription: L10n.text(
                "accessibility.rendering",
                defaultValue: "Rendering"
            )
        )

        renderer.render(markdown) { [weak self] result in
            guard let self else { return }
            self.renderActivity.finish()
            self.updateRenderingUI(isRendering: false)

            switch result {
            case let .success(image):
                do {
                    try Clipboard.write(image: image)
                    self.lastImage = image
                    self.previewMenuItem.isEnabled = true
                    self.hud.show(
                        L10n.text(
                            "hud.png_copied",
                            defaultValue: "PNG copied — paste with Command-V"
                        ),
                        symbol: "checkmark.circle.fill"
                    )
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
        if !isRendering {
            statusItem.button?.image = brandStatusImage
        }
    }

    @objc private func showAbout() {
        aboutController.show()
    }

    @objc private func terminateFromStatusMenu() {
        NSApp.terminate(nil)
    }

    private func show(_ error: Error) {
        hud.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill", isError: true)
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
