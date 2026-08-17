import AppKit
import SwiftUI

enum AboutLayout {
    static let windowSize = NSSize(width: 560, height: 490)
    static let detailedUpdateHeight: CGFloat = 66
    static let updateRowHeight: CGFloat = 18
    static let updateRowFontSize: CGFloat = 12
    static let updateRowIconSize: CGFloat = 16
    static let updateRowSpacing: CGFloat = 7
    static let updateRowIconBaselineOffset = NSFont
        .systemFont(ofSize: updateRowFontSize)
        .capHeight / 2
}

@MainActor
final class AboutContentModel: ObservableObject {
    @Published private(set) var metadata: AppMetadata
    @Published private(set) var updatePresentation: AboutUpdatePresentation?
    @Published private(set) var updateFeatureAvailable = false
    @Published private(set) var didCopyVersion = false
    @Published private(set) var diagnosticSaveState = AboutDiagnosticSaveState.idle
    @Published private(set) var rendererSelfTestState = AboutRendererSelfTestState.idle
    @Published private(set) var releaseNotesRevision = 0

    init(metadata: AppMetadata = .current()) {
        self.metadata = metadata
    }

    func apply(metadata: AppMetadata, updateFeatureAvailable: Bool) {
        self.metadata = metadata
        self.updateFeatureAvailable = updateFeatureAvailable
        didCopyVersion = false
        diagnosticSaveState = .idle
        releaseNotesRevision += 1
    }

    func apply(
        updatePresentation: AboutUpdatePresentation,
        updateFeatureAvailable: Bool
    ) {
        if self.updatePresentation?.releaseNotes != updatePresentation.releaseNotes {
            releaseNotesRevision += 1
        }
        self.updatePresentation = updatePresentation
        self.updateFeatureAvailable = updateFeatureAvailable
    }

    func showCopySucceeded() {
        didCopyVersion = true
    }

    func showCopyReady() {
        didCopyVersion = false
    }

    func showDiagnosticSaveStarted() {
        diagnosticSaveState = .saving
    }

    func showDiagnosticSaveSucceeded() {
        diagnosticSaveState = .saved
    }

    func showDiagnosticSaveReady() {
        diagnosticSaveState = .idle
    }

    func showRendererSelfTestStarted() {
        rendererSelfTestState = .running
    }

    func showRendererSelfTestReady() {
        rendererSelfTestState = .idle
    }
}

struct AboutContentView: View {
    @ObservedObject var model: AboutContentModel

    let onOpenProject: () -> Void
    let onPrimaryUpdateAction: (AboutUpdatePrimaryAction) -> Void
    let onSecondaryUpdateAction: (AboutUpdateSecondaryAction) -> Void
    let onCopyVersion: () -> Void
    let onRunRendererSelfTest: () -> Void
    let onSaveDiagnosticLogs: (DiagnosticExportWindow) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .padding(.horizontal, 28)
                .padding(.top, 14)

            releaseNotes

            footer
        }
        .frame(
            width: AboutLayout.windowSize.width,
            height: AboutLayout.windowSize.height
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text("md2png")
                        .font(.system(size: 27, weight: .semibold))

                    AboutBuildBadge(configuration: model.metadata.buildConfiguration)
                }

                Text(L10n.text(
                    "about.description",
                    defaultValue: "Turn clipboard Markdown into a polished PNG — locally and privately."
                ))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)

                HStack(spacing: 6) {
                    Text(model.metadata.versionBuildText())
                        .font(.system(size: 12, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Button(action: onCopyVersion) {
                        Image(systemName: model.didCopyVersion
                            ? "checkmark.circle.fill"
                            : "doc.on.doc")
                            .foregroundStyle(model.didCopyVersion
                                ? Color.green
                                : Color(nsColor: .secondaryLabelColor))
                    }
                    .buttonStyle(.plain)
                    .help(copyVersionHelp)
                    .accessibilityLabel(copyVersionLabel)
                }

                if model.updateFeatureAvailable,
                   let presentation = model.updatePresentation,
                   presentation.isVisible {
                    AboutUpdateCard(
                        presentation: presentation,
                        onPrimaryAction: onPrimaryUpdateAction,
                        onSecondaryAction: onSecondaryUpdateAction
                    )
                    .frame(
                        height: AboutLayout.detailedUpdateHeight,
                        alignment: .top
                    )
                    .padding(.top, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
    }

    private var releaseNotes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(displayedReleaseNotesTitle)
                .font(.system(size: 15, weight: .semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(styledReleaseNotes)
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if model.updatePresentation?.releaseNotes?
                        .showsFullReleaseNotesAction == true {
                        Button {
                            onSecondaryUpdateAction(.viewFullReleaseNotes)
                        } label: {
                            Label(
                                L10n.text(
                                    "about.view_full_release_notes",
                                    defaultValue: "View Full Release Notes"
                                ),
                                systemImage: "arrow.up.right.square"
                            )
                            .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .id(model.releaseNotesRevision)
            .frame(maxHeight: .infinity)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            if model.metadata.projectURL != nil {
                Text(L10n.text("about.project", defaultValue: "Project"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Button(action: onOpenProject) {
                    Label(
                        L10n.text("about.open_project", defaultValue: "Open Project"),
                        systemImage: "arrow.up.right.square"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(model.metadata.projectURL?.absoluteString ?? "")
            }

            Spacer()

            Menu {
                Button(
                    AboutRendererSelfTestPresentation.buttonTitle(for: .idle),
                    action: onRunRendererSelfTest
                )

                Divider()

                Menu(
                    AboutDiagnosticSavePresentation.buttonTitle(for: .idle)
                ) {
                    ForEach(DiagnosticExportWindow.allCases, id: \.rawValue) { window in
                        Button(window.aboutMenuTitle) {
                            onSaveDiagnosticLogs(window)
                        }
                    }
                }
            } label: {
                Label(
                    AboutDiagnosticsPresentation.buttonTitle(
                        selfTestState: model.rendererSelfTestState,
                        saveState: model.diagnosticSaveState
                    ),
                    systemImage: AboutDiagnosticsPresentation.symbolName(
                        selfTestState: model.rendererSelfTestState,
                        saveState: model.diagnosticSaveState
                    )
                )
                .font(.system(size: 12))
                .foregroundStyle(model.diagnosticSaveState == .saved
                    ? Color.green
                    : Color.accentColor)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(
                model.rendererSelfTestState == .running
                    || model.diagnosticSaveState == .saving
            )
            .help(L10n.text(
                "about.diagnostics_help",
                defaultValue: "Runs the renderer self-test or saves privacy-safe logs. Nothing is uploaded."
            ))

            Button(
                L10n.text("about.done", defaultValue: "Done"),
                action: onClose
            )
            .keyboardShortcut(.defaultAction)
            .frame(minWidth: 80)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 24)
    }

    private var copyVersionLabel: String {
        L10n.text(
            "about.copy_version_info",
            defaultValue: "Copy Version Info"
        )
    }

    private var displayedReleaseNotesTitle: String {
        model.updatePresentation?.releaseNotes?.title ?? L10n.format(
            "about.whats_new",
            defaultValue: "What’s new in %@",
            model.metadata.version
        )
    }

    private var copyVersionHelp: String {
        model.didCopyVersion
            ? L10n.text("about.version_info_copied", defaultValue: "Copied")
            : copyVersionLabel
    }

    private var styledReleaseNotes: AttributedString {
        let headings = Set([
            L10n.text("release_section.added", defaultValue: "Added"),
            L10n.text("release_section.changed", defaultValue: "Changed"),
            L10n.text("release_section.fixed", defaultValue: "Fixed"),
            L10n.text("release_section.removed", defaultValue: "Removed"),
            L10n.text("release_section.deprecated", defaultValue: "Deprecated"),
            L10n.text("release_section.security", defaultValue: "Security")
        ])
        let releaseNotes = model.updatePresentation?.releaseNotes?.text
            ?? model.metadata.releaseNotes
        let lines = releaseNotes.components(separatedBy: .newlines)
        var output = AttributedString()

        for (index, line) in lines.enumerated() {
            var attributedLine = AttributedString(line)
            attributedLine.font = headings.contains(line)
                ? .system(size: 13, weight: .semibold)
                : .system(size: 13)
            attributedLine.foregroundColor = headings.contains(line)
                ? Color.primary
                : Color(nsColor: .textColor)
            output.append(attributedLine)
            if index < lines.count - 1 {
                output.append(AttributedString("\n"))
            }
        }

        return output
    }
}

private struct AboutBuildBadge: View {
    let configuration: AppBuildConfiguration

    var body: some View {
        Text(configuration.displayName())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(configuration.badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                configuration.badgeColor.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(configuration.badgeColor.opacity(0.38), lineWidth: 1)
            }
            .help(configuration.displayName())
    }
}

private struct AboutUpdateCard: View {
    let presentation: AboutUpdatePresentation
    let onPrimaryAction: (AboutUpdatePrimaryAction) -> Void
    let onSecondaryAction: (AboutUpdateSecondaryAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: AboutLayout.updateRowSpacing) {
                Image(systemName: presentation.symbolName)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: AboutLayout.updateRowIconSize,
                        height: AboutLayout.updateRowIconSize
                    )
                    .frame(
                        width: AboutLayout.updateRowHeight,
                        height: AboutLayout.updateRowHeight
                    )
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions[VerticalAlignment.center]
                            + AboutLayout.updateRowIconBaselineOffset
                    }
                    .foregroundStyle(presentation.tint.color)
                    .accessibilityHidden(true)

                AboutSelectableStatusLabel(
                    text: presentation.title,
                    accessibilityLabel: statusAccessibilityLabel,
                    toolTip: presentation.detail ?? presentation.title
                )
                .frame(minWidth: 1)
                .layoutPriority(1)

                if let secondaryAction = presentation.secondaryAction {
                    Button(secondaryAction.title) {
                        onSecondaryAction(secondaryAction.action)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: AboutLayout.updateRowFontSize))
                    .foregroundStyle(Color.accentColor)
                }

                if let primaryAction = presentation.primaryAction {
                    Button(primaryAction.title) {
                        onPrimaryAction(primaryAction.action)
                    }
                    .buttonStyle(.plain)
                    .font(.system(
                        size: AboutLayout.updateRowFontSize,
                        weight: primaryAction.isEmphasized ? .semibold : .regular
                    ))
                    .foregroundStyle(primaryAction.isEnabled
                        ? Color.accentColor
                        : Color(nsColor: .secondaryLabelColor))
                    .disabled(!primaryAction.isEnabled)
                    .help(primaryAction.toolTip ?? primaryAction.title)
                }

                Spacer(minLength: 0)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: AboutLayout.updateRowHeight,
                alignment: .leading
            )

            if let detail = presentation.detail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, AboutLayout.updateRowHeight + AboutLayout.updateRowSpacing)
                    .help(detail)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 7)
        .frame(
            maxWidth: .infinity,
            minHeight: AboutLayout.detailedUpdateHeight,
            maxHeight: AboutLayout.detailedUpdateHeight,
            alignment: presentation.detail == nil ? .leading : .topLeading
        )
        .background(
            Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .help(L10n.text(
            "about.check_for_updates_help",
            defaultValue: "Checks the signed update feed only when you choose Check for Updates."
        ))
    }

    private var statusAccessibilityLabel: String {
        presentation.detail.map { "\(presentation.title). \($0)" }
            ?? presentation.title
    }
}

private final class SelectAllOnDoubleClickTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            selectText(nil)
        }
    }
}

private struct AboutSelectableStatusLabel: NSViewRepresentable {
    static let identifier = NSUserInterfaceItemIdentifier("AboutUpdateStatusLabel")

    let text: String
    let accessibilityLabel: String
    let toolTip: String

    func makeNSView(context: Context) -> NSTextField {
        let textField = SelectAllOnDoubleClickTextField(labelWithString: "")
        textField.identifier = Self.identifier
        textField.font = .systemFont(ofSize: AboutLayout.updateRowFontSize)
        textField.isSelectable = true
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byTruncatingTail
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        textField.stringValue = text
        textField.setAccessibilityLabel(accessibilityLabel)
        textField.toolTip = toolTip
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textField: NSTextField,
        context: Context
    ) -> CGSize? {
        let intrinsicSize = textField.intrinsicContentSize
        return CGSize(
            width: min(proposal.width ?? intrinsicSize.width, intrinsicSize.width),
            height: max(AboutLayout.updateRowHeight, intrinsicSize.height)
        )
    }
}

private extension AppBuildConfiguration {
    var badgeColor: Color {
        switch self {
        case .debug: .orange
        case .release: .blue
        }
    }
}

private extension AboutUpdateTint {
    var color: Color {
        switch self {
        case .green: .green
        case .blue: .blue
        case .orange: .orange
        }
    }
}
