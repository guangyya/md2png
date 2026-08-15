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

    init(
        registration: GlobalHotKey.Registration,
        failedRegistrationIDs: Set<UInt32>
    ) {
        id = registration.id
        title = registration.commandTitle
        shortcutGlyphs = registration.shortcutGlyphs
        shortcutAccessibilityName = registration.shortcutAccessibilityName
        isRegistered = !failedRegistrationIDs.contains(registration.id)
    }

    init(
        id: UInt32,
        title: String,
        shortcutGlyphs: String,
        shortcutAccessibilityName: String,
        isRegistered: Bool
    ) {
        self.id = id
        self.title = title
        self.shortcutGlyphs = shortcutGlyphs
        self.shortcutAccessibilityName = shortcutAccessibilityName
        self.isRegistered = isRegistered
    }
}

struct WelcomeWindowPlacement {
    static func centeredOrigin(
        windowSize: NSSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        )
    }
}

private enum WelcomeLayout {
    static let contentSize = NSSize(width: 620, height: 650)
}

struct WelcomeCopy {
    let windowTitle: String
    let title: String
    let subtitle: String
    let copyStepTitle: String
    let copyStepDetail: String
    let renderStepTitle: String
    let renderStepDetail: String
    let pasteStepTitle: String
    let pasteStepDetail: String
    let shortcutsTitle: String
    let shortcutReady: String
    let shortcutUnavailable: String
    let shortcutConflictHelp: String
    let privacyNote: String
    let reopenHint: String
    let trySample: String
    let trySampleHelp: String
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
        shortcutsTitle = L10n.text(
            "welcome.shortcuts",
            defaultValue: "Global shortcuts",
            bundle: localizationBundle
        )
        shortcutReady = L10n.text(
            "welcome.shortcut_ready",
            defaultValue: "Ready",
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
        privacyNote = L10n.text(
            "welcome.privacy_note",
            defaultValue: "md2png never pastes, sends, or uploads your content automatically.",
            bundle: localizationBundle
        )
        reopenHint = L10n.text(
            "welcome.reopen_hint",
            defaultValue: "If this window gets hidden, choose Show Welcome from the md2png menu bar.",
            bundle: localizationBundle
        )
        trySample = L10n.text(
            "welcome.try_sample",
            defaultValue: "Try a Short Sample",
            bundle: localizationBundle
        )
        trySampleHelp = L10n.text(
            "welcome.try_sample_help",
            defaultValue: "Explicitly copy and render the bundled short sample.",
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
final class WelcomeController: NSWindowController, NSWindowDelegate {
    private let preference: WelcomePreference
    private let copy: WelcomeCopy
    private let onVisibilityChange: (Bool) -> Void
    private let onTrySample: () -> Void
    private var shortcutStatuses: [WelcomeShortcutStatus] = []

#if DEBUG
    var displayedShortcutStatuses: [WelcomeShortcutStatus] { shortcutStatuses }
    var displayedContentSize: NSSize {
        window?.contentView?.bounds.size ?? .zero
    }
#endif

    init(
        preference: WelcomePreference = WelcomePreference(),
        localizationBundle: Bundle? = nil,
        onVisibilityChange: @escaping (Bool) -> Void = { _ in },
        onTrySample: @escaping () -> Void
    ) {
        self.preference = preference
        copy = WelcomeCopy(localizationBundle: localizationBundle)
        self.onVisibilityChange = onVisibilityChange
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
        shortcutStatuses = shortcuts
        let rootView = WelcomeView(
            copy: copy,
            shortcuts: shortcuts,
            onTrySample: { [weak self] in self?.trySample() },
            onDone: { [weak self] in self?.complete() }
        )
        let hostingController = NSHostingController(rootView: rootView)

        if window == nil {
            let window = PreviewWindow(
                contentRect: NSRect(origin: .zero, size: WelcomeLayout.contentSize),
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
        window?.contentViewController = hostingController
        window?.setContentSize(WelcomeLayout.contentSize)
        onVisibilityChange(true)
        NSApp.activate(ignoringOtherApps: true)
        centerOnActiveScreen()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        preference.markCompleted()
        onVisibilityChange(false)
    }

#if DEBUG
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

    private func centerOnActiveScreen() {
        guard let window else { return }
        let pointerLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first {
            $0.frame.contains(pointerLocation)
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = targetScreen?.visibleFrame else { return }
        window.setFrameOrigin(WelcomeWindowPlacement.centeredOrigin(
            windowSize: window.frame.size,
            visibleFrame: visibleFrame
        ))
    }
}

private struct WelcomeView: View {
    let copy: WelcomeCopy
    let shortcuts: [WelcomeShortcutStatus]
    let onTrySample: () -> Void
    let onDone: () -> Void

    private var hasShortcutConflict: Bool {
        shortcuts.contains { !$0.isRegistered }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(copy.title)
                        .font(.system(size: 25, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(copy.subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            WelcomeWorkflowDemo(copy: copy)

            VStack(alignment: .leading, spacing: 9) {
                Text(copy.shortcutsTitle)
                    .font(.headline)

                ForEach(shortcuts) { shortcut in
                    WelcomeShortcutRow(shortcut: shortcut, copy: copy)
                }

                if hasShortcutConflict {
                    Label(copy.shortcutConflictHelp, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(copy.privacyNote, systemImage: "lock.shield")
                Label(copy.reopenHint, systemImage: "menubar.rectangle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Button(action: onTrySample) {
                    Label(copy.trySample, systemImage: "sparkles")
                }
                .help(copy.trySampleHelp)

                Spacer()

                Button(copy.done, action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(
            width: WelcomeLayout.contentSize.width,
            height: WelcomeLayout.contentSize.height
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct WelcomeShortcutRow: View {
    let shortcut: WelcomeShortcutStatus
    let copy: WelcomeCopy

    private var statusText: String {
        shortcut.isRegistered ? copy.shortcutReady : copy.shortcutUnavailable
    }

    private var statusSymbol: String {
        shortcut.isRegistered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        shortcut.isRegistered ? .green : .orange
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(shortcut.title)
                .lineLimit(1)

            Spacer()

            Text(shortcut.shortcutGlyphs)
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
                .accessibilityLabel(shortcut.shortcutAccessibilityName)

            Label(statusText, systemImage: statusSymbol)
                .font(.callout.weight(.medium))
                .foregroundStyle(statusColor)
                .frame(width: 74, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
