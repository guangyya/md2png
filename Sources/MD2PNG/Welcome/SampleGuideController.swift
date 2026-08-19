import AppKit
import SwiftUI

@MainActor
final class SampleGuideController: NSObject, NSPopoverDelegate {
    private let popover: any SampleGuidePopover
    private let onChoose: (ExampleKind) -> Void
    private let copy: SampleGuideCopy
    private let visibleFrameProvider: (NSStatusBarButton) -> NSRect?
    private weak var highlightedButton: NSButton?
    private var acceptsSelection = false
    private var pendingSelection: ExampleKind?
    private var isClosing = false

    convenience init(onChoose: @escaping (ExampleKind) -> Void) {
        self.init(popover: NSPopover(), onChoose: onChoose)
    }

    init(
        popover: any SampleGuidePopover,
        localizationBundle: Bundle? = nil,
        visibleFrameProvider: @escaping (NSStatusBarButton) -> NSRect? = {
            $0.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        },
        onChoose: @escaping (ExampleKind) -> Void
    ) {
        self.popover = popover
        self.onChoose = onChoose
        copy = SampleGuideCopy(localizationBundle: localizationBundle)
        self.visibleFrameProvider = visibleFrameProvider
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = SampleGuideLayout.preferredContentSize
    }

    func show(
        relativeTo button: NSStatusBarButton,
        menuState: SampleGuideMenuState
    ) {
        guard !popover.isShown, !isClosing else { return }
        acceptsSelection = true
        let visibleFrame = visibleFrameProvider(button)
        let contentSize = SampleGuideLayout.contentSize(visibleFrame: visibleFrame)
        let placement = SampleGuidePlacement.resolve(buttonBounds: button.bounds)
        popover.contentSize = contentSize

        popover.contentViewController = makeContentViewController(
            contentSize: contentSize,
            menuState: menuState,
            examplesEdge: placement.examplesEdge
        )
        // Installing an NSHostingController can replace NSPopover's requested
        // size with the SwiftUI view's not-yet-laid-out intrinsic size.
        popover.contentSize = contentSize
        highlightedButton = button
        button.highlight(true)
        popover.show(
            relativeTo: placement.positioningRect,
            of: button,
            preferredEdge: .minY
        )
        guard popover.isShown else {
            acceptsSelection = false
            popover.contentViewController = nil
            clearStatusButtonHighlight()
            return
        }
        popover.requestKeyboardFocus()
    }

    func dismiss() {
        acceptsSelection = false
        if popover.isShown, !isClosing {
            isClosing = true
            popover.close()
        } else if !popover.isShown {
            isClosing = false
            deliverPendingSelection()
        }
        clearStatusButtonHighlight()
    }

    func popoverWillClose(_ notification: Notification) {
        acceptsSelection = false
        isClosing = true
        clearStatusButtonHighlight()
    }

    func popoverDidClose(_ notification: Notification) {
        acceptsSelection = false
        isClosing = false
        clearStatusButtonHighlight()
        deliverPendingSelection()
    }

    func choose(_ kind: ExampleKind) {
        guard acceptsSelection else { return }
        acceptsSelection = false
        pendingSelection = kind
        guard popover.isShown else {
            deliverPendingSelection()
            return
        }
        isClosing = true
        popover.close()
    }

    private func makeContentViewController(
        contentSize: NSSize,
        menuState: SampleGuideMenuState,
        examplesEdge: SampleGuideExamplesEdge
    ) -> NSHostingController<SampleGuideView> {
        let hostingController = NSHostingController(
            rootView: SampleGuideView(
                copy: copy,
                contentSize: contentSize,
                menuState: menuState,
                examplesEdge: examplesEdge,
                onChoose: { [weak self] kind in
                    self?.choose(kind)
                },
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            )
        )
        hostingController.preferredContentSize = contentSize
        hostingController.view.frame = NSRect(origin: .zero, size: contentSize)
        return hostingController
    }

    private func clearStatusButtonHighlight() {
        highlightedButton?.highlight(false)
        highlightedButton = nil
    }

    private func deliverPendingSelection() {
        guard let selection = pendingSelection else { return }
        pendingSelection = nil
        clearStatusButtonHighlight()
        onChoose(selection)
    }
}

extension SampleGuideController: SampleGuidePresenting {}
