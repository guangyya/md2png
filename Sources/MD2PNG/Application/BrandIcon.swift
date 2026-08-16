import AppKit

enum BrandIcon {
    static func statusBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let sourceLines = NSBezierPath()
            sourceLines.lineWidth = 1.45
            sourceLines.lineCapStyle = .round
            for y in [12.5, 9.0, 5.5] {
                sourceLines.move(to: NSPoint(x: 1.1, y: y))
                sourceLines.line(to: NSPoint(x: 5.4, y: y))
            }
            sourceLines.stroke()

            let arrow = NSBezierPath()
            arrow.lineWidth = 1.45
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.move(to: NSPoint(x: 5.5, y: 9.0))
            arrow.line(to: NSPoint(x: 9.2, y: 9.0))
            arrow.move(to: NSPoint(x: 7.4, y: 11.1))
            arrow.line(to: NSPoint(x: 9.5, y: 9.0))
            arrow.line(to: NSPoint(x: 7.4, y: 6.9))
            arrow.stroke()

            let frame = NSBezierPath(
                roundedRect: NSRect(x: 10.4, y: 4.4, width: 6.5, height: 9.2),
                xRadius: 1.35,
                yRadius: 1.35
            )
            frame.lineWidth = 1.4
            frame.stroke()

            NSBezierPath(ovalIn: NSRect(x: 12.0, y: 10.5, width: 1.2, height: 1.2)).fill()

            let landscape = NSBezierPath()
            landscape.lineWidth = 1.25
            landscape.lineCapStyle = .round
            landscape.lineJoinStyle = .round
            landscape.move(to: NSPoint(x: 11.4, y: 6.0))
            landscape.line(to: NSPoint(x: 13.1, y: 8.0))
            landscape.line(to: NSPoint(x: 14.0, y: 7.2))
            landscape.line(to: NSPoint(x: 15.8, y: 9.2))
            landscape.stroke()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = L10n.text(
            "accessibility.app",
            defaultValue: "md2png"
        )
        return image
    }
}
