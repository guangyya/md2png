import AppKit

struct PreviewLayout {
    let canvasSize: NSSize
    let imageFrame: NSRect

    static func calculate(
        imageSize: NSSize,
        viewportSize: NSSize,
        padding: CGFloat = 24
    ) -> PreviewLayout {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return PreviewLayout(canvasSize: viewportSize, imageFrame: .zero)
        }

        let availableWidth = max(1, viewportSize.width - padding * 2)
        let scale = min(1, availableWidth / imageSize.width)
        let displayedSize = NSSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let canvasSize = NSSize(
            width: max(viewportSize.width, displayedSize.width + padding * 2),
            height: max(viewportSize.height, displayedSize.height + padding * 2)
        )
        let imageOrigin = NSPoint(
            x: (canvasSize.width - displayedSize.width) / 2,
            y: canvasSize.height > viewportSize.height
                ? padding
                : (canvasSize.height - displayedSize.height) / 2
        )
        return PreviewLayout(
            canvasSize: canvasSize,
            imageFrame: NSRect(origin: imageOrigin, size: displayedSize)
        )
    }
}

final class PreviewCanvasView: NSView {
    override var isFlipped: Bool { true }
}

final class PreviewWindow: NSWindow {
    static func isCloseShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.charactersIgnoringModifiers?.lowercased() == "w" else {
            return false
        }
        let relevantModifiers = event.modifierFlags.intersection([
            .command,
            .option,
            .control,
            .shift
        ])
        return relevantModifiers == .command
    }

    override func sendEvent(_ event: NSEvent) {
        if Self.isCloseShortcut(event) {
            performClose(nil)
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class PreviewController: NSWindowController, NSWindowDelegate {
    private let imageView = NSImageView()
    private let canvasView = PreviewCanvasView()
    private let scrollView = NSScrollView()

#if DEBUG
    var displayedImageFrame: NSRect { imageView.frame }
    var previewCanvasSize: NSSize { canvasView.frame.size }
    var previewViewportSize: NSSize { scrollView.contentSize }
    var visibleDocumentOrigin: NSPoint { scrollView.contentView.bounds.origin }
    var displayedImage: NSImage? { imageView.image }
    var displayedImageVisibleRect: NSRect { imageView.visibleRect }
    var documentVisibleRect: NSRect { scrollView.documentVisibleRect }
    var canvasUsesAutoLayout: Bool { !canvasView.translatesAutoresizingMaskIntoConstraints }
    var imageIsAttachedToWindow: Bool { imageView.window === window }

    func renderedImageSnapshot() -> NSBitmapImageRep? {
        imageView.displayIfNeeded()
        guard let bitmap = imageView.bitmapImageRepForCachingDisplay(in: imageView.bounds) else {
            return nil
        }
        imageView.cacheDisplay(in: imageView.bounds, to: bitmap)
        return bitmap
    }
#endif

    init() {
        let window = PreviewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(
            "preview.window_title",
            defaultValue: "Last Markdown Render"
        )
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        canvasView.addSubview(imageView)

        scrollView.frame = window.contentView!.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = canvasView
        window.contentView = scrollView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(image: NSImage) {
        imageView.image = image
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        updateLayout(scrollToTop: true)
    }

    func windowDidResize(_ notification: Notification) {
        updateLayout(scrollToTop: false)
    }

    private func updateLayout(scrollToTop: Bool) {
        guard let image = imageView.image else { return }
        let layout = PreviewLayout.calculate(
            imageSize: image.size,
            viewportSize: scrollView.contentSize
        )
        canvasView.frame = NSRect(origin: .zero, size: layout.canvasSize)
        imageView.frame = layout.imageFrame

        if scrollToTop {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
