import AppKit
import SwiftUI

enum SampleGuidePhase: Int, Equatable {
    case mainMenu
    case examplesFocused
    case submenu

    var highlightsExamples: Bool { self != .mainMenu }
    var showsSubmenu: Bool { self == .submenu }
    var acceptsSubmenuInput: Bool { self == .submenu }
}

struct SampleGuideInteractionPolicy: Equatable {
    let showsExamples: Bool
    let acceptsExampleInput: Bool
    let hidesExamplesFromAccessibility: Bool

    init(phase: SampleGuidePhase) {
        showsExamples = phase.showsSubmenu
        acceptsExampleInput = phase.acceptsSubmenuInput
        hidesExamplesFromAccessibility = !phase.acceptsSubmenuInput
    }
}

struct SampleGuideMenuState: Equatable {
    let canRestoreLastMarkdown: Bool
    let canShowLastRender: Bool
}

enum SampleGuideLayout {
    static let preferredContentSize = NSSize(width: 548, height: 382)
    static let screenInset: CGFloat = 12
    static let menuMinimumWidth: CGFloat = 252

    static func contentSize(visibleFrame: NSRect?) -> NSSize {
        guard let visibleFrame else { return preferredContentSize }
        return NSSize(
            width: max(
                1,
                min(
                    preferredContentSize.width,
                    visibleFrame.width - screenInset * 2
                )
            ),
            height: max(
                1,
                min(
                    preferredContentSize.height,
                    visibleFrame.height - screenInset * 2
                )
            )
        )
    }
}

struct SampleGuideCopy {
    let title: String
    let clipboard: String
    let render: String
    let restoreLastMarkdown: String
    let showLastRender: String
    let outputWidth: String
    let examples: String
    let showWelcome: String
    let about: String
    let quit: String
    private let localizationBundle: Bundle?

    init(localizationBundle: Bundle? = nil) {
        self.localizationBundle = localizationBundle
        title = L10n.text(
            "welcome.sample_guide.title",
            defaultValue: "Find Examples in the md2png menu",
            bundle: localizationBundle
        )
        clipboard = L10n.text(
            "menu.clipboard",
            defaultValue: "Clipboard",
            bundle: localizationBundle
        )
        render = L10n.text(
            "menu.render",
            defaultValue: "Render Clipboard as Image",
            bundle: localizationBundle
        )
        restoreLastMarkdown = L10n.text(
            "menu.restore_last_markdown",
            defaultValue: "Restore Last Markdown",
            bundle: localizationBundle
        )
        showLastRender = L10n.text(
            "menu.show_last_render",
            defaultValue: "Show Last Render",
            bundle: localizationBundle
        )
        outputWidth = L10n.text(
            "menu.render_width",
            defaultValue: "Output Width",
            bundle: localizationBundle
        )
        examples = L10n.text(
            "menu.examples",
            defaultValue: "Examples",
            bundle: localizationBundle
        )
        showWelcome = L10n.text(
            "menu.show_welcome",
            defaultValue: "Show Welcome",
            bundle: localizationBundle
        )
        about = L10n.text(
            "menu.about",
            defaultValue: "About md2png",
            bundle: localizationBundle
        )
        quit = L10n.text(
            "menu.quit",
            defaultValue: "Quit md2png",
            bundle: localizationBundle
        )
    }

    func exampleTitle(_ kind: ExampleKind) -> String {
        kind.menuTitle(localizationBundle: localizationBundle)
    }
}

struct GuideMenuHighlightStyle: Equatable {
    let borderWidth: CGFloat
    let recommendedFillOpacity: Double

    init(contrast: ColorSchemeContrast) {
        if contrast == .increased {
            borderWidth = 2
            recommendedFillOpacity = 0.2
        } else {
            borderWidth = 0.5
            recommendedFillOpacity = 0.09
        }
    }
}

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
    func close()
}

extension NSPopover: SampleGuidePopover {}

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
        let contentSize = SampleGuideLayout.contentSize(
            visibleFrame: visibleFrameProvider(button)
        )
        popover.contentSize = contentSize

        popover.contentViewController = NSHostingController(
            rootView: SampleGuideView(
                copy: copy,
                contentSize: contentSize,
                menuState: menuState,
                onChoose: { [weak self] kind in
                    self?.choose(kind)
                }
            )
        )
        highlightedButton = button
        button.highlight(true)
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        guard popover.isShown else {
            acceptsSelection = false
            popover.contentViewController = nil
            clearStatusButtonHighlight()
            return
        }
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

struct SampleGuideView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: SampleGuidePhase

    let copy: SampleGuideCopy
    let contentSize: NSSize
    let menuState: SampleGuideMenuState
    let onChoose: (ExampleKind) -> Void
    let runsRevealSequence: Bool

    private var interactionPolicy: SampleGuideInteractionPolicy {
        SampleGuideInteractionPolicy(phase: phase)
    }

    init(
        copy: SampleGuideCopy,
        contentSize: NSSize,
        menuState: SampleGuideMenuState,
        onChoose: @escaping (ExampleKind) -> Void,
        initialPhase: SampleGuidePhase = .mainMenu,
        runsRevealSequence: Bool = true
    ) {
        _phase = State(initialValue: initialPhase)
        self.copy = copy
        self.contentSize = contentSize
        self.menuState = menuState
        self.onChoose = onChoose
        self.runsRevealSequence = runsRevealSequence
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "menubar.rectangle")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(copy.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 10) {
                    SampleMainMenu(
                        copy: copy,
                        phase: phase,
                        menuState: menuState
                    )

                    SampleExamplesMenu(
                        copy: copy,
                        isInputEnabled: interactionPolicy.acceptsExampleInput,
                        onChoose: { kind in
                            guard interactionPolicy.acceptsExampleInput else { return }
                            onChoose(kind)
                        }
                    )
                    .opacity(interactionPolicy.showsExamples ? 1 : 0)
                    .offset(x: interactionPolicy.showsExamples ? 0 : -14)
                    .scaleEffect(
                        interactionPolicy.showsExamples ? 1 : 0.97,
                        anchor: .topLeading
                    )
                    .allowsHitTesting(interactionPolicy.acceptsExampleInput)
                    .disabled(!interactionPolicy.acceptsExampleInput)
                    .accessibilityHidden(interactionPolicy.hidesExamplesFromAccessibility)
                }
                .fixedSize(horizontal: true, vertical: true)
            }
        }
        .padding(12)
        .frame(
            width: contentSize.width,
            height: contentSize.height,
            alignment: .topLeading
        )
        .task {
            if runsRevealSequence {
                await revealMenuPath()
            }
        }
    }

    @MainActor
    private func revealMenuPath() async {
        if reduceMotion {
            phase = .submenu
            return
        }

        guard await pause(nanoseconds: 420_000_000) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            phase = .examplesFocused
        }

        guard await pause(nanoseconds: 520_000_000) else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            phase = .submenu
        }
    }

    private func pause(nanoseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

private struct SampleMainMenu: View {
    let copy: SampleGuideCopy
    let phase: SampleGuidePhase
    let menuState: SampleGuideMenuState

    var body: some View {
        VStack(spacing: 2) {
            Text(copy.clipboard)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)

            GuideMenuRow(
                title: copy.render,
                trailing: "⌃⌘X"
            )
            GuideMenuRow(
                title: copy.restoreLastMarkdown,
                isDisabled: !menuState.canRestoreLastMarkdown
            )
            GuideMenuRow(
                title: copy.showLastRender,
                trailing: "⌃⌘Z",
                isDisabled: !menuState.canShowLastRender
            )

            GuideDivider()

            GuideMenuRow(
                title: copy.outputWidth,
                showsChevron: true
            )
            GuideMenuRow(
                title: copy.examples,
                showsChevron: true,
                isHighlighted: phase.highlightsExamples
            )

            GuideDivider()

            GuideMenuRow(
                title: copy.showWelcome
            )
            GuideMenuRow(
                title: copy.about
            )

            GuideDivider()

            GuideMenuRow(
                title: copy.quit,
                trailing: "⌘Q"
            )
        }
        .padding(6)
        .frame(minWidth: SampleGuideLayout.menuMinimumWidth, alignment: .top)
        .guideMenuBackground()
    }
}

private struct SampleExamplesMenu: View {
    let copy: SampleGuideCopy
    let isInputEnabled: Bool
    let onChoose: (ExampleKind) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(ExampleKind.allCases, id: \.rawValue) { kind in
                if kind.startsMenuSection {
                    GuideDivider()
                }
                SampleExampleButton(
                    kind: kind,
                    title: copy.exampleTitle(kind),
                    isRecommended: kind == .short,
                    isInputEnabled: isInputEnabled,
                    action: { onChoose(kind) }
                )
            }
        }
        .padding(6)
        .frame(minWidth: SampleGuideLayout.menuMinimumWidth, alignment: .top)
        .guideMenuBackground()
    }
}

private struct GuideMenuRow: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let title: String
    var trailing: String?
    var showsChevron = false
    var isHighlighted = false
    var isDisabled = false

    private var foregroundColor: Color {
        if isHighlighted { return Color(nsColor: .selectedMenuItemTextColor) }
        if isDisabled { return .secondary.opacity(0.55) }
        return .primary
    }

    private var highlightColor: Color {
        Color(nsColor: .selectedContentBackgroundColor)
    }

    private var highlightStyle: GuideMenuHighlightStyle {
        GuideMenuHighlightStyle(contrast: colorSchemeContrast)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(
                        isHighlighted
                            ? Color(nsColor: .selectedMenuItemTextColor)
                            : .secondary
                    )
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
        }
        .font(.body)
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(minHeight: 30)
        .background(
            isHighlighted ? highlightColor : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    isHighlighted
                        ? Color(nsColor: .keyboardFocusIndicatorColor)
                        : Color.clear,
                    lineWidth: highlightStyle.borderWidth
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

private struct SampleExampleButton: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let kind: ExampleKind
    let title: String
    let isRecommended: Bool
    let isInputEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var highlightStyle: GuideMenuHighlightStyle {
        GuideMenuHighlightStyle(contrast: colorSchemeContrast)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if isRecommended {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background(
                (isHovering || isRecommended)
                    ? Color.accentColor.opacity(
                        isHovering ? 0.24 : highlightStyle.recommendedFillOpacity
                    )
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isRecommended && colorSchemeContrast == .increased
                            ? Color.accentColor
                            : Color.clear,
                        lineWidth: 1.5
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!isInputEnabled)
        .allowsHitTesting(isInputEnabled)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("SampleGuideExample.\(kind.rawValue)")
    }
}

private struct GuideDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
    }
}

private extension View {
    func guideMenuBackground() -> some View {
        background(
            Color(nsColor: .windowBackgroundColor).opacity(0.98),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }
}
