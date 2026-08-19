import AppKit

@MainActor
protocol SampleGuidePopover: AnyObject {
    var behavior: NSPopover.Behavior { get set }
    var animates: Bool { get set }
    var delegate: (any NSPopoverDelegate)? { get set }
    var contentSize: NSSize { get set }
    var contentViewController: NSViewController? { get set }
    var isShown: Bool { get }

    func show(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        preferredEdge: NSRectEdge
    )
    func requestKeyboardFocus()
    func close()
}

extension NSPopover: SampleGuidePopover {
    func requestKeyboardFocus() {
        guard isShown else { return }
        if let window = contentViewController?.view.window {
            window.makeKey()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShown else { return }
            self.contentViewController?.view.window?.makeKey()
        }
    }
}

@MainActor
protocol SampleGuidePresenting: AnyObject {
    func show(
        relativeTo button: NSStatusBarButton,
        menuState: SampleGuideMenuState
    )
    func dismiss()
}
