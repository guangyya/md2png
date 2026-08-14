import Foundation

struct LastSourceState {
    private(set) var markdown: String?
    private(set) var ownedClipboardChangeCount: Int?

    var isAvailable: Bool {
        markdown != nil
    }

    mutating func recordSuccessfulRender(
        markdown: String,
        clipboardChangeCount: Int
    ) {
        self.markdown = markdown
        ownedClipboardChangeCount = clipboardChangeCount
    }

    mutating func recordOwnedClipboardWrite(changeCount: Int) {
        guard isAvailable else { return }
        ownedClipboardChangeCount = changeCount
    }

    func requiresConfirmation(currentClipboardChangeCount: Int) -> Bool {
        guard isAvailable else { return false }
        return ownedClipboardChangeCount != currentClipboardChangeCount
    }
}

enum LastSourceOverwriteAction {
    case rerender
    case restore

    func confirmationMessage(bundle: Bundle? = nil) -> String {
        switch self {
        case .rerender:
            return L10n.text(
                "confirmation.clipboard_changed.rerender",
                defaultValue: "Another app changed the clipboard. Replace it with " +
                    "a newly rendered image from the last Markdown?",
                bundle: bundle
            )
        case .restore:
            return L10n.text(
                "confirmation.clipboard_changed.restore",
                defaultValue: "Another app changed the clipboard. Replace it with the last Markdown?",
                bundle: bundle
            )
        }
    }
}
