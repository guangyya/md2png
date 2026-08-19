import AppKit
import UniformTypeIdentifiers

@MainActor
final class PreviewController: NSWindowController, NSWindowDelegate {
    private let imageView = PreviewDragImageView()
    private let canvasView = PreviewCanvasView()
    private let scrollView = NSScrollView()
    private let copyImage: (NSImage) throws -> Int
    private let onCopied: (Int) -> Void
    private let onError: (Error) -> Void
    private let onVisibilityChange: (Bool) -> Void
    private let temporaryImageStore: PreviewTemporaryImageStore
    private let dragExportStore: PreviewDragExportStore
    private let openFileInPreview: PreviewFileOpener
    private var zoomMode: PreviewZoomMode = .fit
    private var currentZoomFactor: CGFloat = 1
    private var suggestedPNGFilename = "md2png-render.png"
    private var dragGenerationID = UUID()

    private lazy var toolbarController = PreviewToolbarController(
        onCommand: { [weak self] command in
            self?.perform(command)
        },
        hasImage: { [weak self] in
            self?.imageView.image != nil
        },
        zoomFactor: { [weak self] in
            self?.currentZoomFactor ?? 1
        }
    )

    private static let zoomSteps: [CGFloat] = [0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4]

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
    var previewZoomMode: PreviewZoomMode { zoomMode }
    var previewZoomFactor: CGFloat { currentZoomFactor }
    var previewWindowTitle: String? { window?.title }
    var previewHasHorizontalScroller: Bool { scrollView.hasHorizontalScroller }
    var previewScrollerStyle: NSScroller.Style { scrollView.scrollerStyle }
    var previewZoomStatus: String { toolbarController.zoomStatus }
    var previewZoomAccessibilityLabel: String? { toolbarController.zoomAccessibilityLabel }
    var previewZoomAccessibilityValue: String? {
        toolbarController.zoomAccessibilityValue
    }
    var previewZoomAccessibilityHelp: String? { toolbarController.zoomAccessibilityHelp }
    var previewImageAccessibilityRole: NSAccessibility.Role? { imageView.accessibilityRole() }
    var previewImageAccessibilityLabel: String? { imageView.accessibilityLabel() }
    var previewImageAccessibilityValue: String? {
        imageView.accessibilityValue() as? String
    }
    var previewImageAccessibilityHelp: String? { imageView.accessibilityHelp() }
    var previewSuggestedPNGFilename: String { suggestedPNGFilename }
    var previewZoomStatusContainerSize: NSSize { toolbarController.zoomStatusContainerSize }
    var previewToolbarStyle: NSWindow.ToolbarStyle? { window?.toolbarStyle }
    var previewSelectedToolbarIdentifier: NSToolbarItem.Identifier? {
        window?.toolbar?.selectedItemIdentifier
    }
    var previewToolbarLabels: [String] {
        window?.toolbar?.items.map(\.label).filter { !$0.isEmpty } ?? []
    }
    var previewToolbarIconSizes: [NSSize] {
        window?.toolbar?.items.compactMap { $0.image?.size } ?? []
    }
    func selectFitForTesting() { selectFit(nil) }
    func selectActualSizeForTesting() { selectActualSize(nil) }
    func zoomInForTesting() { zoomIn(nil) }
    func zoomOutForTesting() { zoomOut(nil) }
    func clickZoomStatusForTesting() { toolbarController.clickZoomStatusForTesting() }
    func toolbarDefaultItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        toolbarController.toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbarSelectableItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        toolbarController.toolbarSelectableItemIdentifiers(toolbar)
    }
    func openInPreviewForTesting() { openInPreview(nil) }
    func dragExportForTesting() throws -> PreviewDragExport? {
        try makeDragExport()
    }
    func renderedImageSnapshot() -> NSBitmapImageRep? {
        imageView.displayIfNeeded()
        guard let bitmap = imageView.bitmapImageRepForCachingDisplay(in: imageView.bounds) else {
            return nil
        }
        imageView.cacheDisplay(in: imageView.bounds, to: bitmap)
        return bitmap
    }
#endif

    init(
        copyImage: @escaping (NSImage) throws -> Int = { try Clipboard.write(image: $0) },
        onCopied: @escaping (Int) -> Void = { _ in },
        onError: @escaping (Error) -> Void = { _ in },
        onVisibilityChange: @escaping (Bool) -> Void = { _ in },
        onShowSettings: @escaping () -> Void = {},
        temporaryImageStore: PreviewTemporaryImageStore = PreviewTemporaryImageStore(),
        dragExportStore: PreviewDragExportStore = PreviewDragExportStore(),
        openFileInPreview: @escaping PreviewFileOpener = { url, completion in
            try PreviewWorkspaceOpener.open(url, completion: completion)
        }
    ) {
        self.copyImage = copyImage
        self.onCopied = onCopied
        self.onError = onError
        self.onVisibilityChange = onVisibilityChange
        self.temporaryImageStore = temporaryImageStore
        self.dragExportStore = dragExportStore
        self.openFileInPreview = openFileInPreview
        let window = PreviewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(
            "preview.window_title",
            defaultValue: "Preview"
        )
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.showSettingsHandler = onShowSettings
        window.commandHandler = { [weak self] command in
            self?.perform(command)
        }

        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.setAccessibilityElement(true)
        imageView.setAccessibilityRole(.image)
        imageView.setAccessibilityLabel(L10n.text(
            "preview.rendered_image",
            defaultValue: "Rendered image"
        ))
        let dragHelp = L10n.text(
            "preview.drag_help",
            defaultValue: "Drag to export this PNG to another app or folder."
        )
        imageView.setAccessibilityHelp(dragHelp)
        imageView.toolTip = dragHelp
        imageView.draggingItemProvider = { [weak self, weak imageView] event in
            guard let self, let imageView else { return nil }
            let location = imageView.convert(event.locationInWindow, from: nil)
            return try self.makeDraggingItem(at: location)
        }
        imageView.draggingErrorHandler = { [weak self] error in
            self?.onError(error)
        }
        imageView.draggingSessionEnded = { [weak self] exportID, operation in
            self?.dragExportStore.finishExport(exportID, operation: operation)
        }
        canvasView.addSubview(imageView)

        scrollView.frame = window.contentView!.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = canvasView
        window.contentView = scrollView

        toolbarController.install(on: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        image: NSImage,
        widthPreset: RenderWidthPreset? = nil,
        markdown: String? = nil
    ) {
        let isBecomingVisible = window?.isVisible != true
        if imageView.image !== image {
            temporaryImageStore.clear()
        }
        dragGenerationID = UUID()
        imageView.image = image
        updateImageAccessibilityValue(image)
        suggestedPNGFilename = SuggestedPNGFilename.make(from: markdown)
        zoomMode = .fit
        updateWindowTitle(image: image, widthPreset: widthPreset)
        if window?.isVisible != true {
            resizeWindowToReflectImageWidth(image)
        }
        if isBecomingVisible {
            onVisibilityChange(true)
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        updateLayout(scrollToTop: true)
        toolbarController.validateVisibleItems()
    }

    func windowDidResize(_ notification: Notification) {
        updateLayout(scrollToTop: false, preserveAnchor: true)
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        updateLayout(scrollToTop: false, preserveAnchor: true)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        updateLayout(scrollToTop: false, preserveAnchor: true)
    }

    func windowWillClose(_ notification: Notification) {
        onVisibilityChange(false)
    }

    private func updateWindowTitle(
        image: NSImage,
        widthPreset: RenderWidthPreset?
    ) {
        let pixelSize = RenderedImageExport.pixelSize(of: image)
        if let widthPreset {
            window?.title = L10n.format(
                "preview.window_title_with_width",
                defaultValue: "Preview — %1$@ · %2$ld × %3$ld px",
                widthPreset.menuTitle,
                Int(pixelSize.width.rounded()),
                Int(pixelSize.height.rounded())
            )
        } else {
            window?.title = L10n.format(
                "preview.window_title_with_dimensions",
                defaultValue: "Preview — %1$ld × %2$ld px",
                Int(pixelSize.width.rounded()),
                Int(pixelSize.height.rounded())
            )
        }
    }

    private func updateImageAccessibilityValue(_ image: NSImage) {
        let pixelSize = RenderedImageExport.pixelSize(of: image)
        imageView.setAccessibilityValue(L10n.format(
            "preview.rendered_image_dimensions",
            defaultValue: "%1$ld × %2$ld pixels",
            Int(pixelSize.width.rounded()),
            Int(pixelSize.height.rounded())
        ))
    }

    private func makeDragExport() throws -> PreviewDragExport? {
        guard let image = imageView.image else { return nil }
        return try dragExportStore.export(
            image: image,
            generationID: dragGenerationID,
            suggestedFilename: suggestedPNGFilename
        )
    }

    private func makeDraggingItem(at location: NSPoint) throws -> PreviewDraggingItem? {
        guard let image = imageView.image else { return nil }
        let export = try dragExportStore.export(
            image: image,
            generationID: dragGenerationID,
            suggestedFilename: suggestedPNGFilename
        )
        do {
            return try PreviewDragItemFactory.makeDraggingItem(
                export: export,
                image: image,
                location: location
            )
        } catch {
            dragExportStore.finishExport(export.id, operation: [])
            throw error
        }
    }

    private func resizeWindowToReflectImageWidth(_ image: NSImage) {
        guard let window,
              let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            return
        }
        let layout = PreviewWindowLayout.calculate(
            imageSize: image.size,
            visibleScreenSize: visibleFrame.size
        )
        window.setContentSize(layout.contentSize)
        let centeredOrigin = NSPoint(
            x: visibleFrame.midX - window.frame.width / 2,
            y: visibleFrame.midY - window.frame.height / 2
        )
        window.setFrameOrigin(centeredOrigin)
    }

    private func updateLayout(
        scrollToTop: Bool,
        preserveAnchor: Bool = false
    ) {
        guard let image = imageView.image else { return }
        let oldAnchor = preserveAnchor ? visibleImageAnchor() : nil
        let layout = PreviewLayout.calculate(
            imagePixelSize: RenderedImageExport.pixelSize(of: image),
            backingScaleFactor: window?.backingScaleFactor ?? 1,
            viewportSize: scrollView.contentSize,
            zoomMode: zoomMode
        )
        canvasView.frame = NSRect(origin: .zero, size: layout.canvasSize)
        imageView.frame = layout.imageFrame
        currentZoomFactor = layout.zoomFactor
        toolbarController.updateZoomStatus(currentZoomFactor)

        if scrollToTop {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else if let oldAnchor {
            scroll(toImageAnchor: oldAnchor)
        }
        toolbarController.validateVisibleItems()
    }

    private func visibleImageAnchor() -> NSPoint? {
        guard imageView.frame.width > 0, imageView.frame.height > 0 else { return nil }
        let visibleCenter = NSPoint(
            x: scrollView.documentVisibleRect.midX,
            y: scrollView.documentVisibleRect.midY
        )
        return NSPoint(
            x: min(max((visibleCenter.x - imageView.frame.minX) / imageView.frame.width, 0), 1),
            y: min(max((visibleCenter.y - imageView.frame.minY) / imageView.frame.height, 0), 1)
        )
    }

    private func scroll(toImageAnchor anchor: NSPoint) {
        let targetCenter = NSPoint(
            x: imageView.frame.minX + imageView.frame.width * anchor.x,
            y: imageView.frame.minY + imageView.frame.height * anchor.y
        )
        let viewportSize = scrollView.contentSize
        let maximumOrigin = NSPoint(
            x: max(0, canvasView.frame.width - viewportSize.width),
            y: max(0, canvasView.frame.height - viewportSize.height)
        )
        let origin = NSPoint(
            x: min(max(targetCenter.x - viewportSize.width / 2, 0), maximumOrigin.x),
            y: min(max(targetCenter.y - viewportSize.height / 2, 0), maximumOrigin.y)
        )
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func perform(_ command: PreviewWindow.Command) {
        switch command {
        case .close:
            window?.performClose(nil)
        case .copyAgain:
            copyAgain(nil)
        case .savePNG:
            savePNG(nil)
        case .openInPreview:
            openInPreview(nil)
        case .fit:
            selectFit(nil)
        case .actualSize:
            selectActualSize(nil)
        case .zoomIn:
            zoomIn(nil)
        case .zoomOut:
            zoomOut(nil)
        }
    }

    @objc private func copyAgain(_ sender: Any?) {
        guard let image = imageView.image else { return }
        do {
            onCopied(try copyImage(image))
        } catch {
            onError(error)
        }
    }

    @objc private func savePNG(_ sender: Any?) {
        guard let image = imageView.image, let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedPNGFilename
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try RenderedImageExport.writePNG(image, to: url)
            } catch {
                self?.onError(error)
            }
        }
    }

    @objc private func openInPreview(_ sender: Any?) {
        guard let image = imageView.image else { return }
        do {
            let url = try temporaryImageStore.replace(with: image)
            try openFileInPreview(url) { [weak self] succeeded in
                guard !succeeded else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.temporaryImageStore.clear(ifCurrentFileURL: url) else { return }
                    self.onError(AppError.previewOpenFailed)
                }
            }
        } catch AppError.pngEncodingFailed {
            temporaryImageStore.clear()
            onError(AppError.pngEncodingFailed)
        } catch {
            temporaryImageStore.clear()
            onError(AppError.previewOpenFailed)
        }
    }

    @objc private func selectFit(_ sender: Any?) {
        guard zoomMode != .fit else { return }
        zoomMode = .fit
        updateLayout(scrollToTop: true)
    }

    @objc private func selectActualSize(_ sender: Any?) {
        guard zoomMode != .actualSize else { return }
        zoomMode = .actualSize
        updateLayout(scrollToTop: false, preserveAnchor: true)
    }

    @objc private func zoomIn(_ sender: Any?) {
        guard let next = Self.zoomSteps.first(where: { $0 > currentZoomFactor + 0.001 }) else {
            return
        }
        zoomMode = .custom(next)
        updateLayout(scrollToTop: false, preserveAnchor: true)
    }

    @objc private func zoomOut(_ sender: Any?) {
        guard let next = Self.zoomSteps.last(where: { $0 < currentZoomFactor - 0.001 }) else {
            return
        }
        zoomMode = .custom(next)
        updateLayout(scrollToTop: false, preserveAnchor: true)
    }

}
