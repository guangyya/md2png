import AppKit
import SwiftUI

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
