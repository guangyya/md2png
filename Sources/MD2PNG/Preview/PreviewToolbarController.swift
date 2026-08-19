import AppKit

@MainActor
final class PreviewToolbarController: NSObject, NSToolbarDelegate,
    NSToolbarItemValidation {
    private enum Identifier {
        static let copyImage = NSToolbarItem.Identifier("preview.copy")
        static let savePNG = NSToolbarItem.Identifier("preview.save-png")
        static let openInPreview = NSToolbarItem.Identifier("preview.open-in-preview")
        static let fit = NSToolbarItem.Identifier("preview.fit")
        static let zoomOut = NSToolbarItem.Identifier("preview.zoom-out")
        static let zoomStatus = NSToolbarItem.Identifier("preview.zoom-status")
        static let zoomIn = NSToolbarItem.Identifier("preview.zoom-in")
    }

    private let zoomStatusButton = NSButton()
    private let zoomStatusContainer = PreviewZoomStatusView(
        frame: NSRect(origin: .zero, size: PreviewZoomStatusView.preferredSize)
    )
    private let onCommand: (PreviewWindow.Command) -> Void
    private let hasImage: () -> Bool
    private let zoomFactor: () -> CGFloat
    private weak var toolbar: NSToolbar?

    init(
        onCommand: @escaping (PreviewWindow.Command) -> Void,
        hasImage: @escaping () -> Bool,
        zoomFactor: @escaping () -> CGFloat
    ) {
        self.onCommand = onCommand
        self.hasImage = hasImage
        self.zoomFactor = zoomFactor
        super.init()
    }

    func install(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "preview.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .expanded
        self.toolbar = toolbar
    }

    func updateZoomStatus(_ zoomFactor: CGFloat) {
        zoomStatusButton.title = L10n.format(
            "preview.zoom_percent",
            defaultValue: "%ld%%",
            Int((zoomFactor * 100).rounded())
        )
        toolbar?.selectedItemIdentifier = nil
        zoomStatusButton.setAccessibilityLabel(L10n.text(
            "preview.zoom_level",
            defaultValue: "Preview zoom"
        ))
        zoomStatusButton.setAccessibilityValue(zoomStatusButton.title)
        zoomStatusButton.setAccessibilityHelp(L10n.text(
            "preview.reset_actual_size",
            defaultValue: "Reset to Actual Size"
        ))
    }

    func validateVisibleItems() {
        toolbar?.validateVisibleItems()
    }

#if DEBUG
    var zoomStatus: String { zoomStatusButton.title }
    var zoomAccessibilityLabel: String? { zoomStatusButton.accessibilityLabel() }
    var zoomAccessibilityValue: String? {
        zoomStatusButton.accessibilityValue() as? String
    }
    var zoomAccessibilityHelp: String? { zoomStatusButton.accessibilityHelp() }
    var zoomStatusContainerSize: NSSize { zoomStatusContainer.frame.size }

    func clickZoomStatusForTesting() {
        zoomStatusButton.performClick(nil)
    }
#endif

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        itemIdentifiers
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        itemIdentifiers
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
        case Identifier.copyImage:
            toolbarItem(
                identifier: itemIdentifier,
                labelKey: "preview.copy",
                label: "Copy",
                symbol: "square.on.square",
                action: #selector(copyImage(_:))
            )
        case Identifier.savePNG:
            toolbarItem(
                identifier: itemIdentifier,
                labelKey: "preview.save_png",
                label: "Save PNG…",
                symbol: "square.and.arrow.down",
                action: #selector(savePNG(_:))
            )
        case Identifier.openInPreview:
            toolbarItem(
                identifier: itemIdentifier,
                labelKey: "preview.open_in_preview",
                label: "Open in Preview",
                symbol: "arrow.up.forward.square",
                action: #selector(openInPreview(_:))
            )
        case Identifier.fit:
            toolbarItem(
                identifier: itemIdentifier,
                labelKey: "preview.fit",
                label: "Fit to Window",
                symbol: "arrow.down.right.and.arrow.up.left",
                action: #selector(selectFit(_:))
            )
        case Identifier.zoomOut:
            toolbarItem(
                identifier: itemIdentifier,
                labelKey: "preview.zoom_out",
                label: "Zoom Out",
                symbol: "minus.magnifyingglass",
                action: #selector(zoomOut(_:))
            )
        case Identifier.zoomStatus:
            zoomStatusToolbarItem(identifier: itemIdentifier)
        case Identifier.zoomIn:
            toolbarItem(
                identifier: itemIdentifier,
                labelKey: "preview.zoom_in",
                label: "Zoom In",
                symbol: "plus.magnifyingglass",
                action: #selector(zoomIn(_:))
            )
        default:
            nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard hasImage() else { return false }
        switch item.itemIdentifier {
        case Identifier.zoomIn:
            return zoomFactor() < PreviewLayout.maximumZoomFactor - 0.001
        case Identifier.zoomOut:
            return zoomFactor() > PreviewLayout.minimumZoomFactor + 0.001
        default:
            return true
        }
    }

    private var itemIdentifiers: [NSToolbarItem.Identifier] {
        [
            Identifier.copyImage,
            Identifier.savePNG,
            Identifier.openInPreview,
            .flexibleSpace,
            Identifier.fit,
            Identifier.zoomOut,
            Identifier.zoomStatus,
            Identifier.zoomIn
        ]
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

    private func zoomStatusToolbarItem(
        identifier: NSToolbarItem.Identifier
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
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

    @objc private func copyImage(_ sender: Any?) {
        onCommand(.copyImage)
    }

    @objc private func savePNG(_ sender: Any?) {
        onCommand(.savePNG)
    }

    @objc private func openInPreview(_ sender: Any?) {
        onCommand(.openInPreview)
    }

    @objc private func selectFit(_ sender: Any?) {
        onCommand(.fit)
    }

    @objc private func selectActualSize(_ sender: Any?) {
        onCommand(.actualSize)
    }

    @objc private func zoomOut(_ sender: Any?) {
        onCommand(.zoomOut)
    }

    @objc private func zoomIn(_ sender: Any?) {
        onCommand(.zoomIn)
    }
}
