import AppKit
import Carbon
import SwiftUI

enum ShortcutSettingsLayout {
    static let windowSize = NSSize(width: 520, height: 326)
    static let rowHeight: CGFloat = 56
    static let feedbackHeight: CGFloat = 44
}

struct ShortcutSettingsCopy {
    let windowTitle: String
    let title: String
    let subtitle: String
    let render: String
    let showLastRender: String
    let recording: String
    let recordHelp: String
    let unavailable: String
    let idleHelp: String
    let restoreDefaults: String
    let localizationBundle: Bundle?

    init(localizationBundle: Bundle? = nil) {
        self.localizationBundle = localizationBundle
        windowTitle = L10n.text(
            "settings.window_title",
            defaultValue: "Settings",
            bundle: localizationBundle
        )
        title = L10n.text(
            "settings.shortcuts_title",
            defaultValue: "Keyboard Shortcuts",
            bundle: localizationBundle
        )
        subtitle = L10n.text(
            "settings.shortcuts_subtitle",
            defaultValue: "Click a shortcut, then press a new key combination.",
            bundle: localizationBundle
        )
        render = L10n.text(
            "hotkey.render_title",
            defaultValue: "Render",
            bundle: localizationBundle
        )
        showLastRender = L10n.text(
            "hotkey.show_last_render_title",
            defaultValue: "Show Last Render",
            bundle: localizationBundle
        )
        recording = L10n.text(
            "settings.recording",
            defaultValue: "Type shortcut…",
            bundle: localizationBundle
        )
        recordHelp = L10n.text(
            "settings.record_help",
            defaultValue: "Use Control, Option, or Command. Press Escape to cancel.",
            bundle: localizationBundle
        )
        unavailable = L10n.text(
            "settings.unavailable",
            defaultValue: "Unavailable",
            bundle: localizationBundle
        )
        idleHelp = L10n.text(
            "settings.idle_help",
            defaultValue: "Changes apply immediately. Menu commands always remain available.",
            bundle: localizationBundle
        )
        restoreDefaults = L10n.text(
            "settings.restore_defaults",
            defaultValue: "Restore Defaults",
            bundle: localizationBundle
        )
    }

    func commandTitle(_ command: GlobalShortcutCommand) -> String {
        switch command {
        case .render:
            render
        case .showLastRender:
            showLastRender
        }
    }

    func recorderAccessibilityLabel(_ command: GlobalShortcutCommand) -> String {
        L10n.format(
            "settings.recorder_accessibility_label",
            defaultValue: "%@ shortcut",
            bundle: localizationBundle,
            commandTitle(command)
        )
    }

    func feedbackText(_ feedback: ShortcutSettingsFeedback) -> String {
        switch feedback {
        case .missingPrimaryModifier:
            return L10n.text(
                "settings.feedback.missing_modifier",
                defaultValue: "Include Control, Option, or Command.",
                bundle: localizationBundle
            )
        case .unsupportedKey:
            return L10n.text(
                "settings.feedback.unsupported_key",
                defaultValue: "That key can’t be used. Try another combination.",
                bundle: localizationBundle
            )
        case .duplicate:
            return L10n.text(
                "settings.feedback.duplicate",
                defaultValue: "Choose a different shortcut for each command.",
                bundle: localizationBundle
            )
        case .saveFailed:
            return L10n.text(
                "settings.feedback.save_failed",
                defaultValue: "The shortcut couldn’t be saved. Try again.",
                bundle: localizationBundle
            )
        case let .registrationUnavailable(commands):
            if commands.count == 1, let command = commands.first {
                return L10n.format(
                    "settings.feedback.unavailable_command",
                    defaultValue: "%@ couldn’t be registered. Its menu command still works.",
                    bundle: localizationBundle,
                    commandTitle(command)
                )
            }
            return L10n.text(
                "settings.feedback.unavailable_multiple",
                defaultValue: "The shortcuts couldn’t be registered. "
                    + "Their menu commands still work.",
                bundle: localizationBundle
            )
        case .restoredDefaults:
            return L10n.text(
                "settings.feedback.restored",
                defaultValue: "Default shortcuts restored.",
                bundle: localizationBundle
            )
        }
    }
}

@MainActor
final class ShortcutSettingsController: NSWindowController, NSWindowDelegate {
    private let copy: ShortcutSettingsCopy
    private let contentModel: ShortcutSettingsModel
    private let onVisibilityChange: (Bool) -> Void

#if DEBUG
    var displayedConfiguration: GlobalShortcutConfiguration {
        contentModel.configuration
    }
    var displayedFeedback: ShortcutSettingsFeedback? {
        contentModel.feedback
    }
    var displayedRecordingCommand: GlobalShortcutCommand? {
        contentModel.recordingCommand
    }
    var displayedContentSize: NSSize {
        window?.contentView?.bounds.size ?? .zero
    }
    var usesSwiftUIHostingBoundary: Bool {
        window?.contentViewController is NSHostingController<ShortcutSettingsContentView>
    }
#endif

    init(
        preference: GlobalShortcutPreference = GlobalShortcutPreference(),
        localizationBundle: Bundle? = nil,
        onApply: @escaping ShortcutSettingsModel.ApplyConfiguration,
        onRecordingBegan: @escaping ShortcutSettingsModel.RecordingLifecycleAction = {},
        onRecordingCancelled: @escaping ShortcutSettingsModel.RecordingLifecycleAction = {},
        onVisibilityChange: @escaping (Bool) -> Void = { _ in }
    ) {
        copy = ShortcutSettingsCopy(localizationBundle: localizationBundle)
        contentModel = ShortcutSettingsModel(
            preference: preference,
            onRecordingBegan: onRecordingBegan,
            onRecordingCancelled: onRecordingCancelled,
            applyConfiguration: onApply
        )
        self.onVisibilityChange = onVisibilityChange
        let window = AppWindow(
            contentRect: NSRect(origin: .zero, size: ShortcutSettingsLayout.windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = copy.windowTitle
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior.insert(.moveToActiveSpace)
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: ShortcutSettingsContentView(
                model: contentModel,
                copy: copy
            )
        )
        window.setContentSize(ShortcutSettingsLayout.windowSize)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        configuration: GlobalShortcutConfiguration,
        failedRegistrationIDs: Set<UInt32>
    ) {
        contentModel.refresh(
            configuration: configuration,
            failedRegistrationIDs: failedRegistrationIDs
        )
        if window?.isVisible != true {
            onVisibilityChange(true)
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    func windowDidResignKey(_ notification: Notification) {
        contentModel.cancelRecording()
    }

    func windowWillClose(_ notification: Notification) {
        contentModel.cancelRecording()
        onVisibilityChange(false)
    }

#if DEBUG
    @discardableResult
    func captureForTesting(
        _ event: NSEvent,
        command: GlobalShortcutCommand
    ) -> Bool {
        contentModel.capture(event, for: command)
    }

    func restoreDefaultsForTesting() {
        contentModel.restoreDefaults()
    }

    func beginRecordingForTesting(_ command: GlobalShortcutCommand) {
        contentModel.beginRecording(command)
    }

    func cancelRecordingForTesting() {
        contentModel.cancelRecording()
    }
#endif
}

struct ShortcutSettingsContentView: View {
    @ObservedObject var model: ShortcutSettingsModel
    let copy: ShortcutSettingsCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(copy.title)
                    .font(.title2.weight(.semibold))
                Text(copy.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                shortcutRow(.render)
                Divider().padding(.leading, 16)
                shortcutRow(.showLastRender)
            }
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.75)
            }

            feedbackView
                .frame(
                    maxWidth: .infinity,
                    minHeight: ShortcutSettingsLayout.feedbackHeight,
                    maxHeight: ShortcutSettingsLayout.feedbackHeight,
                    alignment: .topLeading
                )

            HStack {
                Button {
                    model.restoreDefaults()
                } label: {
                    Text(copy.restoreDefaults)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ShortcutSettingsRestoreDefaults")
                Spacer()
            }
        }
        .padding(24)
        .frame(
            width: ShortcutSettingsLayout.windowSize.width,
            height: ShortcutSettingsLayout.windowSize.height,
            alignment: .topLeading
        )
    }

    private func shortcutRow(_ command: GlobalShortcutCommand) -> some View {
        let isUnavailable = model.failedRegistrationIDs.contains(command.rawValue)
        return HStack(spacing: 12) {
            Text(copy.commandTitle(command))
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)

            if isUnavailable {
                Label(copy.unavailable, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
                    .frame(width: 96, alignment: .trailing)
            } else {
                Color.clear
                    .frame(width: 96, height: 1)
                    .accessibilityHidden(true)
            }

            ShortcutRecorderView(
                shortcut: model.configuration[command],
                isRecording: model.recordingCommand == command,
                recordingTitle: copy.recording,
                accessibilityLabel: copy.recorderAccessibilityLabel(command),
                accessibilityHelp: copy.recordHelp,
                onBegin: { model.beginRecording(command) },
                onCancel: { model.cancelRecording() },
                onCapture: { _ = model.capture($0, for: command) }
            )
            .frame(width: 132, height: 30)
            .accessibilityIdentifier("ShortcutRecorder.\(command.rawValue)")
        }
        .padding(.horizontal, 16)
        .frame(height: ShortcutSettingsLayout.rowHeight)
    }

    @ViewBuilder
    private var feedbackView: some View {
        if let feedback = model.feedback {
            Label {
                Text(copy.feedbackText(feedback))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: feedback == .restoredDefaults
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill")
            }
            .font(.callout)
            .foregroundStyle(feedback == .restoredDefaults ? Color.secondary : Color.orange)
            .accessibilityIdentifier("ShortcutSettingsFeedback")
        } else {
            Text(copy.idleHelp)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let isRecording: Bool
    let recordingTitle: String
    let accessibilityLabel: String
    let accessibilityHelp: String
    let onBegin: () -> Void
    let onCancel: () -> Void
    let onCapture: (NSEvent) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        ShortcutRecorderControl()
    }

    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        control.configure(
            shortcut: shortcut,
            isRecording: isRecording,
            recordingTitle: recordingTitle,
            accessibilityLabel: accessibilityLabel,
            accessibilityHelp: accessibilityHelp,
            onBegin: onBegin,
            onCancel: onCancel,
            onCapture: onCapture
        )
    }
}

@MainActor
final class ShortcutRecorderControl: NSButton {
    private var isRecordingShortcut = false
    private var onBegin: () -> Void = {}
    private var onCancel: () -> Void = {}
    private var onCapture: (NSEvent) -> Void = { _ in }

    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        bezelStyle = .rounded
        controlSize = .regular
        font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        focusRingType = .exterior
        target = self
        action = #selector(toggleRecording)
        setButtonType(.momentaryPushIn)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        shortcut: GlobalShortcut,
        isRecording: Bool,
        recordingTitle: String,
        accessibilityLabel: String,
        accessibilityHelp: String,
        onBegin: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onCapture: @escaping (NSEvent) -> Void
    ) {
        isRecordingShortcut = isRecording
        self.onBegin = onBegin
        self.onCancel = onCancel
        self.onCapture = onCapture
        title = isRecording ? recordingTitle : shortcut.glyphs
        toolTip = accessibilityHelp
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityValue(isRecording ? recordingTitle : shortcut.accessibilityName)
        setAccessibilityHelp(accessibilityHelp)
        if isRecording {
            focusForRecording()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isRecordingShortcut {
            focusForRecording()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.keyDown(with: event)
            return
        }
        handleRecordingEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecordingShortcut, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        handleRecordingEvent(event)
        return true
    }

    @objc private func toggleRecording() {
        if isRecordingShortcut {
            isRecordingShortcut = false
            onCancel()
        } else {
            isRecordingShortcut = true
            window?.makeFirstResponder(self)
            onBegin()
        }
    }

    private func handleRecordingEvent(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        if Int(event.keyCode) == kVK_Escape {
            isRecordingShortcut = false
            onCancel()
        } else {
            onCapture(event)
        }
    }

    private func focusForRecording() {
        guard let window, window.firstResponder !== self else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, self.isRecordingShortcut else { return }
            window?.makeFirstResponder(self)
        }
    }
}
