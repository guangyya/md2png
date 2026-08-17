import AppKit
import SwiftUI

@MainActor
final class AboutController: NSWindowController, NSWindowDelegate {
    private let updateController: UpdateController
    private let contentModel = AboutContentModel()
    private var updateStatusObserverID: UUID?
    private var projectURL: URL?
    private var updateFeatureAvailable = false
    private var versionInfo = ""
    private var copyResetWorkItem: DispatchWorkItem?

#if DEBUG
    var displayedBuildConfiguration: AppBuildConfiguration {
        contentModel.metadata.buildConfiguration
    }
    var displayedProjectButtonTitle: String {
        L10n.text("about.open_project", defaultValue: "Open Project")
    }
    var displayedProjectButtonIsHidden: Bool { contentModel.metadata.projectURL == nil }
    var displayedUpdateButtonTitle: String {
        contentModel.updatePresentation?.primaryAction?.title ?? ""
    }
    var displayedUpdateButtonIsHidden: Bool {
        !contentModel.updateFeatureAvailable
            || contentModel.updatePresentation?.isVisible != true
    }
    var displayedUpdateButtonIsEnabled: Bool {
        contentModel.updatePresentation?.primaryAction?.isEnabled ?? false
    }
    var displayedUpdateStatus: String {
        contentModel.updatePresentation?.title ?? ""
    }
    var displayedUpdateDetail: String {
        contentModel.updatePresentation?.detail ?? ""
    }
    var displayedUpdateDetailMaximumNumberOfLines: Int {
        2
    }
    var displayedUpdateDetailLineBreakMode: NSLineBreakMode {
        .byWordWrapping
    }
    var displayedReleasesFallbackIsHidden: Bool {
        contentModel.updatePresentation?.secondaryAction == nil
    }
    var displayedSecondaryUpdateButtonTitle: String {
        contentModel.updatePresentation?.secondaryAction?.title ?? ""
    }
    var displayedCopyVersionButtonToolTip: String? {
        contentModel.didCopyVersion
            ? L10n.text("about.version_info_copied", defaultValue: "Copied")
            : L10n.text("about.copy_version_info", defaultValue: "Copy Version Info")
    }
    var displayedVersionBuild: String { contentModel.metadata.versionBuildText() }
    var displayedVersionInfo: String { versionInfo }
    var usesSwiftUIHostingBoundary: Bool {
        window?.contentViewController is NSHostingController<AboutContentView>
    }
    var displayedUpdateCardHeight: CGFloat {
        AboutLayout.detailedUpdateHeight
    }
    var displayedReleaseNotesRevision: Int { contentModel.releaseNotesRevision }
    var displayedReleaseNotesTitle: String {
        contentModel.updatePresentation?.releaseNotes?.title ?? ""
    }
    var displayedReleaseNotesText: String {
        contentModel.updatePresentation?.releaseNotes?.text ?? contentModel.metadata.releaseNotes
    }
    var displaysFullReleaseNotesAction: Bool {
        contentModel.updatePresentation?.releaseNotes?.showsFullReleaseNotesAction == true
    }
    var displayedUpdateStatusIsSelectable: Bool {
        updateStatusTextField?.isSelectable == true
    }
    var displayedUpdateStatusSelectedRange: NSRange? {
        updateStatusTextField?.currentEditor()?.selectedRange
    }

    func selectAllUpdateStatusForTesting() {
        updateStatusTextField?.selectText(nil)
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
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: AboutContentView(
                model: contentModel,
                onOpenProject: { [weak self] in self?.openProject() },
                onPrimaryUpdateAction: { [weak self] action in
                    self?.performUpdateAction(action)
                },
                onSecondaryUpdateAction: { [weak self] action in
                    self?.performSecondaryUpdateAction(action)
                },
                onCopyVersion: { [weak self] in self?.copyVersionInfo() },
                onClose: { [weak self] in self?.closeAbout() }
            )
        )
        window.setContentSize(AboutLayout.windowSize)
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
        contentModel.apply(
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
    }

    private func openProject() {
        guard let projectURL else { return }
        NSWorkspace.shared.open(projectURL)
    }

    private func performUpdateAction(_ action: AboutUpdatePrimaryAction) {
        switch action {
        case .checkAgain:
            updateController.checkAgain()
        case .download:
            updateController.downloadAvailableUpdate()
        case .cancel:
            updateController.cancelUpdate()
        case .installAndRelaunch:
            updateController.installAndRelaunch()
        case .openDownloadedUpdate:
            updateController.openDownloadedUpdate()
        }
    }

    private func performSecondaryUpdateAction(_ action: AboutUpdateSecondaryAction) {
        switch action {
        case .viewReleases:
            updateController.viewReleasesFallback()
        case .viewFullReleaseNotes:
            updateController.viewFullReleaseNotes()
        case .installLater:
            closeAbout()
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
        contentModel.apply(
            updatePresentation: presentation,
            updateFeatureAvailable: updateFeatureAvailable
        )
    }

    private func copyVersionInfo() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(versionInfo, forType: .string) else { return }

        copyResetWorkItem?.cancel()
        contentModel.showCopySucceeded()
        let workItem = DispatchWorkItem { [weak self] in
            self?.resetCopyVersionButton()
        }
        copyResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func resetCopyVersionButton() {
        copyResetWorkItem?.cancel()
        copyResetWorkItem = nil
        contentModel.showCopyReady()
    }

    private func closeAbout() {
        copyResetWorkItem?.cancel()
        close()
    }

    func windowWillClose(_ notification: Notification) {
        updateController.installLater()
    }

#if DEBUG
    private var updateStatusTextField: NSTextField? {
        findUpdateStatusTextField(in: window?.contentView)
    }

    private func findUpdateStatusTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let textField = view as? NSTextField,
           textField.identifier?.rawValue == "AboutUpdateStatusLabel" {
            return textField
        }
        for subview in view.subviews {
            if let textField = findUpdateStatusTextField(in: subview) {
                return textField
            }
        }
        return nil
    }
#endif
}
