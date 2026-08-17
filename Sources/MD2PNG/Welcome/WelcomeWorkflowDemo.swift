import AppKit
import SwiftUI

private enum WelcomeDemoPalette {
    static let cyan = Color(red: 0.08, green: 0.72, blue: 0.93)
    static let violet = Color(red: 0.48, green: 0.34, blue: 0.96)
    static let pink = Color(red: 0.94, green: 0.28, blue: 0.62)
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
    let pastePrompt: CGFloat
    let activityOpacity: CGFloat
    let detailIndex: Int

    static let reducedMotion = WelcomeAnimationProgress(phase: .complete)

    init(phase: WelcomeWorkflowPhase) {
        switch phase {
        case .copy:
            cardTravel = -1
            keyPress = 0
            imageReveal = 0
            pastePrompt = 0
            activityOpacity = 1
            detailIndex = 0
        case .render:
            cardTravel = 0
            keyPress = 1
            imageReveal = 0.56
            pastePrompt = 0
            activityOpacity = 1
            detailIndex = 1
        case .paste:
            cardTravel = 1
            keyPress = 0
            imageReveal = 1
            pastePrompt = 1
            activityOpacity = 1
            detailIndex = 2
        case .complete:
            cardTravel = 1
            keyPress = 0
            imageReveal = 1
            pastePrompt = 0.72
            activityOpacity = 0.82
            detailIndex = 2
        }
    }
}

struct WelcomeWorkflowDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = WelcomeWorkflowPhase.copy
    @State private var sequenceID = 0

    let copy: WelcomeCopy

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WelcomeWorkflowScene(
                copy: copy,
                progress: reduceMotion
                    ? .reducedMotion
                    : WelcomeAnimationProgress(phase: phase)
            )
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(copy.copyStepTitle). \(copy.renderStepTitle). \(copy.pasteStepTitle)."
            )

            WelcomeReplayButton(label: copy.replayDemo, action: replay)
                .frame(width: 26, height: 26)
                .background(.thinMaterial, in: Circle())
                .padding(9)
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
            return
        }

        guard await pause(nanoseconds: 900_000_000) else { return }
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

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                WelcomeStageLabel(
                    title: copy.copyStepTitle,
                    symbol: "doc.on.doc.fill",
                    color: WelcomeDemoPalette.cyan,
                    isActive: progress.detailIndex == 0
                )
                WelcomeStageLabel(
                    title: copy.renderStepTitle,
                    symbol: "command",
                    color: WelcomeDemoPalette.violet,
                    isActive: progress.detailIndex == 1
                )
                WelcomeStageLabel(
                    title: copy.pasteStepTitle,
                    symbol: "photo.fill",
                    color: WelcomeDemoPalette.pink,
                    isActive: progress.detailIndex == 2
                )
            }

            WelcomeTransformTrack(progress: progress)

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

            WelcomeTransformCard(progress: progress)
                .offset(x: 154 * progress.cardTravel)

            WelcomeShortcutBadge()
                .offset(y: 28)
                .opacity(progress.keyPress)
                .scaleEffect(0.78 + 0.22 * progress.keyPress)

            Text("⌘V")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(WelcomeDemoPalette.pink, in: Capsule())
                .shadow(color: WelcomeDemoPalette.pink.opacity(0.28), radius: 6, y: 2)
                .offset(x: 204, y: -25 - 5 * progress.pastePrompt)
                .opacity(progress.pastePrompt * progress.activityOpacity)
                .scaleEffect(0.78 + 0.22 * progress.pastePrompt)
        }
        .frame(height: 70)
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

    private var flipAngle: Double {
        sin(Double(progress.imageReveal) * .pi) * 9
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
        .frame(width: 128, height: 62)
        .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0))
        .scaleEffect(1 + 0.045 * progress.keyPress)
        .shadow(
            color: WelcomeDemoPalette.violet.opacity(0.12 + 0.18 * progress.keyPress),
            radius: 9,
            y: 4
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
    var body: some View {
        HStack(spacing: 3) {
            ForEach(["⌃", "⌘", "X"], id: \.self) { key in
                Text(key)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .frame(width: 18, height: 18)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(4)
        .background(WelcomeDemoPalette.violet.opacity(0.2), in: Capsule())
        .overlay {
            Capsule().stroke(WelcomeDemoPalette.violet.opacity(0.45), lineWidth: 0.7)
        }
        .shadow(color: WelcomeDemoPalette.violet.opacity(0.25), radius: 6, y: 2)
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
