import AppKit
import SwiftUI

final class WelcomePreference {
    static let defaultsKey = "welcome.completed"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shouldShowOnLaunch: Bool {
        !defaults.bool(forKey: Self.defaultsKey)
    }

    func markCompleted() {
        defaults.set(true, forKey: Self.defaultsKey)
    }
}

struct WelcomeShortcutStatus: Identifiable, Equatable {
    let id: UInt32
    let title: String
    let shortcutGlyphs: String
    let shortcutAccessibilityName: String
    let isRegistered: Bool
    fileprivate(set) var isVerified: Bool
    fileprivate(set) var verificationCount: Int

    init(
        registration: GlobalHotKey.Registration,
        failedRegistrationIDs: Set<UInt32>
    ) {
        id = registration.id
        title = registration.commandTitle
        shortcutGlyphs = registration.shortcutGlyphs
        shortcutAccessibilityName = registration.shortcutAccessibilityName
        isRegistered = !failedRegistrationIDs.contains(registration.id)
        isVerified = false
        verificationCount = 0
    }

    init(
        id: UInt32,
        title: String,
        shortcutGlyphs: String,
        shortcutAccessibilityName: String,
        isRegistered: Bool,
        isVerified: Bool = false
    ) {
        self.id = id
        self.title = title
        self.shortcutGlyphs = shortcutGlyphs
        self.shortcutAccessibilityName = shortcutAccessibilityName
        self.isRegistered = isRegistered
        self.isVerified = isRegistered && isVerified
        verificationCount = 0
    }
}

@MainActor
private final class WelcomeShortcutVerificationState: ObservableObject {
    @Published private(set) var shortcuts: [WelcomeShortcutStatus] = []

    func reset(shortcuts: [WelcomeShortcutStatus]) {
        self.shortcuts = shortcuts.map { shortcut in
            var shortcut = shortcut
            shortcut.isVerified = false
            shortcut.verificationCount = 0
            return shortcut
        }
    }

    @discardableResult
    func verify(id: UInt32) -> WelcomeShortcutStatus? {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }),
              shortcuts[index].isRegistered else { return nil }
        shortcuts[index].isVerified = true
        shortcuts[index].verificationCount += 1
        return shortcuts[index]
    }
}

struct WelcomeWindowPlacement {
    static func centeredOrigin(
        windowSize: NSSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        let centeredX = visibleFrame.midX - windowSize.width / 2
        let centeredY = visibleFrame.midY - windowSize.height / 2
        return NSPoint(
            x: clampedOrigin(
                centeredX,
                minimum: visibleFrame.minX,
                maximum: visibleFrame.maxX - windowSize.width
            ),
            y: clampedOrigin(
                centeredY,
                minimum: visibleFrame.minY,
                maximum: visibleFrame.maxY - windowSize.height
            )
        )
    }

    private static func clampedOrigin(
        _ value: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        guard maximum >= minimum else { return minimum }
        return min(max(value, minimum), maximum)
    }
}

enum WelcomeLayout {
    static let preferredContentSize = NSSize(width: 560, height: 570)
    static let screenInset: CGFloat = 12
    static let statusColumnMinimumWidth: CGFloat = 88

    static func contentSize(maximumContentSize: NSSize) -> NSSize {
        NSSize(
            width: max(1, min(preferredContentSize.width, maximumContentSize.width)),
            height: max(1, min(preferredContentSize.height, maximumContentSize.height))
        )
    }
}

struct WelcomeCopy {
    let windowTitle: String
    let title: String
    let subtitle: String
    let copyStepTitle: String
    let copyStepDetail: String
    let copyStepCompletionDetail: String
    let renderStepTitle: String
    let renderStepDetail: String
    let renderStepCompletionDetail: String
    let pasteStepTitle: String
    let pasteStepDetail: String
    let pasteStepCompletionDetail: String
    let shortcutsTitle: String
    let shortcutVerificationHelp: String
    let shortcutReady: String
    let shortcutDetected: String
    let shortcutVerified: String
    let shortcutUnavailable: String
    let shortcutConflictHelp: String
    let shortcutVerifiedAnnouncementFormat: String
    let launchAtLoginTitle: String
    let launchAtLoginOptional: String
    let launchAtLoginOn: String
    let launchAtLoginOff: String
    let launchAtLoginOpenSettings: String
    let launchAtLoginUnavailable: String
    let launchAtLoginApprovalHelp: String
    let privacyNote: String
    let reopenHint: String
    let trySample: String
    let trySampleHelp: String
    let replayDemo: String
    let done: String

    init(localizationBundle: Bundle? = nil) {
        windowTitle = L10n.text(
            "welcome.window_title",
            defaultValue: "Welcome to md2png",
            bundle: localizationBundle
        )
        title = L10n.text(
            "welcome.title",
            defaultValue: "Turn Markdown into a polished PNG",
            bundle: localizationBundle
        )
        subtitle = L10n.text(
            "welcome.subtitle",
            defaultValue: "A private, local workflow in three simple steps.",
            bundle: localizationBundle
        )
        copyStepTitle = L10n.text(
            "welcome.step.copy.title",
            defaultValue: "Copy Markdown",
            bundle: localizationBundle
        )
        copyStepDetail = L10n.text(
            "welcome.step.copy.detail",
            defaultValue: "Copy Markdown text in any app.",
            bundle: localizationBundle
        )
        copyStepCompletionDetail = L10n.text(
            "welcome.step.copy.completion_detail",
            defaultValue: "Copy in any app",
            bundle: localizationBundle
        )
        renderStepTitle = L10n.text(
            "welcome.step.render.title",
            defaultValue: "Render it",
            bundle: localizationBundle
        )
        renderStepDetail = L10n.text(
            "welcome.step.render.detail",
            defaultValue: "Use the global shortcut or choose Render Clipboard as Image from the menu bar.",
            bundle: localizationBundle
        )
        renderStepCompletionDetail = L10n.text(
            "welcome.step.render.completion_detail",
            defaultValue: "Render locally",
            bundle: localizationBundle
        )
        pasteStepTitle = L10n.text(
            "welcome.step.paste.title",
            defaultValue: "Paste the PNG",
            bundle: localizationBundle
        )
        pasteStepDetail = L10n.text(
            "welcome.step.paste.detail",
            defaultValue: "Press Command-V, review the image, and send it yourself.",
            bundle: localizationBundle
        )
        pasteStepCompletionDetail = L10n.text(
            "welcome.step.paste.completion_detail",
            defaultValue: "Review, then send",
            bundle: localizationBundle
        )
        shortcutsTitle = L10n.text(
            "welcome.shortcuts",
            defaultValue: "Global shortcuts",
            bundle: localizationBundle
        )
        shortcutVerificationHelp = L10n.text(
            "welcome.shortcut_verification_help",
            defaultValue: "Press a shortcut here to test it without running the command.",
            bundle: localizationBundle
        )
        shortcutReady = L10n.text(
            "welcome.shortcut_ready",
            defaultValue: "Ready",
            bundle: localizationBundle
        )
        shortcutDetected = L10n.text(
            "welcome.shortcut_detected",
            defaultValue: "Detected",
            bundle: localizationBundle
        )
        shortcutVerified = L10n.text(
            "welcome.shortcut_verified",
            defaultValue: "Works",
            bundle: localizationBundle
        )
        shortcutUnavailable = L10n.text(
            "welcome.shortcut_unavailable",
            defaultValue: "In Use",
            bundle: localizationBundle
        )
        shortcutConflictHelp = L10n.text(
            "welcome.shortcut_conflict_help",
            defaultValue: "Another app is using a shortcut. Every action remains available from the md2png menu.",
            bundle: localizationBundle
        )
        shortcutVerifiedAnnouncementFormat = L10n.text(
            "welcome.shortcut_verified_announcement",
            defaultValue: "%@ shortcut works.",
            bundle: localizationBundle
        )
        launchAtLoginTitle = L10n.text(
            "welcome.launch_at_login.title",
            defaultValue: "Launch at Login",
            bundle: localizationBundle
        )
        launchAtLoginOptional = L10n.text(
            "welcome.launch_at_login.optional",
            defaultValue: "Optional",
            bundle: localizationBundle
        )
        launchAtLoginOn = L10n.text(
            "welcome.launch_at_login.on",
            defaultValue: "On",
            bundle: localizationBundle
        )
        launchAtLoginOff = L10n.text(
            "welcome.launch_at_login.off",
            defaultValue: "Off",
            bundle: localizationBundle
        )
        launchAtLoginOpenSettings = L10n.text(
            "welcome.launch_at_login.open_settings",
            defaultValue: "Open Settings…",
            bundle: localizationBundle
        )
        launchAtLoginUnavailable = L10n.text(
            "welcome.launch_at_login.unavailable",
            defaultValue: "Unavailable",
            bundle: localizationBundle
        )
        launchAtLoginApprovalHelp = L10n.text(
            "welcome.launch_at_login.approval_help",
            defaultValue: "Approval is required in Login Items.",
            bundle: localizationBundle
        )
        privacyNote = L10n.text(
            "welcome.privacy_note",
            defaultValue: "Private and local. Nothing is uploaded automatically.",
            bundle: localizationBundle
        )
        reopenHint = L10n.text(
            "welcome.reopen_hint",
            defaultValue: "Reopen from Show Welcome in the menu.",
            bundle: localizationBundle
        )
        trySample = L10n.text(
            "welcome.try_sample",
            defaultValue: "Try an Example",
            bundle: localizationBundle
        )
        trySampleHelp = L10n.text(
            "welcome.try_sample_help",
            defaultValue: "Choose a bundled example to try.",
            bundle: localizationBundle
        )
        replayDemo = L10n.text(
            "welcome.replay_demo",
            defaultValue: "Replay workflow demo",
            bundle: localizationBundle
        )
        done = L10n.text(
            "welcome.done",
            defaultValue: "Done",
            bundle: localizationBundle
        )
    }
}

@MainActor
final class WelcomeLaunchAtLoginState: ObservableObject {
    @Published private(set) var presentation: LaunchAtLoginPresentation

    private let controller: LaunchAtLoginController
    private let onError: (Error) -> Void

    init(
        controller: LaunchAtLoginController,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.controller = controller
        self.onError = onError
        presentation = controller.presentation
    }

    func refresh() {
        presentation = controller.presentation
    }

    func performPrimaryAction() {
        do {
            let result = try controller.performPrimaryAction()
            if result == .statusChanged(.requiresApproval) {
                controller.openSystemSettings()
            }
        } catch {
            onError(error)
        }
        refresh()
    }
}

@MainActor
final class WelcomeController: NSWindowController, NSWindowDelegate {
    private let preference: WelcomePreference
    private let copy: WelcomeCopy
    private let onVisibilityChange: (Bool) -> Void
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
            let window = PreviewWindow(
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
            window.level = .normal
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.delegate = self
            self.window = window
        }

        guard let window else { return }
        let visibleFrame = visibleFrameProvider()
        let maximumContentSize = visibleFrame.map { visibleFrame in
            let availableFrame = visibleFrame.insetBy(
                dx: WelcomeLayout.screenInset,
                dy: WelcomeLayout.screenInset
            )
            return window.contentRect(forFrameRect: availableFrame).size
        } ?? WelcomeLayout.preferredContentSize
        let contentSize = WelcomeLayout.contentSize(
            maximumContentSize: maximumContentSize
        )
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
        let hostingController = NSHostingController(rootView: erasedRootView)

        window.contentViewController = hostingController
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

private struct WelcomeView: View {
    let copy: WelcomeCopy
    let contentSize: NSSize
    @ObservedObject var shortcutVerificationState: WelcomeShortcutVerificationState
    @ObservedObject var launchAtLoginState: WelcomeLaunchAtLoginState
    let onTrySample: () -> Void
    let onDone: () -> Void

    private var hasShortcutConflict: Bool {
        shortcutVerificationState.shortcuts.contains { !$0.isRegistered }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 13) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .padding(7)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color.cyan.opacity(0.2),
                                        Color.purple.opacity(0.16)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.cyan.opacity(0.5),
                                                Color.purple.opacity(0.4)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.8
                                    )
                            }
                            .shadow(color: Color.purple.opacity(0.12), radius: 9, y: 3)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(copy.title)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.primary, Color.purple.opacity(0.9)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .fixedSize(horizontal: false, vertical: true)
                            Text(copy.subtitle)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    WelcomeWorkflowDemo(copy: copy)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(copy.shortcutsTitle)
                            .font(.headline)

                        Text(copy.shortcutVerificationHelp)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(shortcutVerificationState.shortcuts) { shortcut in
                            WelcomeShortcutRow(shortcut: shortcut, copy: copy)
                        }

                        if hasShortcutConflict {
                            Label(copy.shortcutConflictHelp, systemImage: "info.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )

            Divider()

            WelcomeFooter(
                copy: copy,
                launchAtLoginState: launchAtLoginState,
                onTrySample: onTrySample,
                onDone: onDone
            )
        }
        .frame(
            width: contentSize.width,
            height: contentSize.height
        )
        .background {
            WelcomeBackdrop()
        }
    }
}

private struct WelcomeLaunchAtLoginRow: View {
    let copy: WelcomeCopy
    @ObservedObject var state: WelcomeLaunchAtLoginState
    @State private var isHovering = false

    var body: some View {
        Button {
            state.performPrimaryAction()
        } label: {
            HStack(spacing: 10) {
                Text(copy.launchAtLoginTitle)
                    .font(.callout.weight(.medium))

                Text(copy.launchAtLoginOptional)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Label(statusText, systemImage: statusSymbol)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(
                        minWidth: WelcomeLayout.statusColumnMinimumWidth,
                        alignment: .leading
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!state.presentation.canPerformAction)
        .background(
            LinearGradient(
                colors: [
                    isHovering && state.presentation.canPerformAction
                        ? Color.accentColor.opacity(0.12)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.72),
                    Color.accentColor.opacity(0.045)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.1), lineWidth: 0.5)
        }
        .onHover { isHovering = $0 }
        .help(actionHelp)
        .accessibilityHint(actionHelp)
    }

    private var statusText: String {
        switch state.presentation.menuAction {
        case .enable:
            copy.launchAtLoginOff
        case .disable:
            copy.launchAtLoginOn
        case .allowInSystemSettings:
            copy.launchAtLoginOff
        case .unavailable:
            copy.launchAtLoginUnavailable
        }
    }

    private var statusSymbol: String {
        switch state.presentation.menuAction {
        case .enable, .allowInSystemSettings:
            "circle"
        case .disable:
            "checkmark.circle.fill"
        case .unavailable:
            "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch state.presentation.menuAction {
        case .disable:
            .green
        case .enable, .allowInSystemSettings, .unavailable:
            .secondary
        }
    }

    private var actionHelp: String {
        switch state.presentation.menuAction {
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
            "\(copy.launchAtLoginApprovalHelp) \(copy.launchAtLoginOpenSettings)"
        case .unavailable:
            copy.launchAtLoginUnavailable
        }
    }
}

private struct WelcomeFooter: View {
    let copy: WelcomeCopy
    @ObservedObject var launchAtLoginState: WelcomeLaunchAtLoginState
    let onTrySample: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WelcomeLaunchAtLoginRow(
                copy: copy,
                state: launchAtLoginState
            )
            .padding(.horizontal, 22)
            .padding(.vertical, 10)

            Divider()
                .padding(.leading, 22)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    footerNotes
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                    footerActions
                }

                VStack(alignment: .leading, spacing: 6) {
                    footerNotes
                    HStack(spacing: 10) {
                        Spacer()
                        footerActions
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
        }
        .background(.regularMaterial)
    }

    private var footerNotes: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(copy.privacyNote, systemImage: "lock.shield")
            Label(copy.reopenHint, systemImage: "menubar.rectangle")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .background(WelcomeFooterLayoutMarker(
            identifier: WelcomeFooterLayoutMarker.notesIdentifier
        ))
    }

    private var footerActions: some View {
        HStack(spacing: 10) {
            Button(action: onTrySample) {
                Label(copy.trySample, systemImage: "sparkles")
            }
            .help(copy.trySampleHelp)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityIdentifier("WelcomeTrySampleButton")

            Button(copy.done, action: onDone)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityIdentifier("WelcomeDoneButton")
        }
        .fixedSize(horizontal: true, vertical: false)
        .background(WelcomeFooterLayoutMarker(
            identifier: WelcomeFooterLayoutMarker.actionsIdentifier
        ))
    }
}

struct WelcomeFooterLayoutMarker: NSViewRepresentable {
    static let notesIdentifier = NSUserInterfaceItemIdentifier("WelcomeFooterNotesMarker")
    static let actionsIdentifier = NSUserInterfaceItemIdentifier("WelcomeFooterActionsMarker")

    let identifier: NSUserInterfaceItemIdentifier

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = identifier
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.identifier = identifier
    }
}

private struct WelcomeBackdrop: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.cyan.opacity(0.055), location: 0),
                .init(color: Color(nsColor: .windowBackgroundColor), location: 0.42),
                .init(color: Color.purple.opacity(0.05), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct WelcomeShortcutRow: View {
    let shortcut: WelcomeShortcutStatus
    let copy: WelcomeCopy
    @State private var isShowingVerificationFeedback = false
    @State private var verificationFeedbackTask: Task<Void, Never>?

    private var statusText: String {
        if !shortcut.isRegistered {
            return copy.shortcutUnavailable
        }
        if isShowingVerificationFeedback {
            return copy.shortcutDetected
        }
        return shortcut.isVerified ? copy.shortcutVerified : copy.shortcutReady
    }

    private var statusSymbol: String {
        if !shortcut.isRegistered {
            return "exclamationmark.triangle.fill"
        }
        return shortcut.isVerified ? "checkmark.circle.fill" : "circle.dashed"
    }

    private var statusColor: Color {
        if !shortcut.isRegistered {
            return .orange
        }
        return shortcut.isVerified ? .green : .secondary
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(shortcut.title)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Text(shortcut.shortcutGlyphs)
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Color.accentColor.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.accentColor.opacity(0.24), lineWidth: 0.6)
                }
                .accessibilityLabel(shortcut.shortcutAccessibilityName)

            Label(statusText, systemImage: statusSymbol)
                .font(.callout.weight(.medium))
                .foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    minWidth: WelcomeLayout.statusColumnMinimumWidth,
                    alignment: .leading
                )
                .symbolEffect(.bounce, value: shortcut.verificationCount)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [
                    isShowingVerificationFeedback
                        ? Color.green.opacity(0.24)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.72),
                    isShowingVerificationFeedback
                        ? Color.green.opacity(0.12)
                        : Color.accentColor.opacity(0.045)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isShowingVerificationFeedback
                        ? Color.green.opacity(0.75)
                        : Color.accentColor.opacity(0.1),
                    lineWidth: isShowingVerificationFeedback ? 1.4 : 0.5
                )
        }
        .scaleEffect(isShowingVerificationFeedback ? 1.012 : 1)
        .animation(.easeOut(duration: 0.12), value: isShowingVerificationFeedback)
        .onChange(of: shortcut.verificationCount) { _, verificationCount in
            guard verificationCount > 0 else { return }
            verificationFeedbackTask?.cancel()
            isShowingVerificationFeedback = true
            verificationFeedbackTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                isShowingVerificationFeedback = false
            }
        }
        .onDisappear {
            verificationFeedbackTask?.cancel()
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusText)
    }
}
