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
    let canRenderClipboard: Bool
    let canRerenderLastMarkdown: Bool
    let launchAtLoginAction: LaunchAtLoginMenuAction
    let canUseLaunchAtLogin: Bool

    init(
        canRestoreLastMarkdown: Bool,
        canShowLastRender: Bool,
        canRenderClipboard: Bool = true,
        canRerenderLastMarkdown: Bool = false,
        launchAtLoginAction: LaunchAtLoginMenuAction = .enable,
        canUseLaunchAtLogin: Bool = true
    ) {
        self.canRestoreLastMarkdown = canRestoreLastMarkdown
        self.canShowLastRender = canShowLastRender
        self.canRenderClipboard = canRenderClipboard
        self.canRerenderLastMarkdown = canRerenderLastMarkdown
        self.launchAtLoginAction = launchAtLoginAction
        self.canUseLaunchAtLogin = canUseLaunchAtLogin
    }

    init(
        statusMenuPresentation: StatusMenuPresentation,
        launchAtLoginPresentation: LaunchAtLoginPresentation
    ) {
        canRestoreLastMarkdown = statusMenuPresentation[.restoreLastMarkdown].isEnabled
        canShowLastRender = statusMenuPresentation[.showLastRender].isEnabled
        canRenderClipboard = statusMenuPresentation[.renderClipboard].isEnabled
        canRerenderLastMarkdown = statusMenuPresentation[.rerenderLastMarkdown].isEnabled
        launchAtLoginAction = launchAtLoginPresentation.menuAction
        canUseLaunchAtLogin = launchAtLoginPresentation.canPerformAction
    }
}

enum SampleGuideLayout {
    static let preferredContentSize = NSSize(width: 548, height: 382)
    static let screenInset: CGFloat = 12
    static let menuMinimumWidth: CGFloat = 252
    static let menuSections: [[StatusMenuCommand]] = [
        [.renderClipboard, .showLastRender],
        [.theme, .outputWidth, .examples],
        [.about, .quit]
    ]

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

enum SampleGuideExamplesEdge: Equatable {
    case leading
    case trailing
}

struct SampleGuidePlacement: Equatable {
    let positioningRect: NSRect
    let examplesEdge: SampleGuideExamplesEdge

    static func resolve(
        buttonBounds: NSRect,
        buttonFrameInScreen: NSRect?,
        visibleFrame: NSRect?
    ) -> SampleGuidePlacement {
        guard let buttonFrameInScreen, let visibleFrame else {
            return SampleGuidePlacement(
                positioningRect: buttonBounds,
                examplesEdge: .trailing
            )
        }
        return SampleGuidePlacement(
            positioningRect: buttonBounds,
            examplesEdge: buttonFrameInScreen.midX < visibleFrame.midX
                ? .trailing
                : .leading
        )
    }
}

enum SampleGuideFocusDirection: Equatable {
    case previous
    case next
}

enum SampleGuideKeyboardAction: Equatable {
    case move(SampleGuideFocusDirection)
    case activate
    case dismiss
    case ignore
}

struct SampleGuideKeyboardPolicy {
    static func action(
        for key: KeyEquivalent,
        modifiers: EventModifiers,
        acceptsExampleInput: Bool
    ) -> SampleGuideKeyboardAction {
        if key == .escape { return .dismiss }
        guard acceptsExampleInput else { return .ignore }
        if key == .upArrow || (key == .tab && modifiers.contains(.shift)) {
            return .move(.previous)
        }
        if key == .downArrow || key == .tab {
            return .move(.next)
        }
        if key == .return || key == .space {
            return .activate
        }
        return .ignore
    }
}

struct SampleGuideFocusOrder {
    static func movedFocus(
        from rawValue: Int?,
        direction: SampleGuideFocusDirection
    ) -> Int? {
        let values = ExampleKind.allCases.map(\.rawValue)
        guard !values.isEmpty else { return nil }
        guard let rawValue, let index = values.firstIndex(of: rawValue) else {
            return direction == .next ? values.first : values.last
        }
        switch direction {
        case .previous:
            return values[(index - 1 + values.count) % values.count]
        case .next:
            return values[(index + 1) % values.count]
        }
    }
}

struct SampleGuideCopy {
    let title: String
    let clipboard: String
    let render: String
    let saveClipboardAsSplitPNGs: String
    let rerenderLastMarkdown: String
    let restoreLastMarkdown: String
    let showLastRender: String
    let theme: String
    let outputWidth: String
    let examples: String
    let settings: String
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
        render = StatusMenuPresentation.title(
            for: .renderClipboard,
            localizationBundle: localizationBundle
        )
        saveClipboardAsSplitPNGs = StatusMenuPresentation.title(
            for: .saveClipboardAsSplitPNGs,
            localizationBundle: localizationBundle
        )
        rerenderLastMarkdown = StatusMenuPresentation.title(
            for: .rerenderLastMarkdown,
            localizationBundle: localizationBundle
        )
        restoreLastMarkdown = StatusMenuPresentation.title(
            for: .restoreLastMarkdown,
            localizationBundle: localizationBundle
        )
        showLastRender = StatusMenuPresentation.title(
            for: .showLastRender,
            localizationBundle: localizationBundle
        )
        theme = StatusMenuPresentation.title(
            for: .theme,
            localizationBundle: localizationBundle
        )
        outputWidth = StatusMenuPresentation.title(
            for: .outputWidth,
            localizationBundle: localizationBundle
        )
        examples = StatusMenuPresentation.title(
            for: .examples,
            localizationBundle: localizationBundle
        )
        settings = StatusMenuPresentation.title(
            for: .settings,
            localizationBundle: localizationBundle
        )
        showWelcome = StatusMenuPresentation.title(
            for: .showWelcome,
            localizationBundle: localizationBundle
        )
        about = StatusMenuPresentation.title(
            for: .about,
            localizationBundle: localizationBundle
        )
        quit = StatusMenuPresentation.title(
            for: .quit,
            localizationBundle: localizationBundle
        )
    }

    func exampleTitle(_ kind: ExampleKind) -> String {
        kind.menuTitle(localizationBundle: localizationBundle)
    }

    func launchAtLoginTitle(for action: LaunchAtLoginMenuAction) -> String {
        switch action {
        case .enable:
            L10n.text(
                "menu.enable_launch_at_login",
                defaultValue: "Enable Launch at Login",
                bundle: localizationBundle
            )
        case .disable:
            L10n.text(
                "menu.disable_launch_at_login",
                defaultValue: "Disable Launch at Login",
                bundle: localizationBundle
            )
        case .allowInSystemSettings:
            L10n.text(
                "menu.allow_launch_at_login",
                defaultValue: "Allow Launch at Login…",
                bundle: localizationBundle
            )
        case .unavailable:
            L10n.text(
                "menu.launch_at_login_unavailable",
                defaultValue: "Launch at Login Unavailable",
                bundle: localizationBundle
            )
        }
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
protocol SampleGuidePresenting: AnyObject {
    func show(
        relativeTo button: NSStatusBarButton,
        menuState: SampleGuideMenuState
    )
    func dismiss()
}

@MainActor
final class SampleGuideController: NSObject, NSPopoverDelegate {
    private let popover: any SampleGuidePopover
    private let onChoose: (ExampleKind) -> Void
    private let copy: SampleGuideCopy
    private let visibleFrameProvider: (NSStatusBarButton) -> NSRect?
    private let buttonFrameProvider: (NSStatusBarButton) -> NSRect?
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
        buttonFrameProvider: @escaping (NSStatusBarButton) -> NSRect? = {
            guard let window = $0.window else { return nil }
            return window.convertToScreen($0.convert($0.bounds, to: nil))
        },
        onChoose: @escaping (ExampleKind) -> Void
    ) {
        self.popover = popover
        self.onChoose = onChoose
        copy = SampleGuideCopy(localizationBundle: localizationBundle)
        self.visibleFrameProvider = visibleFrameProvider
        self.buttonFrameProvider = buttonFrameProvider
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
        let placement = SampleGuidePlacement.resolve(
            buttonBounds: button.bounds,
            buttonFrameInScreen: buttonFrameProvider(button),
            visibleFrame: visibleFrame
        )
        popover.contentSize = contentSize

        let hostingController = NSHostingController(
            rootView: SampleGuideView(
                copy: copy,
                contentSize: contentSize,
                menuState: menuState,
                examplesEdge: placement.examplesEdge,
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
        popover.contentViewController = hostingController
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

extension SampleGuideController: SampleGuidePresenting {}

struct SampleGuideView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: SampleGuidePhase
    @FocusState private var focusedExampleRawValue: Int?

    let copy: SampleGuideCopy
    let contentSize: NSSize
    let menuState: SampleGuideMenuState
    let examplesEdge: SampleGuideExamplesEdge
    let onChoose: (ExampleKind) -> Void
    let onDismiss: () -> Void
    let runsRevealSequence: Bool

    private var interactionPolicy: SampleGuideInteractionPolicy {
        SampleGuideInteractionPolicy(phase: phase)
    }

    init(
        copy: SampleGuideCopy,
        contentSize: NSSize,
        menuState: SampleGuideMenuState,
        examplesEdge: SampleGuideExamplesEdge = .trailing,
        onChoose: @escaping (ExampleKind) -> Void,
        onDismiss: @escaping () -> Void = {},
        initialPhase: SampleGuidePhase = .mainMenu,
        runsRevealSequence: Bool = true
    ) {
        _phase = State(initialValue: initialPhase)
        self.copy = copy
        self.contentSize = contentSize
        self.menuState = menuState
        self.examplesEdge = examplesEdge
        self.onChoose = onChoose
        self.onDismiss = onDismiss
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

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 10) {
                        if examplesEdge == .leading {
                            examplesMenu
                                .id(SampleGuidePanel.examples)
                            mainMenu
                                .id(SampleGuidePanel.mainMenu)
                        } else {
                            mainMenu
                                .id(SampleGuidePanel.mainMenu)
                            examplesMenu
                                .id(SampleGuidePanel.examples)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: true)
                }
                .onAppear {
                    proxy.scrollTo(
                        SampleGuidePanel.mainMenu,
                        anchor: examplesEdge == .leading ? .trailing : .leading
                    )
                }
                .onChange(of: phase) { _, newPhase in
                    guard newPhase == .submenu else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo(
                            SampleGuidePanel.examples,
                            anchor: examplesEdge == .leading ? .leading : .trailing
                        )
                    }
                }
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
        .onAppear {
            synchronizeExampleFocus()
        }
        .onChange(of: phase) { _, _ in
            synchronizeExampleFocus()
        }
        .onKeyPress(
            keys: [.tab, .upArrow, .downArrow, .return, .space, .escape],
            phases: .down
        ) { press in
            handleKeyPress(press)
        }
    }

    private var mainMenu: some View {
        SampleMainMenu(
            copy: copy,
            phase: phase,
            menuState: menuState
        )
    }

    private var examplesMenu: some View {
        SampleExamplesMenu(
            copy: copy,
            isInputEnabled: interactionPolicy.acceptsExampleInput,
            focusedExampleRawValue: $focusedExampleRawValue,
            onChoose: { kind in
                guard interactionPolicy.acceptsExampleInput else { return }
                onChoose(kind)
            }
        )
        .opacity(interactionPolicy.showsExamples ? 1 : 0)
        .offset(
            x: interactionPolicy.showsExamples
                ? 0
                : (examplesEdge == .leading ? 14 : -14)
        )
        .scaleEffect(
            interactionPolicy.showsExamples ? 1 : 0.97,
            anchor: examplesEdge == .leading ? .topTrailing : .topLeading
        )
        .allowsHitTesting(interactionPolicy.acceptsExampleInput)
        .disabled(!interactionPolicy.acceptsExampleInput)
        .accessibilityHidden(interactionPolicy.hidesExamplesFromAccessibility)
    }

    @MainActor
    private func synchronizeExampleFocus() {
        if interactionPolicy.acceptsExampleInput {
            if focusedExampleRawValue == nil {
                focusedExampleRawValue = ExampleKind.allCases.first?.rawValue
            }
        } else {
            focusedExampleRawValue = nil
        }
    }

    @MainActor
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        switch SampleGuideKeyboardPolicy.action(
            for: press.key,
            modifiers: press.modifiers,
            acceptsExampleInput: interactionPolicy.acceptsExampleInput
        ) {
        case let .move(direction):
            focusedExampleRawValue = SampleGuideFocusOrder.movedFocus(
                from: focusedExampleRawValue,
                direction: direction
            )
            return .handled
        case .activate:
            guard let focusedExampleRawValue,
                  let kind = ExampleKind(rawValue: focusedExampleRawValue) else {
                return .ignored
            }
            onChoose(kind)
            return .handled
        case .dismiss:
            onDismiss()
            return .handled
        case .ignore:
            return .ignored
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

private enum SampleGuidePanel: Hashable {
    case mainMenu
    case examples
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

            ForEach(SampleGuideLayout.menuSections.indices, id: \.self) { sectionIndex in
                GuideDivider()
                ForEach(SampleGuideLayout.menuSections[sectionIndex], id: \.self) { command in
                    menuRow(for: command)
                }
            }
        }
        .padding(6)
        .frame(minWidth: SampleGuideLayout.menuMinimumWidth, alignment: .top)
        .guideMenuBackground()
    }

    @ViewBuilder
    private func menuRow(for command: StatusMenuCommand) -> some View {
        switch command {
        case .renderClipboard:
            GuideMenuRow(
                title: copy.render,
                trailing: "⌃⌘X",
                isDisabled: !menuState.canRenderClipboard
            )
        case .saveClipboardAsSplitPNGs:
            GuideMenuRow(
                title: copy.saveClipboardAsSplitPNGs,
                isDisabled: !menuState.canRenderClipboard
            )
        case .showLastRender:
            GuideMenuRow(
                title: copy.showLastRender,
                trailing: "⌃⌘Z",
                isDisabled: !menuState.canShowLastRender
            )
        case .rerenderLastMarkdown:
            GuideMenuRow(
                title: copy.rerenderLastMarkdown,
                isDisabled: !menuState.canRerenderLastMarkdown
            )
        case .restoreLastMarkdown:
            GuideMenuRow(
                title: copy.restoreLastMarkdown,
                isDisabled: !menuState.canRestoreLastMarkdown
            )
        case .theme:
            GuideMenuRow(title: copy.theme, showsChevron: true)
        case .outputWidth:
            GuideMenuRow(title: copy.outputWidth, showsChevron: true)
        case .examples:
            GuideMenuRow(
                title: copy.examples,
                showsChevron: true,
                isHighlighted: phase.highlightsExamples
            )
        case .launchAtLogin:
            GuideMenuRow(
                title: copy.launchAtLoginTitle(for: menuState.launchAtLoginAction),
                isDisabled: !menuState.canUseLaunchAtLogin
            )
        case .settings:
            GuideMenuRow(title: copy.settings, trailing: "⌘,")
        case .showWelcome:
            GuideMenuRow(title: copy.showWelcome)
        case .about:
            GuideMenuRow(title: copy.about)
        case .quit:
            GuideMenuRow(title: copy.quit, trailing: "⌘Q")
        }
    }
}

private struct SampleExamplesMenu: View {
    let copy: SampleGuideCopy
    let isInputEnabled: Bool
    let focusedExampleRawValue: FocusState<Int?>.Binding
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
                .focused(focusedExampleRawValue, equals: kind.rawValue)
            }
        }
        .padding(6)
        .frame(minWidth: SampleGuideLayout.menuMinimumWidth, alignment: .top)
        .guideMenuBackground()
        .focusSection()
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
