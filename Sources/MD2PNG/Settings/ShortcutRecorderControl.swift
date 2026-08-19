import AppKit
import Carbon

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
        isBordered = false
        controlSize = .regular
        font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        focusRingType = .none
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
