import AppKit

final class PreviewCanvasView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    var imageFrame: NSRect = .zero {
        didSet {
            guard imageFrame != oldValue else { return }
            needsDisplay = true
        }
    }

    var imageCornerRadius: CGFloat = 0 {
        didSet {
            guard imageCornerRadius != oldValue else { return }
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        dirtyRect.fill()

        guard !imageFrame.isEmpty else { return }
        let scale = max(1, window?.backingScaleFactor ?? 1)
        let lineWidth = 1 / scale
        let outlineRect = imageFrame.insetBy(
            dx: -lineWidth / 2,
            dy: -lineWidth / 2
        )
        let outline = if imageCornerRadius > 0 {
            NSBezierPath(
                roundedRect: outlineRect,
                xRadius: imageCornerRadius + lineWidth / 2,
                yRadius: imageCornerRadius + lineWidth / 2
            )
        } else {
            NSBezierPath(rect: outlineRect)
        }
        outline.lineWidth = lineWidth

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.separatorColor.setStroke()
        outline.stroke()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.setStroke()
        outline.stroke()
    }
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
