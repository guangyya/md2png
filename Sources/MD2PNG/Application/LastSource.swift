import Foundation

struct LastSourceState {
    private(set) var markdown: String?
    private(set) var ownedClipboardChangeCount: Int?

    var isAvailable: Bool {
        markdown != nil
    }

    mutating func recordSuccessfulRender(
        markdown: String,
        clipboardChangeCount: Int?
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
