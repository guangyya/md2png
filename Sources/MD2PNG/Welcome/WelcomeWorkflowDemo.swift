import AppKit
import SwiftUI

private enum WelcomeDemoPalette {
    static let cyan = Color(red: 0.08, green: 0.72, blue: 0.93)
    static let violet = Color(red: 0.48, green: 0.34, blue: 0.96)
    static let pink = Color(red: 0.94, green: 0.28, blue: 0.62)
}

enum WelcomeWorkflowLayout {
    static let replayButtonSize: CGFloat = 26
    static let replayButtonInset: CGFloat = 9
    static let stageWidth: CGFloat = 128
    static let stageOffset: CGFloat = 154
    static let trackHeight: CGFloat = 70
    static let shortcutVerticalOffset: CGFloat = 20
}

enum WelcomeWorkflowPhase: Int, CaseIterable, Equatable {
    case copy
    case render
    case paste
    case complete
}

struct WelcomeAnimationProgress: Equatable {
    let cardTravel: CGFloat
    let keyPress: CGFloat
    let imageReveal: CGFloat
    let detailIndex: Int
    let showsCompletedJourney: Bool

    static let reducedMotion = WelcomeAnimationProgress(phase: .complete)

    func shortcutOpacity(for phase: WelcomeWorkflowPhase) -> CGFloat {
        if showsCompletedJourney {
            return phase == .complete ? 0 : 1
        }
        return phase.rawValue == detailIndex ? 1 : 0
    }

    init(phase: WelcomeWorkflowPhase) {
        switch phase {
        case .copy:
            cardTravel = -1
            keyPress = 0
            imageReveal = 0
            detailIndex = 0
            showsCompletedJourney = false
        case .render:
            cardTravel = 0
            keyPress = 1
            imageReveal = 0.56
            detailIndex = 1
            showsCompletedJourney = false
        case .paste:
            cardTravel = 1
            keyPress = 0
            imageReveal = 1
            detailIndex = 2
            showsCompletedJourney = false
        case .complete:
            cardTravel = 1
            keyPress = 0
            imageReveal = 1
            detailIndex = 2
            showsCompletedJourney = true
        }
    }
}

struct WelcomeCompletedJourneyStage: Equatable, Identifiable {
    let phase: WelcomeWorkflowPhase
    let cardOffset: CGFloat
    let shortcutKeys: [String]

    var id: Int { phase.rawValue }
    var progress: WelcomeAnimationProgress { WelcomeAnimationProgress(phase: phase) }

    static let all = [
        WelcomeCompletedJourneyStage(
            phase: .copy,
            cardOffset: -WelcomeWorkflowLayout.stageOffset,
            shortcutKeys: ["⌘", "C"]
        ),
        WelcomeCompletedJourneyStage(
            phase: .render,
            cardOffset: 0,
            shortcutKeys: ["⌃", "⌘", "X"]
        ),
        WelcomeCompletedJourneyStage(
            phase: .paste,
            cardOffset: WelcomeWorkflowLayout.stageOffset,
            shortcutKeys: ["⌘", "V"]
        )
    ]
}

struct WelcomeCardMotion: Equatable {
    let rotation: Double
    let scale: CGFloat
    let verticalOffset: CGFloat
    let activityShadowOpacity: Double
    let copyGlowOpacity: Double

    init(
        progress: WelcomeAnimationProgress,
        copyEmphasis: CGFloat,
        isSettled: Bool
    ) {
        if isSettled {
            rotation = 0
            scale = 1
            verticalOffset = 0
            activityShadowOpacity = 0.12
            copyGlowOpacity = 0
        } else {
            rotation = sin(Double(progress.imageReveal) * .pi) * 9
            scale = 1 + 0.045 * progress.keyPress + 0.06 * copyEmphasis
            verticalOffset = -3 * copyEmphasis
            activityShadowOpacity = 0.12 + 0.18 * Double(progress.keyPress)
            copyGlowOpacity = 0.3 * Double(copyEmphasis)
        }
    }
}

struct WelcomeShortcutContrastStyle: Equatable {
    let tintOpacity: Double
    let containerBorderOpacity: Double
    let containerBorderWidth: CGFloat
    let keyBorderOpacity: Double
    let keyBorderWidth: CGFloat

    init(contrast: ColorSchemeContrast) {
        if contrast == .increased {
            tintOpacity = 0.2
            containerBorderOpacity = 0.55
            containerBorderWidth = 1.2
            keyBorderOpacity = 0.62
            keyBorderWidth = 1.2
        } else {
            tintOpacity = 0.12
            containerBorderOpacity = 0.26
            containerBorderWidth = 0.8
            keyBorderOpacity = 0.34
            keyBorderWidth = 0.8
        }
    }
}

struct WelcomeWorkflowDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = WelcomeWorkflowPhase.copy
    @State private var sequenceID = 0
    @State private var copyEmphasis: CGFloat = 0

    let copy: WelcomeCopy

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WelcomeWorkflowScene(
                copy: copy,
                progress: reduceMotion
                    ? .reducedMotion
                    : WelcomeAnimationProgress(phase: phase),
                copyEmphasis: reduceMotion ? 0 : copyEmphasis
            )
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(copy.copyStepTitle). \(copy.renderStepTitle). \(copy.pasteStepTitle)."
            )

            WelcomeReplayButton(label: copy.replayDemo, action: replay)
                .frame(
                    width: WelcomeWorkflowLayout.replayButtonSize,
                    height: WelcomeWorkflowLayout.replayButtonSize
                )
                .background(.thinMaterial, in: Circle())
                .padding(WelcomeWorkflowLayout.replayButtonInset)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 156)
        .background(
            LinearGradient(
                colors: [
                    WelcomeDemoPalette.cyan.opacity(0.12),
                    Color.accentColor.opacity(0.055),
                    WelcomeDemoPalette.violet.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            WelcomeDemoPalette.cyan.opacity(0.34),
                            WelcomeDemoPalette.violet.opacity(0.26)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        }
        .shadow(color: WelcomeDemoPalette.violet.opacity(0.07), radius: 10, y: 4)
        .task(id: sequenceID) {
            await runSequence()
        }
    }

    @MainActor
    private func runSequence() async {
        if reduceMotion {
            phase = .complete
            copyEmphasis = 0
            return
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.56)) {
            copyEmphasis = 1
        }
        guard await pause(nanoseconds: 360_000_000) else { return }
        withAnimation(.easeOut(duration: 0.24)) {
            copyEmphasis = 0
        }

        guard await pause(nanoseconds: 540_000_000) else { return }
        withAnimation(.spring(response: 0.58, dampingFraction: 0.8)) {
            phase = .render
        }

        guard await pause(nanoseconds: 1_250_000_000) else { return }
        withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) {
            phase = .paste
        }

        guard await pause(nanoseconds: 1_150_000_000) else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            phase = .complete
        }
    }

    private func replay() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            phase = reduceMotion ? .complete : .copy
            copyEmphasis = 0
        }
        sequenceID += 1
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

struct WelcomeReplayButton: NSViewRepresentable {
    static let identifier = NSUserInterfaceItemIdentifier("WelcomeReplayButton")

    let label: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.identifier = Self.identifier
        button.title = ""
        button.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: nil
        )
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.focusRingType = .default
        button.setAccessibilityElement(true)
        button.setAccessibilityRole(.button)
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.keyEquivalent = "r"
        button.keyEquivalentModifierMask = [.command]
        update(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        update(button)
    }

    private func update(_ button: NSButton) {
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.setAccessibilityHelp(label)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

private struct WelcomeWorkflowScene: View {
    let copy: WelcomeCopy
    let progress: WelcomeAnimationProgress
    let copyEmphasis: CGFloat

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                WelcomeStageLabel(
                    title: copy.copyStepTitle,
                    symbol: "doc.on.doc.fill",
                    color: WelcomeDemoPalette.cyan,
                    isActive: progress.showsCompletedJourney || progress.detailIndex == 0
                )
                .frame(width: WelcomeWorkflowLayout.stageWidth)
                .offset(x: -WelcomeWorkflowLayout.stageOffset)
                WelcomeStageLabel(
                    title: copy.renderStepTitle,
                    symbol: "command",
                    color: WelcomeDemoPalette.violet,
                    isActive: progress.showsCompletedJourney || progress.detailIndex == 1
                )
                .frame(width: WelcomeWorkflowLayout.stageWidth)
                WelcomeStageLabel(
                    title: copy.pasteStepTitle,
                    symbol: "photo.fill",
                    color: WelcomeDemoPalette.pink,
                    isActive: progress.showsCompletedJourney || progress.detailIndex == 2
                )
                .frame(width: WelcomeWorkflowLayout.stageWidth)
                .offset(x: WelcomeWorkflowLayout.stageOffset)
            }
            .frame(maxWidth: .infinity)

            WelcomeTransformTrack(progress: progress, copyEmphasis: copyEmphasis)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 16)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.22), value: progress.detailIndex)
        }
    }

    private var detail: String {
        switch progress.detailIndex {
        case 0:
            copy.copyStepDetail
        case 1:
            copy.renderStepDetail
        default:
            copy.pasteStepDetail
        }
    }
}

private struct WelcomeStageLabel: View {
    let title: String
    let symbol: String
    let color: Color
    let isActive: Bool

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(isActive ? color : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                isActive ? color.opacity(0.12) : Color.clear,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(isActive ? color.opacity(0.3) : Color.clear, lineWidth: 0.6)
            }
    }
}

private struct WelcomeTransformTrack: View {
    let progress: WelcomeAnimationProgress
    let copyEmphasis: CGFloat

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(width: 350, height: 2)

            HStack {
                WelcomeTrackNode(color: WelcomeDemoPalette.cyan)
                Spacer()
                WelcomeTrackNode(color: WelcomeDemoPalette.violet)
                Spacer()
                WelcomeTrackNode(color: WelcomeDemoPalette.pink)
            }
            .frame(width: 358)

            ForEach(WelcomeCompletedJourneyStage.all) { stage in
                WelcomeTransformCard(progress: stage.progress, isSettled: true)
                    .offset(x: stage.cardOffset)
                    .opacity(progress.showsCompletedJourney ? 1 : 0)
                    .scaleEffect(progress.showsCompletedJourney ? 1 : 0.92)
            }

            WelcomeTransformCard(progress: progress, copyEmphasis: copyEmphasis)
                .offset(x: WelcomeWorkflowLayout.stageOffset * progress.cardTravel)
                .opacity(progress.showsCompletedJourney ? 0 : 1)

            ForEach(WelcomeCompletedJourneyStage.all) { stage in
                let shortcutOpacity = progress.shortcutOpacity(for: stage.phase)
                WelcomeShortcutBadge(
                    keys: stage.shortcutKeys,
                    color: shortcutColor(for: stage.phase)
                )
                .offset(
                    x: stage.cardOffset,
                    y: WelcomeWorkflowLayout.shortcutVerticalOffset
                )
                .opacity(shortcutOpacity)
                .scaleEffect(0.78 + 0.22 * shortcutOpacity)
            }
        }
        .frame(height: WelcomeWorkflowLayout.trackHeight)
    }

    private func shortcutColor(for phase: WelcomeWorkflowPhase) -> Color {
        switch phase {
        case .copy:
            WelcomeDemoPalette.cyan
        case .render:
            WelcomeDemoPalette.violet
        case .paste, .complete:
            WelcomeDemoPalette.pink
        }
    }
}

private struct WelcomeTrackNode: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(Color(nsColor: .windowBackgroundColor))
            .frame(width: 12, height: 12)
            .overlay {
                Circle().stroke(color.opacity(0.55), lineWidth: 2)
            }
    }
}

private struct WelcomeTransformCard: View {
    let progress: WelcomeAnimationProgress
    var isSettled = false
    var copyEmphasis: CGFloat = 0

    private var motion: WelcomeCardMotion {
        WelcomeCardMotion(
            progress: progress,
            copyEmphasis: copyEmphasis,
            isSettled: isSettled
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))

            WelcomeMarkdownFace()
                .opacity(1 - progress.imageReveal)

            WelcomePNGFace()
                .opacity(progress.imageReveal)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            WelcomeDemoPalette.cyan.opacity(0.4),
                            WelcomeDemoPalette.violet.opacity(0.36),
                            WelcomeDemoPalette.pink.opacity(0.34)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .frame(width: WelcomeWorkflowLayout.stageWidth, height: 62)
        .rotation3DEffect(.degrees(motion.rotation), axis: (x: 0, y: 1, z: 0))
        .scaleEffect(motion.scale)
        .offset(y: motion.verticalOffset)
        .shadow(
            color: WelcomeDemoPalette.violet.opacity(motion.activityShadowOpacity),
            radius: 9,
            y: 4
        )
        .shadow(
            color: WelcomeDemoPalette.cyan.opacity(motion.copyGlowOpacity),
            radius: 12,
            y: 2
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: progress.imageReveal > 0.8 ? "photo.fill" : "doc.text.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(
                    progress.imageReveal > 0.8
                        ? WelcomeDemoPalette.pink
                        : WelcomeDemoPalette.cyan,
                    in: Circle()
                )
                .offset(x: 6, y: -6)
        }
    }
}

private struct WelcomeMarkdownFace: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            DemoCodeLine(width: 88, color: WelcomeDemoPalette.cyan.opacity(0.68))
            DemoCodeLine(width: 102)
            DemoCodeLine(width: 72)
        }
    }
}

private struct WelcomePNGFace: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    WelcomeDemoPalette.cyan,
                    WelcomeDemoPalette.violet,
                    WelcomeDemoPalette.pink
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(5)
    }
}

private struct WelcomeShortcutBadge: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let keys: [String]
    let color: Color

    private var style: WelcomeShortcutContrastStyle {
        WelcomeShortcutContrastStyle(contrast: colorSchemeContrast)
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .frame(width: 18, height: 18)
                    .background(
                        Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(
                                Color(nsColor: .labelColor).opacity(style.keyBorderOpacity),
                                lineWidth: style.keyBorderWidth
                            )
                    }
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.opacity(style.tintOpacity))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(
                Color(nsColor: .labelColor).opacity(style.containerBorderOpacity),
                lineWidth: style.containerBorderWidth
            )
        }
        .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
    }
}

private struct DemoCodeLine: View {
    let width: CGFloat
    var color = Color(nsColor: .tertiaryLabelColor).opacity(0.45)

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: 4)
    }
}
