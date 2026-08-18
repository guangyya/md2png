import AppKit

@MainActor
class AppWindow: NSWindow {
    enum Command: Equatable {
        case close
        case showSettings
    }

    var showSettingsHandler: (() -> Void)?

    static func appCommand(for event: NSEvent) -> Command? {
        guard event.type == .keyDown else { return nil }
        let relevantModifiers = event.modifierFlags.intersection([
            .command,
            .option,
            .control,
            .shift
        ])
        guard relevantModifiers == .command else { return nil }
        return switch event.charactersIgnoringModifiers?.lowercased() {
        case "w": .close
        case ",": .showSettings
        default: nil
        }
    }

    override func sendEvent(_ event: NSEvent) {
        switch Self.appCommand(for: event) {
        case .close:
            performClose(nil)
        case .showSettings:
            guard let showSettingsHandler else {
                super.sendEvent(event)
                return
            }
            showSettingsHandler()
        case nil:
            super.sendEvent(event)
        }
    }
}
