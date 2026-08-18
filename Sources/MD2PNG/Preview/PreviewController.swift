import AppKit
import UniformTypeIdentifiers

typealias PreviewFileOpenCompletion = @Sendable (Bool) -> Void
typealias PreviewFileOpener = @MainActor (
    URL,
    @escaping PreviewFileOpenCompletion
) throws -> Void

enum PreviewWorkspaceOpener {
    static func open(
        _ url: URL,
        completion: @escaping PreviewFileOpenCompletion
    ) throws {
        guard let previewURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Preview"
        ) else {
            throw AppError.previewOpenFailed
        }
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: previewURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            completion(error == nil)
        }
    }
}

enum PreviewZoomMode: Equatable {
    case fit
    case actualSize
    case custom(CGFloat)
}

struct PreviewLayout {
    let canvasSize: NSSize
    let imageFrame: NSRect
    let zoomFactor: CGFloat

    static let minimumZoomFactor: CGFloat = 0.25
    static let maximumZoomFactor: CGFloat = 4

    static func calculate(
        imagePixelSize: NSSize,
        backingScaleFactor: CGFloat,
        viewportSize: NSSize,
        zoomMode: PreviewZoomMode,
        padding: CGFloat = 24
    ) -> PreviewLayout {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            return PreviewLayout(canvasSize: viewportSize, imageFrame: .zero, zoomFactor: 1)
        }

        let safeBackingScale = max(1, backingScaleFactor)
        let actualSize = NSSize(
            width: imagePixelSize.width / safeBackingScale,
            height: imagePixelSize.height / safeBackingScale
        )
        let availableWidth = max(1, viewportSize.width - padding * 2)
        let fitFactor = min(maximumZoomFactor, availableWidth / actualSize.width)
        let zoomFactor = switch zoomMode {
        case .fit:
            fitFactor
        case .actualSize:
            CGFloat(1)
        case let .custom(factor):
            min(max(factor, minimumZoomFactor), maximumZoomFactor)
        }
        let displayedSize = NSSize(
            width: actualSize.width * zoomFactor,
            height: actualSize.height * zoomFactor
        )
        let canvasSize = NSSize(
            width: max(viewportSize.width, displayedSize.width + padding * 2),
            height: max(viewportSize.height, displayedSize.height + padding * 2)
        )
        let imageOrigin = NSPoint(
            x: canvasSize.width > viewportSize.width
                ? padding
                : (canvasSize.width - displayedSize.width) / 2,
            y: canvasSize.height > viewportSize.height
                ? padding
                : (canvasSize.height - displayedSize.height) / 2
        )
        return PreviewLayout(
            canvasSize: canvasSize,
            imageFrame: NSRect(origin: imageOrigin, size: displayedSize),
            zoomFactor: zoomFactor
        )
    }

    static func calculate(
        imageSize: NSSize,
        viewportSize: NSSize,
        padding: CGFloat = 24
    ) -> PreviewLayout {
        calculate(
            imagePixelSize: imageSize,
            backingScaleFactor: 1,
            viewportSize: viewportSize,
            zoomMode: .fit,
            padding: padding
        )
    }
}

struct PreviewWindowLayout {
    let contentSize: NSSize

    static func calculate(
        imageSize: NSSize,
        visibleScreenSize: NSSize,
        horizontalImagePadding: CGFloat = 48,
        horizontalScreenMargin: CGFloat = 80,
        verticalScreenMargin: CGFloat = 120,
        minimumContentWidth: CGFloat = 520,
        preferredContentHeight: CGFloat = 640
    ) -> PreviewWindowLayout {
        let maximumContentWidth = max(
            1,
            visibleScreenSize.width - horizontalScreenMargin
        )
        let minimumWidth = min(minimumContentWidth, maximumContentWidth)
        let desiredWidth = max(
            minimumWidth,
            imageSize.width + horizontalImagePadding
        )
        let maximumContentHeight = max(
            1,
            visibleScreenSize.height - verticalScreenMargin
        )
        return PreviewWindowLayout(contentSize: NSSize(
            width: min(desiredWidth, maximumContentWidth),
            height: min(preferredContentHeight, maximumContentHeight)
        ))
    }
}

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

@MainActor
final class PreviewController: NSWindowController, NSWindowDelegate,
    NSToolbarDelegate, NSToolbarItemValidation {
    private let imageView = NSImageView()
    private let canvasView = PreviewCanvasView()
    private let scrollView = NSScrollView()
    private let zoomStatusButton = NSButton()
    private let zoomStatusContainer = PreviewZoomStatusView(
        frame: NSRect(origin: .zero, size: PreviewZoomStatusView.preferredSize)
    )
    private let copyImage: (NSImage) throws -> Int
    private let onCopied: (Int) -> Void
    private let onError: (Error) -> Void
    private let onVisibilityChange: (Bool) -> Void
    private let temporaryImageStore: PreviewTemporaryImageStore
    private let openFileInPreview: PreviewFileOpener
    private var zoomMode: PreviewZoomMode = .fit
    private var currentZoomFactor: CGFloat = 1
    private var suggestedPNGFilename = "md2png-render.png"

    private static let zoomSteps: [CGFloat] = [0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4]
    private enum ToolbarIdentifier {
        static let copyAgain = NSToolbarItem.Identifier("preview.copy-again")
        static let savePNG = NSToolbarItem.Identifier("preview.save-png")
        static let openInPreview = NSToolbarItem.Identifier("preview.open-in-preview")
        static let fit = NSToolbarItem.Identifier("preview.fit")
        static let zoomOut = NSToolbarItem.Identifier("preview.zoom-out")
        static let zoomStatus = NSToolbarItem.Identifier("preview.zoom-status")
        static let zoomIn = NSToolbarItem.Identifier("preview.zoom-in")
    }

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
    var previewZoomStatus: String { zoomStatusButton.title }
    var previewSuggestedPNGFilename: String { suggestedPNGFilename }
    var previewZoomStatusContainerSize: NSSize { zoomStatusContainer.frame.size }
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
    func clickZoomStatusForTesting() { zoomStatusButton.performClick(nil) }
    func openInPreviewForTesting() { openInPreview(nil) }
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
        openFileInPreview: @escaping PreviewFileOpener = { url, completion in
            try PreviewWorkspaceOpener.open(url, completion: completion)
        }
    ) {
        self.copyImage = copyImage
        self.onCopied = onCopied
        self.onError = onError
        self.onVisibilityChange = onVisibilityChange
        self.temporaryImageStore = temporaryImageStore
        self.openFileInPreview = openFileInPreview
        let window = PreviewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(
            "preview.window_title",
            defaultValue: "Last Render"
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

        let toolbar = NSToolbar(identifier: "preview.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .expanded
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
        imageView.image = image
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
        window?.toolbar?.validateVisibleItems()
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
                defaultValue: "Last Render — %1$@ · %2$ld × %3$ld px",
                widthPreset.menuTitle,
                Int(pixelSize.width.rounded()),
                Int(pixelSize.height.rounded())
            )
        } else {
            window?.title = L10n.format(
                "preview.window_title_with_dimensions",
                defaultValue: "Last Render — %1$ld × %2$ld px",
                Int(pixelSize.width.rounded()),
                Int(pixelSize.height.rounded())
            )
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
        updateZoomStatus()

        if scrollToTop {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else if let oldAnchor {
            scroll(toImageAnchor: oldAnchor)
        }
        window?.toolbar?.validateVisibleItems()
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

    private func updateZoomStatus() {
        zoomStatusButton.title = L10n.format(
            "preview.zoom_percent",
            defaultValue: "%ld%%",
            Int((currentZoomFactor * 100).rounded())
        )
        window?.toolbar?.selectedItemIdentifier = nil
        zoomStatusButton.setAccessibilityLabel(L10n.text(
            "preview.actual_size",
            defaultValue: "Actual Size"
        ))
    }

    private func perform(_ command: PreviewWindow.Command) {
        switch command {
        case .close:
            window?.performClose(nil)
        case .copyAgain:
            copyAgain(nil)
        case .savePNG:
            savePNG(nil)
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

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarIdentifier.copyAgain,
            ToolbarIdentifier.savePNG,
            ToolbarIdentifier.openInPreview,
            .flexibleSpace,
            ToolbarIdentifier.fit,
            ToolbarIdentifier.zoomOut,
            ToolbarIdentifier.zoomStatus,
            ToolbarIdentifier.zoomIn
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarIdentifier.copyAgain,
            ToolbarIdentifier.savePNG,
            ToolbarIdentifier.openInPreview,
            .flexibleSpace,
            ToolbarIdentifier.fit,
            ToolbarIdentifier.zoomOut,
            ToolbarIdentifier.zoomStatus,
            ToolbarIdentifier.zoomIn
        ]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        []
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarIdentifier.copyAgain:
            return toolbarItem(
                identifier: itemIdentifier,
                labelKey: "preview.copy_again",
                label: "Copy Again",
                symbol: "square.on.square",
                action: #selector(copyAgain(_:))
            )
        case ToolbarIdentifier.savePNG:
            return toolbarItem(
                identifier: itemIdentifier,
                labelKey: "preview.save_png",
                label: "Save PNG…",
                symbol: "square.and.arrow.down",
                action: #selector(savePNG(_:))
            )
        case ToolbarIdentifier.openInPreview:
            return toolbarItem(
                identifier: itemIdentifier,
                labelKey: "preview.open_in_preview",
                label: "Open in Preview",
                symbol: "arrow.up.forward.square",
                action: #selector(openInPreview(_:))
            )
        case ToolbarIdentifier.fit:
            return toolbarItem(
                identifier: itemIdentifier,
                labelKey: "preview.fit",
                label: "Fit to Window",
                symbol: "arrow.down.right.and.arrow.up.left",
                action: #selector(selectFit(_:))
            )
        case ToolbarIdentifier.zoomOut:
            return toolbarItem(
                identifier: itemIdentifier,
                labelKey: "preview.zoom_out",
                label: "Zoom Out",
                symbol: "minus.magnifyingglass",
                action: #selector(zoomOut(_:))
            )
        case ToolbarIdentifier.zoomStatus:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = L10n.text("preview.zoom_level", defaultValue: "Preview zoom")
            zoomStatusButton.frame = zoomStatusContainer.bounds
            zoomStatusButton.autoresizingMask = [.width, .height]
            zoomStatusButton.bezelStyle = .inline
            zoomStatusButton.font = NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.smallSystemFontSize,
                weight: .regular
            )
            zoomStatusButton.target = self
            zoomStatusButton.action = #selector(selectActualSize(_:))
            zoomStatusButton.toolTip = L10n.text(
                "preview.actual_size",
                defaultValue: "Actual Size"
            )
            if zoomStatusButton.superview !== zoomStatusContainer {
                zoomStatusContainer.addSubview(zoomStatusButton)
            }
            item.view = zoomStatusContainer
            return item
        case ToolbarIdentifier.zoomIn:
            return toolbarItem(
                identifier: itemIdentifier,
                labelKey: "preview.zoom_in",
                label: "Zoom In",
                symbol: "plus.magnifyingglass",
                action: #selector(zoomIn(_:))
            )
        default:
            return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard imageView.image != nil else { return false }
        switch item.itemIdentifier {
        case ToolbarIdentifier.zoomIn:
            return currentZoomFactor < PreviewLayout.maximumZoomFactor - 0.001
        case ToolbarIdentifier.zoomOut:
            return currentZoomFactor > PreviewLayout.minimumZoomFactor + 0.001
        default:
            return true
        }
    }

    private func toolbarItem(
        identifier: NSToolbarItem.Identifier,
        labelKey: String,
        label: String,
        symbol: String,
        action: Selector
    ) -> NSToolbarItem {
        let localizedLabel = L10n.text(labelKey, defaultValue: label)
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = localizedLabel
        item.paletteLabel = localizedLabel
        item.toolTip = localizedLabel
        item.image = toolbarSymbol(named: symbol, accessibilityDescription: localizedLabel)
        item.target = self
        item.action = action
        return item
    }

    private func toolbarSymbol(
        named name: String,
        accessibilityDescription: String
    ) -> NSImage? {
        guard let symbol = NSImage(
            systemSymbolName: name,
            accessibilityDescription: accessibilityDescription
        ) else {
            return nil
        }
        let configuration = NSImage.SymbolConfiguration(
            pointSize: 14,
            weight: .regular,
            scale: .medium
        )
        return symbol.withSymbolConfiguration(configuration) ?? symbol
    }
}
