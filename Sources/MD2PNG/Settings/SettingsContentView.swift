import SwiftUI

struct SettingsContentView: View {
    @State private var isLaunchAtLoginHovering = false
    @State private var isRoundedCornersHovering = false

    @ObservedObject var model: ShortcutSettingsModel
    @ObservedObject var launchAtLoginModel: LaunchAtLoginSettingsModel
    @ObservedObject var renderCornerModel: RenderCornerSettingsModel
    let copy: SettingsCopy

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.contentGroups) {
                generalSection
                outputSection
                shortcutSection
            }
            .padding(.horizontal, AppTheme.Spacing.windowHorizontal)
            .padding(.top, AppTheme.Spacing.windowTop)
            .padding(.bottom, AppTheme.Spacing.windowBottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            settingsFooter
                .padding(.horizontal, AppTheme.Spacing.footerHorizontal)
                .padding(.vertical, AppTheme.Spacing.footerVertical)
                .appWindowFooterStyle()
        }
        .frame(
            width: SettingsLayout.windowSize.width,
            height: SettingsLayout.windowSize.height,
            alignment: .topLeading
        )
        .background {
            AppWindowBackdrop()
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            Text(copy.outputTitle)
                .font(.headline)

            Button {
                renderCornerModel.toggle()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(copy.roundedCorners)
                            .font(.body.weight(.medium))
                        Text(copy.roundedCornersDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    AppInlineStatusLabel(
                        title: renderCornerModel.isEnabled
                            ? copy.launchAtLoginOn
                            : copy.launchAtLoginOff,
                        systemImage: renderCornerModel.isEnabled
                            ? "checkmark.circle.fill"
                            : "circle",
                        color: renderCornerModel.isEnabled ? .green : .secondary
                    )
                    .frame(minWidth: 80, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .frame(
                    maxWidth: .infinity,
                    minHeight: SettingsLayout.generalRowHeight,
                    maxHeight: SettingsLayout.generalRowHeight,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .appCardStyle(isHighlighted: isRoundedCornersHovering)
            .onHover { isRoundedCornersHovering = $0 }
            .accessibilityLabel(copy.roundedCorners)
            .accessibilityValue(
                renderCornerModel.isEnabled
                    ? copy.launchAtLoginOn
                    : copy.launchAtLoginOff
            )
            .accessibilityIdentifier("SettingsRoundedCornersToggle")
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            Text(copy.generalTitle)
                .font(.headline)

            Button {
                launchAtLoginModel.performPrimaryAction()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(copy.launchAtLogin)
                            .font(.body.weight(.medium))
                        Text(launchAtLoginDetail)
                            .font(.caption)
                            .foregroundStyle(launchAtLoginDetailColor)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    AppInlineStatusLabel(
                        title: launchAtLoginStatusText,
                        systemImage: launchAtLoginStatusSymbol,
                        color: launchAtLoginStatusColor
                    )
                    .frame(minWidth: 80, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .frame(
                    maxWidth: .infinity,
                    minHeight: SettingsLayout.generalRowHeight,
                    maxHeight: SettingsLayout.generalRowHeight,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!launchAtLoginModel.canChange)
            .appCardStyle(
                isHighlighted: isLaunchAtLoginHovering && launchAtLoginModel.canChange
            )
            .onHover { isLaunchAtLoginHovering = $0 }
            .accessibilityLabel(copy.launchAtLogin)
            .accessibilityValue(launchAtLoginStatusText)
            .accessibilityIdentifier("SettingsLaunchAtLoginToggle")
        }
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeading(title: copy.title, subtitle: copy.subtitle)

            VStack(spacing: 0) {
                shortcutRow(.render)
                Divider().padding(.leading, 16)
                shortcutRow(.showLastRender)
            }
            .appCardStyle()

            HStack {
                Spacer()
                Button(copy.restoreDefaults) {
                    model.restoreDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("ShortcutSettingsRestoreDefaults")
            }
        }
    }

    private var settingsFooter: some View {
        feedbackView
            .frame(
                maxWidth: .infinity,
                minHeight: SettingsLayout.feedbackHeight,
                maxHeight: SettingsLayout.feedbackHeight,
                alignment: .leading
            )
    }

    private var launchAtLoginDetail: String {
        if let errorMessage = launchAtLoginModel.errorMessage {
            return errorMessage
        }
        switch launchAtLoginModel.status {
        case .requiresApproval:
            return copy.launchAtLoginApproval
        case .unknown:
            return copy.launchAtLoginUnavailable
        case .notRegistered, .enabled, .notFound:
            return copy.launchAtLoginDetail
        }
    }

    private var launchAtLoginDetailColor: Color {
        launchAtLoginModel.errorMessage != nil || launchAtLoginModel.requiresApproval
            ? .orange
            : .secondary
    }

    private var launchAtLoginStatusText: String {
        switch launchAtLoginModel.status {
        case .enabled:
            copy.launchAtLoginOn
        case .notRegistered, .notFound, .requiresApproval:
            copy.launchAtLoginOff
        case .unknown:
            copy.unavailable
        }
    }

    private var launchAtLoginStatusSymbol: String {
        switch launchAtLoginModel.status {
        case .enabled:
            "checkmark.circle.fill"
        case .notRegistered, .notFound, .requiresApproval:
            "circle"
        case .unknown:
            "xmark.circle"
        }
    }

    private var launchAtLoginStatusColor: Color {
        launchAtLoginModel.status == .enabled ? .green : .secondary
    }

    private func shortcutRow(_ command: GlobalShortcutCommand) -> some View {
        let isUnavailable = model.failedRegistrationIDs.contains(command.rawValue)
        return HStack(spacing: 12) {
            Text(copy.commandTitle(command))
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)

            if isUnavailable {
                Label(copy.unavailable, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
                    .frame(width: 96, alignment: .trailing)
            } else {
                Color.clear
                    .frame(width: 96, height: 1)
                    .accessibilityHidden(true)
            }

            ShortcutRecorderView(
                shortcut: model.configuration[command],
                isRecording: model.recordingCommand == command,
                recordingTitle: copy.recording,
                accessibilityLabel: copy.recorderAccessibilityLabel(command),
                accessibilityHelp: copy.recordHelp,
                onBegin: { model.beginRecording(command) },
                onCancel: { model.cancelRecording() },
                onCapture: { _ = model.capture($0, for: command) }
            )
            .frame(width: 132, height: 30)
            .appShortcutControlStyle(
                isActive: model.recordingCommand == command
            )
            .accessibilityIdentifier("ShortcutRecorder.\(command.rawValue)")
        }
        .padding(.horizontal, 16)
        .frame(height: SettingsLayout.rowHeight)
    }

    @ViewBuilder
    private var feedbackView: some View {
        if let feedback = model.feedback {
            Label {
                Text(copy.feedbackText(feedback))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: feedback == .restoredDefaults
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill")
            }
            .font(.callout)
            .foregroundStyle(feedback == .restoredDefaults ? Color.secondary : Color.orange)
            .accessibilityIdentifier("ShortcutSettingsFeedback")
        } else {
            Text(copy.idleHelp)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let isRecording: Bool
    let recordingTitle: String
    let accessibilityLabel: String
    let accessibilityHelp: String
    let onBegin: () -> Void
    let onCancel: () -> Void
    let onCapture: (NSEvent) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        ShortcutRecorderControl()
    }

    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        control.configure(
            shortcut: shortcut,
            isRecording: isRecording,
            recordingTitle: recordingTitle,
            accessibilityLabel: accessibilityLabel,
            accessibilityHelp: accessibilityHelp,
            onBegin: onBegin,
            onCancel: onCancel,
            onCapture: onCapture
        )
    }
}
