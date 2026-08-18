import AppKit

@MainActor
enum AlertKeyboard {
    static func configureDefaultAndCancel(
        in alert: NSAlert,
        defaultButton: NSButton,
        cancelButton: NSButton
    ) {
        defaultButton.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1b}"
        alert.window.defaultButtonCell = defaultButton.cell as? NSButtonCell
    }
}
