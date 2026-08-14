import AppKit

enum AppBuildConfiguration: Equatable {
    case debug
    case release

    static var current: AppBuildConfiguration {
#if DEBUG
        .debug
#else
        .release
#endif
    }

    func displayName(bundle: Bundle? = nil) -> String {
        switch self {
        case .debug:
            return L10n.text("about.build_debug", defaultValue: "DEBUG", bundle: bundle)
        case .release:
            return L10n.text("about.build_release", defaultValue: "RELEASE", bundle: bundle)
        }
    }
}

struct AppMetadata {
    let version: String
    let build: String
    let buildConfiguration: AppBuildConfiguration
    let releaseNotes: String
    let projectURL: URL?

    init(
        version: String,
        build: String,
        buildConfiguration: AppBuildConfiguration = .current,
        releaseNotes: String,
        projectURL: URL?
    ) {
        self.version = version
        self.build = build
        self.buildConfiguration = buildConfiguration
        self.releaseNotes = releaseNotes
        self.projectURL = projectURL
    }

    static func current(bundle: Bundle = .main) -> AppMetadata {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? L10n.text("about.development", defaultValue: "Development")
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let notes: String

        if let changelogURL = AppResources.changelogURL(resourcesURL: bundle.resourceURL),
           let changelog = try? String(contentsOf: changelogURL, encoding: .utf8),
           let parsedNotes = ChangelogParser.releaseNotes(for: version, in: changelog) {
            notes = parsedNotes
        } else {
            notes = L10n.text(
                "about.release_notes_unavailable",
                defaultValue: "Release notes are not available in this build."
            )
        }

        return AppMetadata(
            version: version,
            build: build,
            buildConfiguration: .current,
            releaseNotes: notes,
            projectURL: ProjectLinks.project
        )
    }

    func versionInfo(
        macOSVersion: String = AppRuntimeInfo.macOSVersion,
        architecture: String = AppRuntimeInfo.architecture,
        localizationBundle: Bundle? = nil
    ) -> String {
        L10n.format(
            "about.version_info",
            defaultValue: "md2png %@ (%@) · %@ · macOS %@ · %@",
            bundle: localizationBundle,
            version,
            build,
            buildConfiguration.displayName(bundle: localizationBundle),
            macOSVersion,
            architecture
        )
    }
}

enum AppRuntimeInfo {
    static var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static var architecture: String {
#if arch(arm64)
        "arm64"
#elseif arch(x86_64)
        "x86_64"
#else
        "unknown"
#endif
    }
}

enum ChangelogParser {
    static func releaseNotes(
        for version: String,
        in changelog: String,
        localizationBundle: Bundle? = nil
    ) -> String? {
        let headingPrefix = "## [\(version)]"
        let lines = changelog.components(separatedBy: .newlines)
        guard let headingIndex = lines.firstIndex(where: { $0.hasPrefix(headingPrefix) }) else {
            return nil
        }

        let section = lines[(headingIndex + 1)...].prefix { !$0.hasPrefix("## [") }
        var blocks: [String] = []
        var currentBullet: String?

        func flushBullet() {
            if let currentBullet {
                blocks.append("• " + currentBullet)
            }
            currentBullet = nil
        }

        for rawLine in section {
            let line = rawLine.replacingOccurrences(of: "`", with: "")
            if rawLine.hasPrefix("### ") {
                flushBullet()
                blocks.append(localizedSectionHeading(
                    String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces),
                    bundle: localizationBundle
                ))
            } else if rawLine.hasPrefix("- ") {
                flushBullet()
                currentBullet = String(line.dropFirst(2))
                    .trimmingCharacters(in: .whitespaces)
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                let continuation = line.trimmingCharacters(in: .whitespaces)
                if currentBullet != nil {
                    currentBullet! += " " + continuation
                } else {
                    blocks.append(continuation)
                }
            }
        }
        flushBullet()

        var formatted = ""
        for block in blocks {
            if formatted.isEmpty {
                formatted = block
            } else if !block.hasPrefix("• ") {
                formatted += "\n\n" + block
            } else {
                formatted += "\n" + block
            }
        }

        return formatted.isEmpty ? nil : formatted
    }

    private static func localizedSectionHeading(_ heading: String, bundle: Bundle?) -> String {
        let key: String
        switch heading {
        case "Added": key = "release_section.added"
        case "Changed": key = "release_section.changed"
        case "Fixed": key = "release_section.fixed"
        case "Removed": key = "release_section.removed"
        case "Deprecated": key = "release_section.deprecated"
        case "Security": key = "release_section.security"
        default: return heading
        }
        return L10n.text(key, defaultValue: heading, bundle: bundle)
    }
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
final class AboutController: NSWindowController {
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
    private let updateController: UpdateController
    private var updateStatusObserverID: UUID?
    private var updateRowHeightConstraint: NSLayoutConstraint!
    private var projectURL: URL?
    private var updateFeatureAvailable = false
    private var versionInfo = ""
    private var copyResetWorkItem: DispatchWorkItem?

#if DEBUG
    var displayedBuildConfiguration: AppBuildConfiguration {
        buildBadgeView.configuration
    }
    var displayedProjectButtonTitle: String { projectButton.title }
    var displayedProjectButtonIsHidden: Bool { projectButton.isHidden }
    var displayedUpdateButtonTitle: String { updateActionButton.title }
    var displayedUpdateButtonIsHidden: Bool { updateRow.isHidden }
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
    var displayedVersionInfo: String { versionInfo }
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
        guard let contentView = window?.contentView,
              let superview = view.superview else { return .zero }
        return superview.convert(view.frame, to: contentView)
    }
#endif

    init(updateController: UpdateController = UpdateController()) {
        self.updateController = updateController
        let window = PreviewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 490),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("about.window_title", defaultValue: "About md2png")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        configureContent()
        updateStatusObserverID = updateController.observeStatus { [weak self] status in
            self?.applyUpdateStatus(status)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(metadata: AppMetadata = .current()) {
        buildBadgeView.configure(metadata.buildConfiguration)
        versionLabel.stringValue = L10n.format(
            "about.version_build",
            defaultValue: "Version %@  •  Build %@",
            metadata.version,
            metadata.build
        )
        releaseHeadingLabel.stringValue = L10n.format(
            "about.whats_new",
            defaultValue: "What’s new in %@",
            metadata.version
        )
        applyReleaseNotesStyle(metadata.releaseNotes)
        projectURL = metadata.projectURL
        updateFeatureAvailable = metadata.projectURL.flatMap(
            GitHubRepository.init(projectURL:)
        ) != nil
        updateSlot.isHidden = !updateFeatureAvailable
        versionInfo = metadata.versionInfo()
        projectTitle.isHidden = metadata.projectURL == nil
        projectButton.isHidden = metadata.projectURL == nil
        projectButton.title = L10n.text(
            "about.open_project",
            defaultValue: "Open Project"
        )
        projectButton.toolTip = metadata.projectURL?.absoluteString
        updateRow.toolTip = L10n.text(
            "about.check_for_updates_help",
            defaultValue: "Checks GitHub when About opens; successful results are cached for 24 hours."
        )
        applyUpdateStatus(updateController.status)
        resetCopyVersionButton()

        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.contentView?.layoutSubtreeIfNeeded()
        updateReleaseNotesLayout()
        if updateFeatureAvailable {
            updateController.refreshIfNeeded()
        }
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

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
        copyVersionButton.action = #selector(copyVersionInfo)
        copyVersionButton.isBordered = false
        copyVersionButton.controlSize = .small
        copyVersionButton.contentTintColor = .secondaryLabelColor
        copyVersionButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: nil
        )
        copyVersionButton.imagePosition = .imageOnly
        copyVersionButton.toolTip = L10n.text(
            "about.copy_version_info",
            defaultValue: "Copy Version Info"
        )
        copyVersionButton.setAccessibilityLabel(copyVersionButton.toolTip ?? "Copy Version Info")
        copyVersionButton.translatesAutoresizingMaskIntoConstraints = false

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
        updateActionButton.action = #selector(performUpdateAction)
        updateActionButton.bezelStyle = .rounded
        updateActionButton.controlSize = .small
        updateActionButton.translatesAutoresizingMaskIntoConstraints = false

        secondaryUpdateButton.title = L10n.text(
            "about.view_all_releases",
            defaultValue: "View Releases"
        )
        secondaryUpdateButton.target = self
        secondaryUpdateButton.action = #selector(performSecondaryUpdateAction)
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
        projectButton.action = #selector(openProject)
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
            action: #selector(closeAbout)
        )
        closeButton.keyEquivalent = "\r"
        closeButton.bezelStyle = .rounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [
            iconView, headerText, divider, releaseHeadingLabel, notesScrollView,
            projectTitle, projectButton, closeButton
        ] {
            contentView.addSubview(view)
        }

        updateRowHeightConstraint = updateRow.heightAnchor.constraint(equalToConstant: 36)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            iconView.widthAnchor.constraint(equalToConstant: 88),
            iconView.heightAnchor.constraint(equalToConstant: 88),

            headerText.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 20),
            headerText.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            headerText.topAnchor.constraint(equalTo: iconView.topAnchor),

            descriptionLabel.widthAnchor.constraint(equalTo: headerText.widthAnchor),
            descriptionLabel.heightAnchor.constraint(equalToConstant: 20),
            updateSlot.widthAnchor.constraint(equalTo: headerText.widthAnchor),
            updateSlot.heightAnchor.constraint(equalToConstant: 66),
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

            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
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
            closeButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
    }

    @objc private func openProject() {
        guard let projectURL else { return }
        NSWorkspace.shared.open(projectURL)
    }

    @objc private func performUpdateAction() {
        switch updateController.status.phase {
        case .updateAvailable, .failed(_, _, _, .some):
            updateController.downloadAvailableUpdate()
        case .downloading, .verifying, .opening:
            updateController.cancelUpdate()
        case .upToDate, .failed:
            updateController.checkAgain()
        case .readyToInstall:
            updateController.openDownloadedUpdate()
        case .unknown:
            break
        }
    }

    @objc private func performSecondaryUpdateAction() {
        if case .readyToInstall = updateController.status.phase {
            updateController.revealDownloadedUpdate()
        } else {
            updateController.viewReleasesFallback()
        }
    }

    private func applyUpdateStatus(_ status: UpdateStatus) {
        guard updateFeatureAvailable else {
            updateSlot.isHidden = true
            updateRow.isHidden = true
            return
        }
        updateSlot.isHidden = false
        let symbolName: String
        let tintColor: NSColor
        let title: String
        let actionTitle: String?
        let canPerformAction: Bool
        let emphasizesAction: Bool
        let secondaryActionTitle: String?
        var detail: String?

        switch status.phase {
        case .unknown:
            updateRow.isHidden = true
            return
        case let .upToDate(version):
            detail = nil
            symbolName = "checkmark.circle.fill"
            tintColor = .systemGreen
            title = L10n.format(
                "about.update_up_to_date",
                defaultValue: "Up to Date · %@",
                version.description
            )
            switch status.manualCheckFeedback {
            case .checking:
                actionTitle = L10n.text(
                    "about.update_checking",
                    defaultValue: "Checking…"
                )
            case .completed where status.nextManualCheckAt != nil:
                actionTitle = L10n.text(
                    "about.update_checked_recently",
                    defaultValue: "Checked just now"
                )
            case .none where status.nextManualCheckAt != nil:
                actionTitle = L10n.text(
                    "about.update_check_again_later",
                    defaultValue: "Check Again Later"
                )
            case .none, .completed:
                actionTitle = L10n.text(
                    "about.update_check_again",
                    defaultValue: "Check Again"
                )
            }
            canPerformAction = !status.isChecking && status.nextManualCheckAt == nil
            emphasizesAction = false
            secondaryActionTitle = nil
        case let .updateAvailable(update):
            detail = nil
            symbolName = "arrow.down.circle.fill"
            tintColor = .systemBlue
            title = L10n.format(
                "about.update_available",
                defaultValue: "Update available · %@",
                update.version.description
            )
            actionTitle = L10n.text(
                "about.update_download",
                defaultValue: "Download Update"
            )
            canPerformAction = !status.isChecking
            emphasizesAction = true
            secondaryActionTitle = nil
        case let .downloading(update, progressPercent):
            detail = nil
            symbolName = "arrow.down.circle"
            tintColor = .systemBlue
            title = L10n.format(
                "about.update_downloading_progress",
                defaultValue: "Downloading md2png %@ — %ld%%",
                update.version.description,
                progressPercent
            )
            actionTitle = L10n.text("common.cancel", defaultValue: "Cancel")
            canPerformAction = true
            emphasizesAction = false
            secondaryActionTitle = nil
        case let .verifying(update):
            detail = nil
            symbolName = "checkmark.shield"
            tintColor = .systemBlue
            title = L10n.format(
                "about.update_verifying_version",
                defaultValue: "Verifying md2png %@…",
                update.version.description
            )
            actionTitle = L10n.text("common.cancel", defaultValue: "Cancel")
            canPerformAction = true
            emphasizesAction = false
            secondaryActionTitle = nil
        case let .opening(update):
            detail = nil
            symbolName = "opticaldiscdrive"
            tintColor = .systemBlue
            title = L10n.format(
                "about.update_opening_version",
                defaultValue: "Opening md2png %@…",
                update.version.description
            )
            actionTitle = nil
            canPerformAction = false
            emphasizesAction = false
            secondaryActionTitle = nil
        case let .readyToInstall(update, _):
            detail = L10n.text(
                "about.update_ready_detail",
                defaultValue: "Downloaded — open the DMG and drag md2png into Applications."
            )
            symbolName = "checkmark.circle.fill"
            tintColor = .systemGreen
            title = L10n.format(
                "about.update_ready",
                defaultValue: "Ready to install · %@",
                update.version.description
            )
            actionTitle = L10n.text(
                "about.update_open_again",
                defaultValue: "Open"
            )
            canPerformAction = true
            emphasizesAction = true
            secondaryActionTitle = L10n.text(
                "about.update_show_in_finder",
                defaultValue: "Show in Finder"
            )
        case let .failed(message, releasesURL, _, availableUpdate):
            symbolName = "exclamationmark.triangle.fill"
            tintColor = .systemOrange
            detail = message
            title = availableUpdate == nil
                ? L10n.text(
                    "about.update_check_failed",
                    defaultValue: "Update check failed"
                )
                : L10n.text(
                    "about.update_download_failed",
                    defaultValue: "Download failed"
                )
            if availableUpdate == nil {
                if status.manualCheckFeedback == .checking {
                    actionTitle = L10n.text(
                        "about.update_checking",
                        defaultValue: "Checking…"
                    )
                } else if status.nextManualCheckAt != nil {
                    actionTitle = L10n.text(
                        "about.update_try_again_later",
                        defaultValue: "Try Again Later"
                    )
                } else {
                    actionTitle = L10n.text(
                        "about.update_retry_check",
                        defaultValue: "Try Again"
                    )
                }
            } else {
                actionTitle = L10n.text(
                    "about.update_retry_download",
                    defaultValue: "Retry Download"
                )
            }
            canPerformAction = !status.isChecking && (
                availableUpdate != nil || status.nextManualCheckAt == nil
            )
            emphasizesAction = true
            secondaryActionTitle = releasesURL == nil
                ? nil
                : L10n.text("about.view_all_releases", defaultValue: "View Releases")
        }

        updateRow.isHidden = false
        updateStatusIcon.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )
        updateStatusIcon.contentTintColor = tintColor
        updateStatusLabel.stringValue = title
        updateStatusLabel.setAccessibilityLabel(
            detail.map { "\(title). \($0)" } ?? title
        )
        updateStatusLabel.toolTip = detail ?? title
        updateDetailLabel.isHidden = detail == nil
        updateDetailLabel.stringValue = detail ?? ""
        updateDetailLabel.toolTip = detail
        updateRowHeightConstraint.constant = detail == nil ? 36 : 66
        updateActionButton.isHidden = actionTitle == nil
        updateActionButton.title = actionTitle ?? ""
        updateActionButton.isEnabled = canPerformAction
        updateActionButton.isBordered = false
        updateActionButton.bezelColor = nil
        updateActionButton.font = .systemFont(
            ofSize: 12,
            weight: emphasizesAction ? .semibold : .regular
        )
        updateActionButton.contentTintColor = canPerformAction
            ? .linkColor
            : .secondaryLabelColor
        secondaryUpdateButton.isHidden = secondaryActionTitle == nil
        secondaryUpdateButton.title = secondaryActionTitle ?? ""

        if !canPerformAction, let retryAt = status.nextManualCheckAt {
            updateActionButton.toolTip = L10n.format(
                "about.update_retry_after",
                defaultValue: "Try again after %@.",
                retryAt.formatted(date: .omitted, time: .shortened)
            )
        } else {
            updateActionButton.toolTip = nil
        }
    }

    @objc private func copyVersionInfo() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(versionInfo, forType: .string) else { return }

        copyResetWorkItem?.cancel()
        copyVersionButton.contentTintColor = .systemGreen
        copyVersionButton.image = NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: nil
        )
        copyVersionButton.toolTip = L10n.text(
            "about.version_info_copied",
            defaultValue: "Copied"
        )

        let workItem = DispatchWorkItem { [weak self] in
            self?.resetCopyVersionButton()
        }
        copyResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func resetCopyVersionButton() {
        copyResetWorkItem?.cancel()
        copyResetWorkItem = nil
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

    private func updateReleaseNotesLayout() {
        let width = max(1, notesScrollView.contentSize.width)
        releaseNotesView.setFrameSize(NSSize(
            width: width,
            height: notesScrollView.contentSize.height
        ))
        releaseNotesView.textContainer?.containerSize = NSSize(
            width: width,
            height: .greatestFiniteMagnitude
        )
        releaseNotesView.layoutManager?.ensureLayout(
            for: releaseNotesView.textContainer!
        )
        if let textContainer = releaseNotesView.textContainer,
           let layoutManager = releaseNotesView.layoutManager {
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            releaseNotesView.setFrameSize(NSSize(
                width: width,
                height: max(notesScrollView.contentSize.height, usedHeight + 24)
            ))
        }
        releaseNotesView.setSelectedRange(NSRange(location: 0, length: 0))
        notesScrollView.contentView.scroll(to: .zero)
        notesScrollView.reflectScrolledClipView(notesScrollView.contentView)
    }

    @objc private func closeAbout() {
        copyResetWorkItem?.cancel()
        close()
    }
}
