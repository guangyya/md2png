import AppKit

enum AboutLayout {
    static let windowSize = NSSize(width: 560, height: 490)
    static let compactUpdateHeight: CGFloat = 36
    static let detailedUpdateHeight: CGFloat = 66
}

final class BuildBadgeView: NSView {
    private let textLabel = NSTextField(labelWithString: "")
    private(set) var configuration: AppBuildConfiguration = .debug

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        textLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        textLabel.alignment = .center
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)

        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = textLabel.intrinsicContentSize
        return NSSize(width: labelSize.width + 16, height: labelSize.height + 6)
    }

    func configure(_ configuration: AppBuildConfiguration) {
        self.configuration = configuration
        textLabel.stringValue = configuration.displayName()
        let tintColor: NSColor
        switch configuration {
        case .debug:
            tintColor = .systemOrange
        case .release:
            tintColor = .systemBlue
        }
        textLabel.textColor = tintColor
        layer?.backgroundColor = tintColor.withAlphaComponent(0.12).cgColor
        layer?.borderColor = tintColor.withAlphaComponent(0.38).cgColor
        toolTip = configuration.displayName()
        invalidateIntrinsicContentSize()
    }
}

final class UpdateStatusCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.07).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.20).cgColor
    }
}

final class SelectAllOnDoubleClickTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            selectText(nil)
        }
    }
}

@MainActor
final class AboutContentView: NSView {
    var onOpenProject: (() -> Void)?
    var onPrimaryUpdateAction: ((AboutUpdatePrimaryAction) -> Void)?
    var onSecondaryUpdateAction: ((AboutUpdateSecondaryAction) -> Void)?
    var onCopyVersion: (() -> Void)?
    var onClose: (() -> Void)?

    private let versionLabel = NSTextField(labelWithString: "")
    private let buildBadgeView = BuildBadgeView()
    private let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let releaseHeadingLabel = NSTextField(labelWithString: "")
    private let releaseNotesView = NSTextView()
    private let notesScrollView = NSScrollView()
    private let updateSlot = NSView()
    private let updateRow = UpdateStatusCardView()
    private let updateStatusIcon = NSImageView()
    private let updateStatusLabel = SelectAllOnDoubleClickTextField(labelWithString: "")
    private let updateDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let updateActionButton = NSButton()
    private let secondaryUpdateButton = NSButton()
    private let projectTitle = NSTextField(labelWithString: "")
    private let projectButton = NSButton()
    private let copyVersionButton = NSButton()
    private var updateRowHeightConstraint: NSLayoutConstraint!
    private var primaryUpdateAction: AboutUpdatePrimaryAction?
    private var secondaryUpdateAction: AboutUpdateSecondaryAction?

    init() {
        super.init(frame: NSRect(origin: .zero, size: AboutLayout.windowSize))
        configureContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(metadata: AppMetadata, updateFeatureAvailable: Bool) {
        buildBadgeView.configure(metadata.buildConfiguration)
        versionLabel.stringValue = metadata.versionBuildText()
        releaseHeadingLabel.stringValue = L10n.format(
            "about.whats_new",
            defaultValue: "What’s new in %@",
            metadata.version
        )
        applyReleaseNotesStyle(metadata.releaseNotes)
        projectTitle.isHidden = metadata.projectURL == nil
        projectButton.isHidden = metadata.projectURL == nil
        projectButton.title = L10n.text(
            "about.open_project",
            defaultValue: "Open Project"
        )
        projectButton.toolTip = metadata.projectURL?.absoluteString
        updateSlot.isHidden = !updateFeatureAvailable
        updateRow.toolTip = L10n.text(
            "about.check_for_updates_help",
            defaultValue: "Checks the signed update feed only when you choose Check for Updates."
        )
        showCopyReady()
    }

    func apply(
        updatePresentation presentation: AboutUpdatePresentation,
        updateFeatureAvailable: Bool
    ) {
        updateSlot.isHidden = !updateFeatureAvailable
        guard updateFeatureAvailable, presentation.isVisible else {
            updateRow.isHidden = true
            primaryUpdateAction = nil
            secondaryUpdateAction = nil
            return
        }

        updateRow.isHidden = false
        updateStatusIcon.image = NSImage(
            systemSymbolName: presentation.symbolName,
            accessibilityDescription: nil
        )
        updateStatusIcon.contentTintColor = presentation.tint.color
        updateStatusLabel.stringValue = presentation.title
        updateStatusLabel.setAccessibilityLabel(
            presentation.detail.map { "\(presentation.title). \($0)" }
                ?? presentation.title
        )
        updateStatusLabel.toolTip = presentation.detail ?? presentation.title
        updateDetailLabel.isHidden = presentation.detail == nil
        updateDetailLabel.stringValue = presentation.detail ?? ""
        updateDetailLabel.toolTip = presentation.detail
        updateRowHeightConstraint.constant = presentation.detail == nil
            ? AboutLayout.compactUpdateHeight
            : AboutLayout.detailedUpdateHeight

        primaryUpdateAction = presentation.primaryAction?.action
        updateActionButton.isHidden = presentation.primaryAction == nil
        updateActionButton.title = presentation.primaryAction?.title ?? ""
        updateActionButton.isEnabled = presentation.primaryAction?.isEnabled ?? false
        updateActionButton.isBordered = false
        updateActionButton.bezelColor = nil
        updateActionButton.font = .systemFont(
            ofSize: 12,
            weight: presentation.primaryAction?.isEmphasized == true ? .semibold : .regular
        )
        updateActionButton.contentTintColor = presentation.primaryAction?.isEnabled == true
            ? .linkColor
            : .secondaryLabelColor
        updateActionButton.toolTip = presentation.primaryAction?.toolTip

        secondaryUpdateAction = presentation.secondaryAction?.action
        secondaryUpdateButton.isHidden = presentation.secondaryAction == nil
        secondaryUpdateButton.title = presentation.secondaryAction?.title ?? ""
    }

    func showCopySucceeded() {
        copyVersionButton.contentTintColor = .systemGreen
        copyVersionButton.image = NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: nil
        )
        copyVersionButton.toolTip = L10n.text(
            "about.version_info_copied",
            defaultValue: "Copied"
        )
    }

    func showCopyReady() {
        let copyLabel = L10n.text(
            "about.copy_version_info",
            defaultValue: "Copy Version Info"
        )
        copyVersionButton.title = ""
        copyVersionButton.toolTip = copyLabel
        copyVersionButton.setAccessibilityLabel(copyLabel)
        copyVersionButton.contentTintColor = .secondaryLabelColor
        copyVersionButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: nil
        )
    }

    func updateReleaseNotesLayout() {
        let width = max(1, notesScrollView.contentSize.width)
        releaseNotesView.setFrameSize(NSSize(
            width: width,
            height: notesScrollView.contentSize.height
        ))
        releaseNotesView.textContainer?.containerSize = NSSize(
            width: width,
            height: .greatestFiniteMagnitude
        )
        if let textContainer = releaseNotesView.textContainer {
            releaseNotesView.layoutManager?.ensureLayout(for: textContainer)
            if let layoutManager = releaseNotesView.layoutManager {
                let usedHeight = layoutManager.usedRect(for: textContainer).height
                releaseNotesView.setFrameSize(NSSize(
                    width: width,
                    height: max(notesScrollView.contentSize.height, usedHeight + 24)
                ))
            }
        }
        releaseNotesView.setSelectedRange(NSRange(location: 0, length: 0))
        notesScrollView.contentView.scroll(to: .zero)
        notesScrollView.reflectScrolledClipView(notesScrollView.contentView)
    }

#if DEBUG
    var displayedBuildConfiguration: AppBuildConfiguration { buildBadgeView.configuration }
    var displayedProjectButtonTitle: String { projectButton.title }
    var displayedProjectButtonIsHidden: Bool { projectButton.isHidden }
    var displayedUpdateButtonTitle: String { updateActionButton.title }
    var displayedUpdateButtonIsHidden: Bool { updateRow.isHidden }
    var displayedUpdateButtonIsEnabled: Bool { updateActionButton.isEnabled }
    var displayedUpdateStatus: String { updateStatusLabel.stringValue }
    var displayedUpdateDetail: String { updateDetailLabel.stringValue }
    var displayedUpdateDetailMaximumNumberOfLines: Int {
        updateDetailLabel.maximumNumberOfLines
    }
    var displayedUpdateDetailLineBreakMode: NSLineBreakMode {
        updateDetailLabel.lineBreakMode
    }
    var displayedReleasesFallbackIsHidden: Bool { secondaryUpdateButton.isHidden }
    var displayedSecondaryUpdateButtonTitle: String { secondaryUpdateButton.title }
    var displayedCopyVersionButtonToolTip: String? { copyVersionButton.toolTip }
    var displayedVersionBuild: String { versionLabel.stringValue }
    var releaseNotesVisibleOrigin: NSPoint { notesScrollView.contentView.bounds.origin }
    var displayedUpdateCardFrame: NSRect { frameInContent(updateRow) }
    var displayedReleaseHeadingFrame: NSRect { frameInContent(releaseHeadingLabel) }
    var displayedDescriptionFrame: NSRect { frameInContent(descriptionLabel) }
    var displayedUpdateStatusSelectedRange: NSRange? {
        updateStatusLabel.currentEditor()?.selectedRange
    }

    func selectAllUpdateStatusForTesting() {
        updateStatusLabel.selectText(nil)
    }

    private func frameInContent(_ view: NSView) -> NSRect {
        guard let superview = view.superview else { return .zero }
        return superview.convert(view.frame, to: self)
    }
#endif

    private func configureContent() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "md2png")
        titleLabel.font = .systemFont(ofSize: 27, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleRow = NSStackView(views: [titleLabel, buildBadgeView])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 10
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        versionLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        copyVersionButton.title = ""
        copyVersionButton.target = self
        copyVersionButton.action = #selector(copyVersionRequested)
        copyVersionButton.isBordered = false
        copyVersionButton.controlSize = .small
        copyVersionButton.imagePosition = .imageOnly
        copyVersionButton.translatesAutoresizingMaskIntoConstraints = false
        showCopyReady()

        let versionRow = NSStackView(views: [versionLabel, copyVersionButton])
        versionRow.orientation = .horizontal
        versionRow.alignment = .centerY
        versionRow.spacing = 6
        versionRow.translatesAutoresizingMaskIntoConstraints = false

        updateSlot.translatesAutoresizingMaskIntoConstraints = false
        updateRow.translatesAutoresizingMaskIntoConstraints = false

        updateStatusIcon.imageScaling = .scaleProportionallyDown
        updateStatusIcon.translatesAutoresizingMaskIntoConstraints = false

        updateStatusLabel.font = .systemFont(ofSize: 11.5)
        updateStatusLabel.isSelectable = true
        updateStatusLabel.maximumNumberOfLines = 1
        updateStatusLabel.lineBreakMode = .byTruncatingTail
        updateStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateStatusLabel.translatesAutoresizingMaskIntoConstraints = false

        updateDetailLabel.font = .systemFont(ofSize: 10.5)
        updateDetailLabel.textColor = .secondaryLabelColor
        updateDetailLabel.maximumNumberOfLines = 2
        updateDetailLabel.lineBreakMode = .byWordWrapping
        updateDetailLabel.preferredMaxLayoutWidth = 351
        updateDetailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateDetailLabel.translatesAutoresizingMaskIntoConstraints = false

        updateActionButton.target = self
        updateActionButton.action = #selector(primaryUpdateActionRequested)
        updateActionButton.bezelStyle = .rounded
        updateActionButton.controlSize = .small
        updateActionButton.translatesAutoresizingMaskIntoConstraints = false

        secondaryUpdateButton.title = L10n.text(
            "about.view_all_releases",
            defaultValue: "View Releases"
        )
        secondaryUpdateButton.target = self
        secondaryUpdateButton.action = #selector(secondaryUpdateActionRequested)
        secondaryUpdateButton.isBordered = false
        secondaryUpdateButton.font = .systemFont(ofSize: 11)
        secondaryUpdateButton.contentTintColor = .linkColor
        secondaryUpdateButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [
            updateStatusIcon, updateStatusLabel, updateDetailLabel,
            secondaryUpdateButton, updateActionButton
        ] {
            updateRow.addSubview(view)
        }
        updateSlot.addSubview(updateRow)

        descriptionLabel.stringValue = L10n.text(
            "about.description",
            defaultValue: "Turn clipboard Markdown into a polished PNG — locally and privately."
        )
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 1
        descriptionLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.preferredMaxLayoutWidth = 396
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        let headerText = NSStackView(views: [titleRow, descriptionLabel, versionRow, updateSlot])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 5
        headerText.setCustomSpacing(2, after: titleRow)
        headerText.setCustomSpacing(10, after: versionRow)
        headerText.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        releaseHeadingLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        releaseHeadingLabel.translatesAutoresizingMaskIntoConstraints = false

        releaseNotesView.isEditable = false
        releaseNotesView.isSelectable = true
        releaseNotesView.drawsBackground = false
        releaseNotesView.font = .systemFont(ofSize: 13)
        releaseNotesView.textColor = .labelColor
        releaseNotesView.textContainerInset = NSSize(width: 12, height: 10)
        releaseNotesView.isRichText = false
        releaseNotesView.isHorizontallyResizable = false
        releaseNotesView.isVerticallyResizable = true
        releaseNotesView.autoresizingMask = [.width]
        releaseNotesView.textContainer?.widthTracksTextView = true
        releaseNotesView.frame = NSRect(x: 0, y: 0, width: 480, height: 205)

        notesScrollView.documentView = releaseNotesView
        notesScrollView.hasVerticalScroller = true
        notesScrollView.autohidesScrollers = true
        notesScrollView.drawsBackground = true
        notesScrollView.backgroundColor = .controlBackgroundColor
        notesScrollView.borderType = .noBorder
        notesScrollView.wantsLayer = true
        notesScrollView.layer?.cornerRadius = 10
        notesScrollView.layer?.cornerCurve = .continuous
        notesScrollView.layer?.borderWidth = 1
        notesScrollView.layer?.borderColor = NSColor.separatorColor.cgColor
        notesScrollView.translatesAutoresizingMaskIntoConstraints = false

        projectTitle.stringValue = L10n.text("about.project", defaultValue: "Project")
        projectTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        projectTitle.textColor = .secondaryLabelColor
        projectTitle.translatesAutoresizingMaskIntoConstraints = false

        projectButton.target = self
        projectButton.action = #selector(openProjectRequested)
        projectButton.isBordered = false
        projectButton.font = .systemFont(ofSize: 12)
        projectButton.contentTintColor = .linkColor
        projectButton.alignment = .left
        projectButton.image = NSImage(
            systemSymbolName: "arrow.up.right.square",
            accessibilityDescription: nil
        )
        projectButton.imagePosition = .imageLeading
        projectButton.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(
            title: L10n.text("about.done", defaultValue: "Done"),
            target: self,
            action: #selector(closeRequested)
        )
        closeButton.keyEquivalent = "\r"
        closeButton.bezelStyle = .rounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [
            iconView, headerText, divider, releaseHeadingLabel, notesScrollView,
            projectTitle, projectButton, closeButton
        ] {
            addSubview(view)
        }

        updateRowHeightConstraint = updateRow.heightAnchor.constraint(
            equalToConstant: AboutLayout.compactUpdateHeight
        )

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            iconView.widthAnchor.constraint(equalToConstant: 88),
            iconView.heightAnchor.constraint(equalToConstant: 88),

            headerText.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 20),
            headerText.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            headerText.topAnchor.constraint(equalTo: iconView.topAnchor),

            descriptionLabel.widthAnchor.constraint(equalTo: headerText.widthAnchor),
            descriptionLabel.heightAnchor.constraint(equalToConstant: 20),
            updateSlot.widthAnchor.constraint(equalTo: headerText.widthAnchor),
            updateSlot.heightAnchor.constraint(equalToConstant: AboutLayout.detailedUpdateHeight),
            updateRow.leadingAnchor.constraint(equalTo: updateSlot.leadingAnchor),
            updateRow.trailingAnchor.constraint(equalTo: updateSlot.trailingAnchor),
            updateRow.topAnchor.constraint(equalTo: updateSlot.topAnchor),
            updateRowHeightConstraint,

            updateStatusIcon.leadingAnchor.constraint(equalTo: updateRow.leadingAnchor, constant: 10),
            updateStatusIcon.topAnchor.constraint(equalTo: updateRow.topAnchor, constant: 9),
            updateStatusIcon.widthAnchor.constraint(equalToConstant: 18),
            updateStatusIcon.heightAnchor.constraint(equalToConstant: 18),

            updateStatusLabel.leadingAnchor.constraint(equalTo: updateStatusIcon.trailingAnchor, constant: 7),
            updateStatusLabel.centerYAnchor.constraint(equalTo: updateStatusIcon.centerYAnchor),
            updateStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: secondaryUpdateButton.leadingAnchor, constant: -8),

            updateDetailLabel.leadingAnchor.constraint(equalTo: updateStatusLabel.leadingAnchor),
            updateDetailLabel.trailingAnchor.constraint(equalTo: updateRow.trailingAnchor, constant: -10),
            updateDetailLabel.topAnchor.constraint(equalTo: updateStatusLabel.bottomAnchor, constant: 3),
            updateDetailLabel.bottomAnchor.constraint(lessThanOrEqualTo: updateRow.bottomAnchor, constant: -7),

            secondaryUpdateButton.centerYAnchor.constraint(equalTo: updateStatusIcon.centerYAnchor),
            secondaryUpdateButton.trailingAnchor.constraint(equalTo: updateActionButton.leadingAnchor, constant: -8),

            updateActionButton.centerYAnchor.constraint(equalTo: updateStatusIcon.centerYAnchor),
            updateActionButton.trailingAnchor.constraint(equalTo: updateRow.trailingAnchor, constant: -10),

            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            divider.topAnchor.constraint(greaterThanOrEqualTo: iconView.bottomAnchor, constant: 22),
            divider.topAnchor.constraint(equalTo: headerText.bottomAnchor, constant: 22),

            releaseHeadingLabel.leadingAnchor.constraint(equalTo: divider.leadingAnchor),
            releaseHeadingLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 20),

            notesScrollView.leadingAnchor.constraint(equalTo: divider.leadingAnchor),
            notesScrollView.trailingAnchor.constraint(equalTo: divider.trailingAnchor),
            notesScrollView.topAnchor.constraint(equalTo: releaseHeadingLabel.bottomAnchor, constant: 10),
            notesScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            notesScrollView.bottomAnchor.constraint(equalTo: projectTitle.topAnchor, constant: -18),

            projectTitle.leadingAnchor.constraint(equalTo: divider.leadingAnchor),
            projectButton.leadingAnchor.constraint(equalTo: projectTitle.trailingAnchor, constant: 10),
            projectButton.centerYAnchor.constraint(equalTo: projectTitle.centerYAnchor),
            projectButton.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -16),

            closeButton.trailingAnchor.constraint(equalTo: divider.trailingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: projectTitle.centerYAnchor),
            closeButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
    }

    private func applyReleaseNotesStyle(_ notes: String) {
        let headings = Set([
            L10n.text("release_section.added", defaultValue: "Added"),
            L10n.text("release_section.changed", defaultValue: "Changed"),
            L10n.text("release_section.fixed", defaultValue: "Fixed"),
            L10n.text("release_section.removed", defaultValue: "Removed"),
            L10n.text("release_section.deprecated", defaultValue: "Deprecated"),
            L10n.text("release_section.security", defaultValue: "Security")
        ])
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 4
        let output = NSMutableAttributedString()
        let lines = notes.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: headings.contains(line)
                    ? NSFont.systemFont(ofSize: 13, weight: .semibold)
                    : NSFont.systemFont(ofSize: 13),
                .foregroundColor: headings.contains(line)
                    ? NSColor.labelColor
                    : NSColor.textColor,
                .paragraphStyle: paragraphStyle
            ]
            output.append(NSAttributedString(string: line, attributes: attributes))
            if index < lines.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }
        releaseNotesView.textStorage?.setAttributedString(output)
    }

    @objc private func openProjectRequested() {
        onOpenProject?()
    }

    @objc private func primaryUpdateActionRequested() {
        guard let primaryUpdateAction else { return }
        onPrimaryUpdateAction?(primaryUpdateAction)
    }

    @objc private func secondaryUpdateActionRequested() {
        guard let secondaryUpdateAction else { return }
        onSecondaryUpdateAction?(secondaryUpdateAction)
    }

    @objc private func copyVersionRequested() {
        onCopyVersion?()
    }

    @objc private func closeRequested() {
        onClose?()
    }
}

private extension AboutUpdateTint {
    var color: NSColor {
        switch self {
        case .green: .systemGreen
        case .blue: .systemBlue
        case .orange: .systemOrange
        }
    }
}
