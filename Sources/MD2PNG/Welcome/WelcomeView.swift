import AppKit
import SwiftUI

struct WelcomeView: View {
    let copy: WelcomeCopy
    let contentSize: NSSize
    @ObservedObject var shortcutVerificationState: WelcomeShortcutVerificationState
    @ObservedObject var launchAtLoginState: WelcomeLaunchAtLoginState
    let onTrySample: () -> Void
    let onDone: () -> Void

    private var hasShortcutConflict: Bool {
        shortcutVerificationState.shortcuts.contains { !$0.isRegistered }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.contentGroups) {
                    HStack(alignment: .top, spacing: 13) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .padding(7)
                            .background(
                                Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(Color.primary.opacity(0.14), lineWidth: 0.75)
                            }
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(copy.title)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(copy.subtitle)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    WelcomeWorkflowDemo(
                        copy: copy,
                        renderShortcutKeys: renderShortcutKeys
                    )

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                        AppSectionHeading(
                            title: copy.shortcutsTitle,
                            subtitle: copy.shortcutVerificationHelp
                        )

                        ForEach(shortcutVerificationState.shortcuts) { shortcut in
                            WelcomeShortcutRow(shortcut: shortcut, copy: copy)
                        }

                        if hasShortcutConflict {
                            Label(copy.shortcutConflictHelp, systemImage: "info.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.windowHorizontal)
                .padding(.top, AppTheme.Spacing.windowTop)
                .padding(.bottom, AppTheme.Spacing.windowBottom)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )

            Divider()

            WelcomeFooter(
                copy: copy,
                launchAtLoginState: launchAtLoginState,
                onTrySample: onTrySample,
                onDone: onDone
            )
        }
        .frame(
            width: contentSize.width,
            height: contentSize.height
        )
        .background {
            AppWindowBackdrop()
        }
    }

    private var renderShortcutKeys: [String] {
        shortcutVerificationState.shortcuts.first {
            $0.id == GlobalShortcutCommand.render.rawValue
        }?.shortcutKeys ?? GlobalShortcut.defaultRender.presentationKeys
    }
}

private struct WelcomeLaunchAtLoginRow: View {
    let copy: WelcomeCopy
    @ObservedObject var state: WelcomeLaunchAtLoginState
    @State private var isHovering = false

    var body: some View {
        Button {
            state.performPrimaryAction()
        } label: {
            HStack(spacing: 10) {
                Text(copy.launchAtLoginTitle)
                    .font(.callout.weight(.medium))

                Text(copy.launchAtLoginOptional)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                AppInlineStatusLabel(
                    title: statusText,
                    systemImage: statusSymbol,
                    color: statusColor
                )
                .frame(
                    minWidth: WelcomeLayout.statusColumnMinimumWidth,
                    alignment: .leading
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!state.presentation.canPerformAction)
        .appCardStyle(
            isHighlighted: isHovering && state.presentation.canPerformAction
        )
        .onHover { isHovering = $0 }
        .help(actionHelp)
        .accessibilityHint(actionHelp)
    }

    private var statusText: String {
        switch state.presentation.menuAction {
        case .enable:
            copy.launchAtLoginOff
        case .disable:
            copy.launchAtLoginOn
        case .allowInSystemSettings:
            copy.launchAtLoginOff
        case .unavailable:
            copy.launchAtLoginUnavailable
        }
    }

    private var statusSymbol: String {
        switch state.presentation.menuAction {
        case .enable, .allowInSystemSettings:
            "circle"
        case .disable:
            "checkmark.circle.fill"
        case .unavailable:
            "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch state.presentation.menuAction {
        case .disable:
            .green
        case .enable, .allowInSystemSettings, .unavailable:
            .secondary
        }
    }

    private var actionHelp: String {
        switch state.presentation.menuAction {
        case .enable:
            L10n.text(
                "menu.enable_launch_at_login",
                defaultValue: "Enable Launch at Login"
            )
        case .disable:
            L10n.text(
                "menu.disable_launch_at_login",
                defaultValue: "Disable Launch at Login"
            )
        case .allowInSystemSettings:
            "\(copy.launchAtLoginApprovalHelp) \(copy.launchAtLoginOpenSettings)"
        case .unavailable:
            copy.launchAtLoginUnavailable
        }
    }
}

private struct WelcomeFooter: View {
    let copy: WelcomeCopy
    @ObservedObject var launchAtLoginState: WelcomeLaunchAtLoginState
    let onTrySample: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WelcomeLaunchAtLoginRow(
                copy: copy,
                state: launchAtLoginState
            )
            .padding(.horizontal, AppTheme.Spacing.footerHorizontal)
            .padding(.vertical, 10)

            Divider()
                .padding(.leading, AppTheme.Spacing.footerHorizontal)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    footerNotes
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                    footerActions
                }

                VStack(alignment: .leading, spacing: 6) {
                    footerNotes
                    HStack(spacing: 10) {
                        Spacer()
                        footerActions
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.footerHorizontal)
            .padding(.vertical, AppTheme.Spacing.footerVertical)
        }
        .appWindowFooterStyle()
    }

    private var footerNotes: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(copy.privacyNote, systemImage: "lock.shield")
            Label(copy.reopenHint, systemImage: "menubar.rectangle")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .background(WelcomeFooterLayoutMarker(
            identifier: WelcomeFooterLayoutMarker.notesIdentifier
        ))
    }

    private var footerActions: some View {
        HStack(spacing: 10) {
            Button(action: onTrySample) {
                Label(copy.trySample, systemImage: "sparkles")
            }
            .help(copy.trySampleHelp)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityIdentifier("WelcomeTrySampleButton")

            Button(copy.done, action: onDone)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityIdentifier("WelcomeDoneButton")
        }
        .fixedSize(horizontal: true, vertical: false)
        .background(WelcomeFooterLayoutMarker(
            identifier: WelcomeFooterLayoutMarker.actionsIdentifier
        ))
    }
}

struct WelcomeFooterLayoutMarker: NSViewRepresentable {
    static let notesIdentifier = NSUserInterfaceItemIdentifier("WelcomeFooterNotesMarker")
    static let actionsIdentifier = NSUserInterfaceItemIdentifier("WelcomeFooterActionsMarker")

    let identifier: NSUserInterfaceItemIdentifier

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = identifier
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.identifier = identifier
    }
}

struct WelcomeShortcutFeedbackMotion: Equatable {
    let bounceValue: Int
    let scale: CGFloat
    let animationDuration: TimeInterval?

    init(
        reduceMotion: Bool,
        isShowingFeedback: Bool,
        verificationCount: Int
    ) {
        bounceValue = reduceMotion ? 0 : verificationCount
        scale = reduceMotion ? 1 : (isShowingFeedback ? 1.012 : 1)
        animationDuration = reduceMotion ? nil : 0.12
    }
}

struct WelcomeShortcutRowContrastStyle: Equatable {
    let idleRowBorderOpacity: Double
    let idleRowBorderWidth: CGFloat
    let feedbackFillOpacity: Double
    let feedbackRowBorderOpacity: Double
    let feedbackRowBorderWidth: CGFloat

    init(contrast: ColorSchemeContrast) {
        if contrast == .increased {
            idleRowBorderOpacity = 0.45
            idleRowBorderWidth = 1.25
            feedbackFillOpacity = 0.18
            feedbackRowBorderOpacity = 1
            feedbackRowBorderWidth = 2
        } else {
            idleRowBorderOpacity = 0.14
            idleRowBorderWidth = 0.75
            feedbackFillOpacity = 0.1
            feedbackRowBorderOpacity = 0.75
            feedbackRowBorderWidth = 1.4
        }
    }
}

private struct WelcomeShortcutRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let shortcut: WelcomeShortcutStatus
    let copy: WelcomeCopy
    @State private var isShowingVerificationFeedback = false
    @State private var verificationFeedbackTask: Task<Void, Never>?

    private var motion: WelcomeShortcutFeedbackMotion {
        WelcomeShortcutFeedbackMotion(
            reduceMotion: reduceMotion,
            isShowingFeedback: isShowingVerificationFeedback,
            verificationCount: shortcut.verificationCount
        )
    }

    private var contrast: WelcomeShortcutRowContrastStyle {
        WelcomeShortcutRowContrastStyle(contrast: colorSchemeContrast)
    }

    private var statusText: String {
        if !shortcut.isRegistered {
            return copy.shortcutUnavailable
        }
        if isShowingVerificationFeedback {
            return copy.shortcutDetected
        }
        return shortcut.isVerified ? copy.shortcutVerified : copy.shortcutReady
    }

    private var statusSymbol: String {
        if !shortcut.isRegistered {
            return "exclamationmark.triangle.fill"
        }
        return shortcut.isVerified ? "checkmark.circle.fill" : "circle.dashed"
    }

    private var statusColor: Color {
        if !shortcut.isRegistered {
            return .orange
        }
        return shortcut.isVerified ? .green : .secondary
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(shortcut.title)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Text(shortcut.shortcutGlyphs)
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .appShortcutControlStyle()
                .accessibilityLabel(shortcut.shortcutAccessibilityName)

            AppInlineStatusLabel(
                title: statusText,
                systemImage: statusSymbol,
                color: statusColor
            )
            .frame(
                minWidth: WelcomeLayout.statusColumnMinimumWidth,
                alignment: .leading
            )
            .symbolEffect(.bounce, value: motion.bounceValue)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: AppTheme.Shape.card
        )
        .overlay {
            if isShowingVerificationFeedback {
                AppTheme.Shape.card.fill(
                    Color.green.opacity(contrast.feedbackFillOpacity)
                )
            }
        }
        .overlay {
            AppTheme.Shape.card.stroke(
                isShowingVerificationFeedback
                    ? Color.green.opacity(contrast.feedbackRowBorderOpacity)
                    : Color.primary.opacity(contrast.idleRowBorderOpacity),
                lineWidth: isShowingVerificationFeedback
                    ? contrast.feedbackRowBorderWidth
                    : contrast.idleRowBorderWidth
            )
        }
        .scaleEffect(motion.scale)
        .animation(
            motion.animationDuration.map { Animation.easeOut(duration: $0) },
            value: isShowingVerificationFeedback
        )
        .onChange(of: shortcut.verificationCount) { _, verificationCount in
            guard verificationCount > 0 else { return }
            verificationFeedbackTask?.cancel()
            isShowingVerificationFeedback = true
            verificationFeedbackTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                isShowingVerificationFeedback = false
            }
        }
        .onDisappear {
            verificationFeedbackTask?.cancel()
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusText)
    }
}
