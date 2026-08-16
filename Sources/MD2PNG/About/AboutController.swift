import AppKit

@MainActor
final class AboutController: NSWindowController {
    private let updateController: UpdateController
    private let aboutView = AboutContentView()
    private var updateStatusObserverID: UUID?
    private var projectURL: URL?
    private var updateFeatureAvailable = false
    private var versionInfo = ""
    private var copyResetWorkItem: DispatchWorkItem?

#if DEBUG
    var displayedBuildConfiguration: AppBuildConfiguration {
        aboutView.displayedBuildConfiguration
    }
    var displayedProjectButtonTitle: String { aboutView.displayedProjectButtonTitle }
    var displayedProjectButtonIsHidden: Bool { aboutView.displayedProjectButtonIsHidden }
    var displayedUpdateButtonTitle: String { aboutView.displayedUpdateButtonTitle }
    var displayedUpdateButtonIsHidden: Bool { aboutView.displayedUpdateButtonIsHidden }
    var displayedUpdateButtonIsEnabled: Bool { aboutView.displayedUpdateButtonIsEnabled }
    var displayedUpdateStatus: String { aboutView.displayedUpdateStatus }
    var displayedUpdateDetail: String { aboutView.displayedUpdateDetail }
    var displayedUpdateDetailMaximumNumberOfLines: Int {
        aboutView.displayedUpdateDetailMaximumNumberOfLines
    }
    var displayedUpdateDetailLineBreakMode: NSLineBreakMode {
        aboutView.displayedUpdateDetailLineBreakMode
    }
    var displayedReleasesFallbackIsHidden: Bool {
        aboutView.displayedReleasesFallbackIsHidden
    }
    var displayedSecondaryUpdateButtonTitle: String {
        aboutView.displayedSecondaryUpdateButtonTitle
    }
    var displayedCopyVersionButtonToolTip: String? {
        aboutView.displayedCopyVersionButtonToolTip
    }
    var displayedVersionBuild: String { aboutView.displayedVersionBuild }
    var displayedVersionInfo: String { versionInfo }
    var releaseNotesVisibleOrigin: NSPoint { aboutView.releaseNotesVisibleOrigin }
    var displayedUpdateCardFrame: NSRect { aboutView.displayedUpdateCardFrame }
    var displayedReleaseHeadingFrame: NSRect { aboutView.displayedReleaseHeadingFrame }
    var displayedDescriptionFrame: NSRect { aboutView.displayedDescriptionFrame }
    var displayedUpdateStatusSelectedRange: NSRange? {
        aboutView.displayedUpdateStatusSelectedRange
    }

    func selectAllUpdateStatusForTesting() {
        aboutView.selectAllUpdateStatusForTesting()
    }
#endif

    init(updateController: UpdateController = UpdateController()) {
        self.updateController = updateController
        let window = PreviewWindow(
            contentRect: NSRect(origin: .zero, size: AboutLayout.windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("about.window_title", defaultValue: "About md2png")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = aboutView
        bindContentActions()
        updateStatusObserverID = updateController.observeStatus { [weak self] status in
            self?.applyUpdateStatus(status)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(metadata: AppMetadata = .current()) {
        projectURL = metadata.projectURL
        updateFeatureAvailable = metadata.projectURL.flatMap(
            GitHubRepository.init(projectURL:)
        ) != nil && updateController.allowsUpdatePresentation
        versionInfo = metadata.versionInfo()
        aboutView.apply(
            metadata: metadata,
            updateFeatureAvailable: updateFeatureAvailable
        )
        applyUpdateStatus(updateController.status)
        resetCopyVersionButton()

        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.contentView?.layoutSubtreeIfNeeded()
        aboutView.updateReleaseNotesLayout()
    }

    private func bindContentActions() {
        aboutView.onOpenProject = { [weak self] in self?.openProject() }
        aboutView.onPrimaryUpdateAction = { [weak self] action in
            self?.performUpdateAction(action)
        }
        aboutView.onSecondaryUpdateAction = { [weak self] action in
            self?.performSecondaryUpdateAction(action)
        }
        aboutView.onCopyVersion = { [weak self] in self?.copyVersionInfo() }
        aboutView.onClose = { [weak self] in self?.closeAbout() }
    }

    private func openProject() {
        guard let projectURL else { return }
        NSWorkspace.shared.open(projectURL)
    }

    private func performUpdateAction(_ action: AboutUpdatePrimaryAction) {
        switch action {
        case .checkAgain:
            updateController.checkAgain()
        case .showUpdate:
            updateController.showStandardUpdateUI()
        case .download:
            updateController.downloadAvailableUpdate()
        case .cancel:
            updateController.cancelUpdate()
        case .openDownloadedUpdate:
            updateController.openDownloadedUpdate()
        }
    }

    private func performSecondaryUpdateAction(_ action: AboutUpdateSecondaryAction) {
        switch action {
        case .viewReleases:
            updateController.viewReleasesFallback()
        case .revealDownloadedUpdate:
            updateController.revealDownloadedUpdate()
        }
    }

    private func applyUpdateStatus(_ status: UpdateStatus) {
        let presentation = AboutUpdatePresentation.make(
            status: status,
            allowsInteractiveCheck: updateController.allowsInteractiveCheck,
            canDownload: updateController.canDownload
        )
        aboutView.apply(
            updatePresentation: presentation,
            updateFeatureAvailable: updateFeatureAvailable
        )
    }

    private func copyVersionInfo() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(versionInfo, forType: .string) else { return }

        copyResetWorkItem?.cancel()
        aboutView.showCopySucceeded()
        let workItem = DispatchWorkItem { [weak self] in
            self?.resetCopyVersionButton()
        }
        copyResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func resetCopyVersionButton() {
        copyResetWorkItem?.cancel()
        copyResetWorkItem = nil
        aboutView.showCopyReady()
    }

    private func closeAbout() {
        copyResetWorkItem?.cancel()
        close()
    }
}
