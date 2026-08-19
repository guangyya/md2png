import AppKit
import SwiftUI

@MainActor
final class WelcomeController: NSWindowController, NSWindowDelegate {
    private let preference: WelcomePreference
    private let copy: WelcomeCopy
    private let onVisibilityChange: (Bool) -> Void
    private let onShowSettings: () -> Void
    private let onTrySample: () -> Void
#if DEBUG
    private(set) var launchAtLoginRefreshCountForTesting = 0
#endif
    private let shortcutVerificationState = WelcomeShortcutVerificationState()
    private let launchAtLoginState: WelcomeLaunchAtLoginState
    private let visibleFrameProvider: @MainActor () -> NSRect?
    private let dynamicTypeSize: DynamicTypeSize?

#if DEBUG
    var displayedShortcutStatuses: [WelcomeShortcutStatus] {
        shortcutVerificationState.shortcuts
    }
    var displayedContentSize: NSSize {
        window?.contentView?.bounds.size ?? .zero
    }
    var displayedLaunchAtLoginPresentation: LaunchAtLoginPresentation {
        launchAtLoginState.presentation
    }
#endif

    init(
        preference: WelcomePreference = WelcomePreference(),
        localizationBundle: Bundle? = nil,
        launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController(),
        onLaunchAtLoginError: @escaping (Error) -> Void = { _ in },
        onVisibilityChange: @escaping (Bool) -> Void = { _ in },
        onShowSettings: @escaping () -> Void = {},
        visibleFrameProvider: @escaping @MainActor () -> NSRect? = WelcomeController.activeVisibleFrame,
        dynamicTypeSize: DynamicTypeSize? = nil,
        onTrySample: @escaping () -> Void
    ) {
        self.preference = preference
        copy = WelcomeCopy(localizationBundle: localizationBundle)
        launchAtLoginState = WelcomeLaunchAtLoginState(
            controller: launchAtLoginController,
            onError: onLaunchAtLoginError
        )
        self.onVisibilityChange = onVisibilityChange
        self.onShowSettings = onShowSettings
        self.visibleFrameProvider = visibleFrameProvider
        self.dynamicTypeSize = dynamicTypeSize
        self.onTrySample = onTrySample
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    func showIfNeeded(shortcuts: [WelcomeShortcutStatus]) -> Bool {
        guard preference.shouldShowOnLaunch else { return false }
        show(shortcuts: shortcuts)
        return true
    }

    func show(shortcuts: [WelcomeShortcutStatus]) {
        shortcutVerificationState.reset(shortcuts: shortcuts)
        launchAtLoginState.refresh()
        if window == nil {
            let window = makeWindow()
            window.delegate = self
            self.window = window
        }

        guard let window else { return }
        let visibleFrame = visibleFrameProvider()
        let contentSize = contentSize(for: window, visibleFrame: visibleFrame)
        window.contentViewController = makeContentViewController(contentSize: contentSize)
        window.setContentSize(contentSize)
        onVisibilityChange(true)
        NSApp.activate(ignoringOtherApps: true)
        if let visibleFrame {
            center(window: window, in: visibleFrame)
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func verifyShortcut(_ command: GlobalShortcutCommand) -> Bool {
        guard let window, window.isVisible, !NSApp.isHidden else { return false }
        if let shortcut = shortcutVerificationState.verify(id: command.rawValue) {
            announceVerification(of: shortcut, in: window)
        }
        return true
    }

    func refreshLaunchAtLogin() {
#if DEBUG
        launchAtLoginRefreshCountForTesting += 1
#endif
        launchAtLoginState.refresh()
    }

    func refreshShortcuts(_ shortcuts: [WelcomeShortcutStatus]) {
        shortcutVerificationState.reset(shortcuts: shortcuts)
    }

    func windowWillClose(_ notification: Notification) {
        preference.markCompleted()
        onVisibilityChange(false)
    }

#if DEBUG
    func performLaunchAtLoginActionForTesting() {
        launchAtLoginState.performPrimaryAction()
    }

    func trySampleForTesting() {
        trySample()
    }

    func completeForTesting() {
        complete()
    }
#endif

    private func makeWindow() -> AppWindow {
        let window = AppWindow(
            contentRect: NSRect(
                origin: .zero,
                size: WelcomeLayout.preferredContentSize
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = copy.windowTitle
        window.isReleasedWhenClosed = false
        window.showSettingsHandler = onShowSettings
        window.level = .normal
        window.collectionBehavior.insert(.moveToActiveSpace)
        return window
    }

    private func contentSize(
        for window: NSWindow,
        visibleFrame: NSRect?
    ) -> NSSize {
        let maximumContentSize = visibleFrame.map { visibleFrame in
            let availableFrame = visibleFrame.insetBy(
                dx: WelcomeLayout.screenInset,
                dy: WelcomeLayout.screenInset
            )
            return window.contentRect(forFrameRect: availableFrame).size
        } ?? WelcomeLayout.preferredContentSize
        return WelcomeLayout.contentSize(maximumContentSize: maximumContentSize)
    }

    private func makeContentViewController(
        contentSize: NSSize
    ) -> NSHostingController<AnyView> {
        let rootView = WelcomeView(
            copy: copy,
            contentSize: contentSize,
            shortcutVerificationState: shortcutVerificationState,
            launchAtLoginState: launchAtLoginState,
            onTrySample: { [weak self] in self?.trySample() },
            onDone: { [weak self] in self?.complete() }
        )
        var erasedRootView = AnyView(rootView)
        if let dynamicTypeSize {
            erasedRootView = AnyView(
                erasedRootView.environment(\.dynamicTypeSize, dynamicTypeSize)
            )
        }
        return NSHostingController(rootView: erasedRootView)
    }

    private func trySample() {
        onTrySample()
    }

    private func complete() {
        preference.markCompleted()
        close()
    }

    private func announceVerification(
        of shortcut: WelcomeShortcutStatus,
        in window: NSWindow
    ) {
        guard let contentView = window.contentView else { return }
        NSAccessibility.post(
            element: contentView,
            notification: .announcementRequested,
            userInfo: [
                .announcement: String(
                    format: copy.shortcutVerifiedAnnouncementFormat,
                    shortcut.title
                ),
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    private func center(window: NSWindow, in visibleFrame: NSRect) {
        window.setFrameOrigin(WelcomeWindowPlacement.centeredOrigin(
            windowSize: window.frame.size,
            visibleFrame: visibleFrame
        ))
    }

    private static func activeVisibleFrame() -> NSRect? {
        let pointerLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first {
            $0.frame.contains(pointerLocation)
        } ?? NSScreen.main ?? NSScreen.screens.first
        return targetScreen?.visibleFrame
    }
}
