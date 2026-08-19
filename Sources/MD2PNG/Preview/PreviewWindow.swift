import AppKit

final class PreviewCanvasView: NSView {
    override var isFlipped: Bool { true }
}

final class PreviewZoomStatusView: NSView {
    static let preferredSize = NSSize(width: 64, height: 22)

    override var intrinsicContentSize: NSSize { Self.preferredSize }
}

final class PreviewWindow: AppWindow {
    enum Command: Equatable {
        case close
        case copyAgain
        case savePNG
        case openInPreview
        case fit
        case actualSize
        case zoomIn
        case zoomOut
    }

    var commandHandler: ((Command) -> Void)?

    static func command(for event: NSEvent) -> Command? {
        guard event.type == .keyDown else { return nil }
        let relevantModifiers = event.modifierFlags.intersection([
            .command,
            .option,
            .control,
            .shift
        ])
        let characters = event.charactersIgnoringModifiers?.lowercased()
        if relevantModifiers == .command {
            return switch characters {
            case "w": .close
            case "c": .copyAgain
            case "s": .savePNG
            case "9": .fit
            case "0": .actualSize
            case "-": .zoomOut
            case "+", "=": .zoomIn
            default: nil
            }
        }
        if relevantModifiers == [.command, .shift], characters == "=" {
            return .zoomIn
        }
        return nil
    }

    static func isCloseShortcut(_ event: NSEvent) -> Bool {
        command(for: event) == .close
    }

    override func sendEvent(_ event: NSEvent) {
        guard let command = Self.command(for: event) else {
            super.sendEvent(event)
            return
        }
        if command == .close {
            performClose(nil)
        } else {
            commandHandler?(command)
        }
    }
}
