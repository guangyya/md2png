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

@MainActor
final class AboutController: NSWindowController {
    private let versionLabel = NSTextField(labelWithString: "")
    private let buildBadgeView = BuildBadgeView()
    private let releaseHeadingLabel = NSTextField(labelWithString: "")
    private let releaseNotesView = NSTextView()
    private let notesScrollView = NSScrollView()
    private let projectTitle = NSTextField(labelWithString: "")
    private let projectButton = NSButton()
    private let releasesButton = NSButton()
    private let copyVersionButton = NSButton()
    private let updateController = UpdateController()
    private var projectURL: URL?
    private var releasesURL: URL?
    private var versionInfo = ""
    private var copyResetWorkItem: DispatchWorkItem?

#if DEBUG
    var displayedBuildConfiguration: AppBuildConfiguration {
        buildBadgeView.configuration
    }
    var displayedProjectButtonTitle: String { projectButton.title }
    var displayedProjectButtonIsHidden: Bool { projectButton.isHidden }
    var displayedReleasesButtonTitle: String { releasesButton.title }
    var displayedReleasesButtonIsHidden: Bool { releasesButton.isHidden }
    var displayedCopyVersionButtonToolTip: String? { copyVersionButton.toolTip }
    var displayedVersionInfo: String { versionInfo }
    var releaseNotesVisibleOrigin: NSPoint { notesScrollView.contentView.bounds.origin }
#endif

    init() {
        let window = PreviewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("about.window_title", defaultValue: "About md2png")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        configureContent()
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
        releasesURL = metadata.projectURL.map(ProjectLinks.releasesURL(for:))
        versionInfo = metadata.versionInfo()
        projectTitle.isHidden = metadata.projectURL == nil
        projectButton.isHidden = metadata.projectURL == nil
        releasesButton.isHidden = releasesURL == nil
        projectButton.title = L10n.text(
            "about.open_project",
            defaultValue: "Open Project"
        )
        projectButton.toolTip = metadata.projectURL?.absoluteString
        releasesButton.title = L10n.text(
            "about.view_all_releases",
            defaultValue: "View All Releases…"
        )
        releasesButton.toolTip = releasesURL?.absoluteString
        resetCopyVersionButton()

        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.contentView?.layoutSubtreeIfNeeded()
        updateReleaseNotesLayout()
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

        let descriptionLabel = NSTextField(
            wrappingLabelWithString: L10n.text(
                "about.description",
                defaultValue: "Turn clipboard Markdown into a polished PNG — locally, privately, and without automatic sending."
            )
        )
        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 2
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        let headerText = NSStackView(views: [titleRow, versionRow, descriptionLabel])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 5
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

        releasesButton.target = self
        releasesButton.action = #selector(viewAllReleases)
        releasesButton.isBordered = false
        releasesButton.font = .systemFont(ofSize: 12)
        releasesButton.contentTintColor = .linkColor
        releasesButton.alignment = .left
        releasesButton.image = NSImage(
            systemSymbolName: "arrow.up.right.square",
            accessibilityDescription: nil
        )
        releasesButton.imagePosition = .imageLeading
        releasesButton.translatesAutoresizingMaskIntoConstraints = false

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
            projectTitle, projectButton, releasesButton, closeButton
        ] {
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            iconView.widthAnchor.constraint(equalToConstant: 88),
            iconView.heightAnchor.constraint(equalToConstant: 88),

            headerText.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 20),
            headerText.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            headerText.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            divider.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 22),

            releaseHeadingLabel.leadingAnchor.constraint(equalTo: divider.leadingAnchor),
            releaseHeadingLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 20),

            notesScrollView.leadingAnchor.constraint(equalTo: divider.leadingAnchor),
            notesScrollView.trailingAnchor.constraint(equalTo: divider.trailingAnchor),
            notesScrollView.topAnchor.constraint(equalTo: releaseHeadingLabel.bottomAnchor, constant: 10),
            notesScrollView.heightAnchor.constraint(equalToConstant: 205),

            projectTitle.leadingAnchor.constraint(equalTo: divider.leadingAnchor),
            projectTitle.topAnchor.constraint(equalTo: notesScrollView.bottomAnchor, constant: 18),
            projectTitle.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            projectButton.leadingAnchor.constraint(equalTo: projectTitle.trailingAnchor, constant: 10),
            projectButton.centerYAnchor.constraint(equalTo: projectTitle.centerYAnchor),
            releasesButton.leadingAnchor.constraint(equalTo: projectButton.trailingAnchor, constant: 14),
            releasesButton.centerYAnchor.constraint(equalTo: projectTitle.centerYAnchor),
            releasesButton.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -16),

            closeButton.trailingAnchor.constraint(equalTo: divider.trailingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: projectTitle.centerYAnchor),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
    }

    @objc private func openProject() {
        guard let projectURL else { return }
        NSWorkspace.shared.open(projectURL)
    }

    @objc private func viewAllReleases() {
        updateController.showReleasesPrompt(releasesURL: releasesURL)
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
        releaseNotesView.setFrameSize(NSSize(width: width, height: 205))
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
