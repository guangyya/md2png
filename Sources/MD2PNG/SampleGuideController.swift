import AppKit
import Carbon
import Combine
import SwiftUI

enum SampleGuidePhase: Int, Equatable {
    case mainMenu
    case examplesFocused
    case submenu

    var highlightsExamples: Bool { self != .mainMenu }
    var showsSubmenu: Bool { self == .submenu }
    var acceptsSubmenuInput: Bool { self == .submenu }
}

struct SampleGuideMenuState: Equatable {
    let canRestoreLastMarkdown: Bool
    let canShowLastRender: Bool
}

enum SampleGuideFocusDirection {
    case previous
    case next
}

enum SampleGuideKeyCommand: Equatable {
    case previous
    case next
    case activate
    case dismiss
}

enum SampleGuideKeyCode {
    static let tab = UInt16(kVK_Tab)
    static let upArrow = UInt16(kVK_UpArrow)
    static let downArrow = UInt16(kVK_DownArrow)
    static let space = UInt16(kVK_Space)
    static let returnKey = UInt16(kVK_Return)
    static let keypadEnter = UInt16(kVK_ANSI_KeypadEnter)
    static let escape = UInt16(kVK_Escape)
}

struct SampleGuideKeyRouting {
    static func command(
        forKeyCode keyCode: UInt16,
        isShiftPressed: Bool
    ) -> SampleGuideKeyCommand? {
        switch keyCode {
        case SampleGuideKeyCode.tab:
            return isShiftPressed ? .previous : .next
        case SampleGuideKeyCode.upArrow:
            return .previous
        case SampleGuideKeyCode.downArrow:
            return .next
        case SampleGuideKeyCode.space,
             SampleGuideKeyCode.returnKey,
             SampleGuideKeyCode.keypadEnter:
            return .activate
        case SampleGuideKeyCode.escape:
            return .dismiss
        default:
            return nil
        }
    }
}

struct SampleGuideFocusNavigation {
    static func targetID(
        from currentID: Int?,
        direction: SampleGuideFocusDirection
    ) -> Int? {
        let ids = ExampleKind.allCases.map(\.rawValue)
        guard !ids.isEmpty else { return nil }
        guard let currentID, let currentIndex = ids.firstIndex(of: currentID) else {
            return direction == .previous ? ids.last : ids.first
        }

        switch direction {
        case .previous:
            return ids[(currentIndex - 1 + ids.count) % ids.count]
        case .next:
            return ids[(currentIndex + 1) % ids.count]
        }
    }
}

@MainActor
final class SampleGuideKeyboardState: ObservableObject {
    @Published private(set) var focusedExampleID: Int?
    private(set) var isNavigationEnabled = false

    var focusedExample: ExampleKind? {
        focusedExampleID.flatMap(ExampleKind.init(rawValue:))
    }

    func enableAndFocusFirstExample() {
        isNavigationEnabled = true
        focusedExampleID = ExampleKind.short.rawValue
    }

    func move(_ direction: SampleGuideFocusDirection) {
        guard isNavigationEnabled else { return }
        focusedExampleID = SampleGuideFocusNavigation.targetID(
            from: focusedExampleID,
            direction: direction
        )
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
    func makeContentKey()
    func close()
}

extension NSPopover: SampleGuidePopover {
    func makeContentKey() {
        contentViewController?.view.window?.makeKey()
    }
}

@MainActor
final class SampleGuideController: NSObject, NSPopoverDelegate {
    private let popover: any SampleGuidePopover
    private let onChoose: (ExampleKind) -> Void
    private weak var highlightedButton: NSButton?
    private var acceptsSelection = false
    private var pendingSelection: ExampleKind?
    private var keyboardState: SampleGuideKeyboardState?
    private var keyEventMonitor: Any?

    convenience init(onChoose: @escaping (ExampleKind) -> Void) {
        self.init(popover: NSPopover(), onChoose: onChoose)
    }

    init(
        popover: any SampleGuidePopover,
        onChoose: @escaping (ExampleKind) -> Void
    ) {
        self.popover = popover
        self.onChoose = onChoose
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 548, height: 382)
    }

    func show(
        relativeTo button: NSStatusBarButton,
        menuState: SampleGuideMenuState
    ) {
        dismiss()
        acceptsSelection = true
        let keyboardState = SampleGuideKeyboardState()
        self.keyboardState = keyboardState

        popover.contentViewController = NSHostingController(
            rootView: SampleGuideView(
                menuState: menuState,
                keyboardState: keyboardState,
                onChoose: { [weak self] kind in
                    self?.choose(kind)
                },
                onDismiss: { [weak self] in self?.dismiss() }
            )
        )
        highlightedButton = button
        button.highlight(true)
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        popover.makeContentKey()
        startMonitoringKeyboard()
    }

    func dismiss() {
        acceptsSelection = false
        pendingSelection = nil
        stopMonitoringKeyboard()
        if popover.isShown {
            popover.close()
        }
        keyboardState = nil
        clearStatusButtonHighlight()
    }

    func popoverWillClose(_ notification: Notification) {
        stopMonitoringKeyboard()
        clearStatusButtonHighlight()
    }

    func popoverDidClose(_ notification: Notification) {
        acceptsSelection = false
        stopMonitoringKeyboard()
        keyboardState = nil
        clearStatusButtonHighlight()

        guard let selection = pendingSelection else { return }
        pendingSelection = nil
        onChoose(selection)
    }

    func choose(_ kind: ExampleKind) {
        guard acceptsSelection else { return }
        acceptsSelection = false
        pendingSelection = kind
        popover.close()
    }

    private func clearStatusButtonHighlight() {
        highlightedButton?.highlight(false)
        highlightedButton = nil
    }

    private func startMonitoringKeyboard() {
        stopMonitoringKeyboard()
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            dispatchPrecondition(condition: .onQueue(.main))
            return self?.handleKeyDown(event) ?? event
        }
    }

    private func stopMonitoringKeyboard() {
        guard let keyEventMonitor else { return }
        NSEvent.removeMonitor(keyEventMonitor)
        self.keyEventMonitor = nil
    }

    func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard acceptsSelection,
              popover.isShown,
              let command = SampleGuideKeyRouting.command(
                  forKeyCode: event.keyCode,
                  isShiftPressed: event.modifierFlags.contains(.shift)
              ) else {
            return event
        }

        if command == .dismiss {
            dismiss()
            return nil
        }

        guard let keyboardState, keyboardState.isNavigationEnabled else {
            return nil
        }

        switch command {
        case .previous:
            keyboardState.move(.previous)
        case .next:
            keyboardState.move(.next)
        case .activate:
            guard let focusedExample = keyboardState.focusedExample else { return nil }
            choose(focusedExample)
        case .dismiss:
            break
        }
        return nil
    }
}

private struct SampleGuideView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = SampleGuidePhase.mainMenu
    @FocusState private var focusedExampleID: Int?

    let menuState: SampleGuideMenuState
    @ObservedObject var keyboardState: SampleGuideKeyboardState
    let onChoose: (ExampleKind) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "menubar.rectangle")
                    .foregroundStyle(.tint)
                Text(L10n.text(
                    "welcome.sample_guide.title",
                    defaultValue: "Find Examples in the md2png menu"
                ))
                    .font(.headline)
            }

            HStack(alignment: .top, spacing: 10) {
                SampleMainMenu(phase: phase, menuState: menuState)

                SampleExamplesMenu(
                    isInputEnabled: phase.acceptsSubmenuInput,
                    focusedExampleID: $focusedExampleID,
                    onChoose: { kind in
                        guard phase.acceptsSubmenuInput else { return }
                        onChoose(kind)
                    }
                )
                    .opacity(phase.showsSubmenu ? 1 : 0)
                    .offset(x: phase.showsSubmenu ? 0 : -14)
                    .scaleEffect(
                        phase.showsSubmenu ? 1 : 0.97,
                        anchor: .topLeading
                    )
                    .allowsHitTesting(phase.acceptsSubmenuInput)
                    .disabled(!phase.acceptsSubmenuInput)
                    .accessibilityHidden(!phase.showsSubmenu)
            }
        }
        .padding(12)
        .frame(width: 548, height: 382, alignment: .topLeading)
        .task {
            await revealMenuPath()
        }
        .onReceive(keyboardState.$focusedExampleID) { focusedExampleID in
            self.focusedExampleID = focusedExampleID
        }
        .onExitCommand(perform: onDismiss)
    }

    @MainActor
    private func revealMenuPath() async {
        if reduceMotion {
            phase = .submenu
            await focusFirstExample()
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
        await focusFirstExample()
    }

    @MainActor
    private func focusFirstExample() async {
        await Task.yield()
        guard phase.acceptsSubmenuInput else { return }
        keyboardState.enableAndFocusFirstExample()
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
    let phase: SampleGuidePhase
    let menuState: SampleGuideMenuState

    var body: some View {
        VStack(spacing: 2) {
            Text(L10n.text("menu.clipboard", defaultValue: "Clipboard"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)

            GuideMenuRow(
                title: L10n.text(
                    "menu.render",
                    defaultValue: "Render Clipboard as Image"
                ),
                trailing: "⌃⌘X"
            )
            GuideMenuRow(
                title: L10n.text(
                    "menu.restore_last_markdown",
                    defaultValue: "Restore Last Markdown"
                ),
                isDisabled: !menuState.canRestoreLastMarkdown
            )
            GuideMenuRow(
                title: L10n.text(
                    "menu.show_last_render",
                    defaultValue: "Show Last Render"
                ),
                trailing: "⌃⌘Z",
                isDisabled: !menuState.canShowLastRender
            )

            GuideDivider()

            GuideMenuRow(
                title: L10n.text("menu.render_width", defaultValue: "Output Width"),
                showsChevron: true
            )
            GuideMenuRow(
                title: L10n.text("menu.examples", defaultValue: "Examples"),
                showsChevron: true,
                isHighlighted: phase.highlightsExamples
            )

            GuideDivider()

            GuideMenuRow(
                title: L10n.text("menu.show_welcome", defaultValue: "Show Welcome")
            )
            GuideMenuRow(
                title: L10n.text("menu.about", defaultValue: "About md2png")
            )

            GuideDivider()

            GuideMenuRow(
                title: L10n.text("menu.quit", defaultValue: "Quit md2png"),
                trailing: "⌘Q"
            )
        }
        .padding(6)
        .frame(width: 252, height: 326, alignment: .top)
        .guideMenuBackground()
    }
}

private struct SampleExamplesMenu: View {
    let isInputEnabled: Bool
    @FocusState.Binding var focusedExampleID: Int?
    let onChoose: (ExampleKind) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(ExampleKind.allCases, id: \.rawValue) { kind in
                if kind.startsMenuSection {
                    GuideDivider()
                }
                SampleExampleButton(
                    kind: kind,
                    isRecommended: kind == .short,
                    isInputEnabled: isInputEnabled,
                    action: { onChoose(kind) }
                )
                .focused($focusedExampleID, equals: kind.rawValue)
            }
        }
        .padding(6)
        .frame(width: 252, height: 326, alignment: .top)
        .guideMenuBackground()
    }
}

private struct GuideMenuRow: View {
    let title: String
    var trailing: String?
    var showsChevron = false
    var isHighlighted = false
    var isDisabled = false

    private var foregroundColor: Color {
        if isHighlighted { return .white }
        if isDisabled { return .secondary.opacity(0.55) }
        return .primary
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(isHighlighted ? .white.opacity(0.85) : .secondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            isHighlighted ? Color.accentColor : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
}

private struct SampleExampleButton: View {
    let kind: ExampleKind
    let isRecommended: Bool
    let isInputEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(kind.menuTitle)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isRecommended {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .background(
                (isHovering || isRecommended)
                    ? Color.accentColor.opacity(isHovering ? 0.2 : 0.09)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isInputEnabled)
        .allowsHitTesting(isInputEnabled)
        .onHover { isHovering = $0 }
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
