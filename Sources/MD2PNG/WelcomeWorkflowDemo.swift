import AppKit
import SwiftUI

struct WelcomeAnimationProgress: Equatable {
    let copyLift: CGFloat
    let copyTravel: CGFloat
    let keyPress: CGFloat
    let renderTravel: CGFloat
    let imageReveal: CGFloat
    let pastePrompt: CGFloat
    let activityOpacity: CGFloat
    let detailIndex: Int

    static let reducedMotion = WelcomeAnimationProgress(
        copyLift: 0,
        copyTravel: 1,
        keyPress: 0,
        renderTravel: 1,
        imageReveal: 1,
        pastePrompt: 1,
        activityOpacity: 1,
        detailIndex: 2
    )

    init(cycleProgress rawProgress: Double) {
        let progress = min(max(rawProgress, 0), 1)
        copyLift = Self.pulse(progress, rise: 0.02, peak: 0.1, fall: 0.24)
        copyTravel = Self.smoothStep(progress, from: 0.05, to: 0.26)
        keyPress = Self.pulse(progress, rise: 0.25, peak: 0.34, fall: 0.47)
        renderTravel = Self.smoothStep(progress, from: 0.34, to: 0.61)
        imageReveal = Self.smoothStep(progress, from: 0.43, to: 0.68)
        pastePrompt = Self.smoothStep(progress, from: 0.66, to: 0.78)
            * (1 - Self.smoothStep(progress, from: 0.92, to: 0.99))
        activityOpacity = min(
            Self.smoothStep(progress, from: 0, to: 0.04),
            1 - Self.smoothStep(progress, from: 0.94, to: 1)
        )
        detailIndex = progress < 0.27 ? 0 : (progress < 0.64 ? 1 : 2)
    }

    private init(
        copyLift: CGFloat,
        copyTravel: CGFloat,
        keyPress: CGFloat,
        renderTravel: CGFloat,
        imageReveal: CGFloat,
        pastePrompt: CGFloat,
        activityOpacity: CGFloat,
        detailIndex: Int
    ) {
        self.copyLift = copyLift
        self.copyTravel = copyTravel
        self.keyPress = keyPress
        self.renderTravel = renderTravel
        self.imageReveal = imageReveal
        self.pastePrompt = pastePrompt
        self.activityOpacity = activityOpacity
        self.detailIndex = detailIndex
    }

    private static func smoothStep(
        _ value: Double,
        from start: Double,
        to end: Double
    ) -> CGFloat {
        let normalized = min(max((value - start) / (end - start), 0), 1)
        return CGFloat(normalized * normalized * (3 - 2 * normalized))
    }

    private static func pulse(
        _ value: Double,
        rise: Double,
        peak: Double,
        fall: Double
    ) -> CGFloat {
        if value <= peak {
            return smoothStep(value, from: rise, to: peak)
        }
        return 1 - smoothStep(value, from: peak, to: fall)
    }
}

struct WelcomeWorkflowDemo: View {
    private static let cycleDuration: TimeInterval = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    let copy: WelcomeCopy

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1 / 30,
            paused: reduceMotion
        )) { context in
            let progress = reduceMotion
                ? WelcomeAnimationProgress.reducedMotion
                : WelcomeAnimationProgress(cycleProgress: cycleProgress(at: context.date))
            WelcomeWorkflowScene(copy: copy, progress: progress)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 184)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.42),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(0.7),
                    lineWidth: 0.5
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(copy.copyStepTitle). \(copy.renderStepTitle). \(copy.pasteStepTitle)."
        )
    }

    private func cycleProgress(at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        return elapsed.truncatingRemainder(dividingBy: Self.cycleDuration)
            / Self.cycleDuration
    }
}

private struct WelcomeWorkflowScene: View {
    let copy: WelcomeCopy
    let progress: WelcomeAnimationProgress

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                WelcomeMarkdownCard(copy: copy, progress: progress)
                WelcomeTransferTrack(
                    progress: progress.copyTravel,
                    activityOpacity: progress.activityOpacity
                )
                WelcomeShortcutCard(copy: copy, progress: progress)
                WelcomeTransferTrack(
                    progress: progress.renderTravel,
                    activityOpacity: progress.activityOpacity
                )
                WelcomePNGCard(copy: copy, progress: progress)
            }

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 34)
                .id(progress.detailIndex)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeInOut(duration: 0.3), value: progress.detailIndex)
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

private struct WelcomeMarkdownCard: View {
    let copy: WelcomeCopy
    let progress: WelcomeAnimationProgress

    private var tokenOpacity: CGFloat {
        CGFloat(sin(Double(progress.copyTravel) * .pi))
            * progress.activityOpacity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text("MD")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                DemoCodeLine(width: 82, color: Color.accentColor.opacity(0.65))
                DemoCodeLine(width: 104)
                DemoCodeLine(width: 66)
            }

            Spacer(minLength: 0)
            Text(copy.copyStepTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(11)
        .frame(width: 140, height: 104)
        .welcomeDemoCardBackground()
        .offset(y: -3 * progress.copyLift)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor, in: Circle())
                .shadow(color: Color.accentColor.opacity(0.25), radius: 6, y: 2)
                .scaleEffect(0.72 + 0.28 * progress.copyLift)
                .offset(
                    x: 24 * progress.copyTravel,
                    y: -8 * progress.copyLift
                )
                .opacity(tokenOpacity)
        }
    }
}

private struct WelcomeShortcutCard: View {
    let copy: WelcomeCopy
    let progress: WelcomeAnimationProgress

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(["⌃", "⌘", "X"], id: \.self) { key in
                    Text(key)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(
                            Color.accentColor.opacity(
                                0.08 + 0.22 * progress.keyPress
                            ),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    Color.accentColor.opacity(
                                        0.25 + 0.45 * progress.keyPress
                                    ),
                                    lineWidth: 0.7
                                )
                        }
                }
            }
            .scaleEffect(x: 1, y: 1 - 0.08 * progress.keyPress)
            .offset(y: 2 * progress.keyPress)

            Label(copy.renderStepTitle, systemImage: "wand.and.stars")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(
                    Color.accentColor.opacity(0.72 + 0.28 * progress.keyPress)
                )
        }
        .frame(width: 130, height: 104)
        .welcomeDemoCardBackground()
        .shadow(
            color: Color.accentColor.opacity(0.18 * progress.keyPress),
            radius: 10,
            y: 3
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)
                .scaleEffect(0.6 + 0.5 * progress.keyPress)
                .rotationEffect(.degrees(18 * Double(progress.keyPress)))
                .opacity(progress.keyPress * progress.activityOpacity)
                .offset(x: 5, y: -7)
        }
    }
}

private struct WelcomePNGCard: View {
    let copy: WelcomeCopy
    let progress: WelcomeAnimationProgress

    private var effectiveReveal: CGFloat {
        progress.imageReveal * progress.activityOpacity
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .separatorColor).opacity(0.12))

                ZStack {
                    LinearGradient(
                        colors: [Color.accentColor, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .mask(alignment: .leading) {
                    Rectangle()
                        .scaleEffect(x: effectiveReveal, anchor: .leading)
                }
            }
            .frame(height: 58)

            HStack {
                Text(copy.pasteStepTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("PNG")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(9)
        .frame(width: 140, height: 104)
        .welcomeDemoCardBackground()
        .overlay(alignment: .topTrailing) {
            Text("⌘V")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor, in: Capsule())
                .shadow(color: Color.accentColor.opacity(0.25), radius: 7, y: 2)
                .scaleEffect(0.72 + 0.28 * progress.pastePrompt)
                .offset(x: 7, y: -7 - 6 * progress.pastePrompt)
                .opacity(progress.pastePrompt * progress.activityOpacity)
        }
    }
}

private struct WelcomeTransferTrack: View {
    let progress: CGFloat
    let activityOpacity: CGFloat

    private var particleOpacity: CGFloat {
        CGFloat(sin(Double(progress) * .pi)) * activityOpacity
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 2)

            Capsule()
                .fill(Color.accentColor.opacity(0.7 * activityOpacity))
                .frame(width: 28 * progress, height: 2)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 7, height: 7)
                .shadow(color: Color.accentColor.opacity(0.5), radius: 4)
                .offset(x: 21 * progress)
                .opacity(particleOpacity)
        }
        .frame(width: 28, height: 18)
        .accessibilityHidden(true)
    }
}

private struct DemoCodeLine: View {
    let width: CGFloat
    var color = Color(nsColor: .tertiaryLabelColor).opacity(0.45)

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: 5)
    }
}

private extension View {
    func welcomeDemoCardBackground() -> some View {
        background(
            Color(nsColor: .windowBackgroundColor).opacity(0.84),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(0.62),
                    lineWidth: 0.5
                )
        }
    }
}
