import AppKit
import SwiftUI

@MainActor
final class AboutController: NSWindowController, NSWindowDelegate {
    private let updateController: UpdateController
    private let diagnosticLogger: DiagnosticLogger
    private let diagnosticSaveDependencies: AboutDiagnosticLogSaveDependencies
    private let rendererSelfTestDependencies: AboutRendererSelfTestDependencies
    private let onVisibilityChange: (Bool) -> Void
    private let contentModel = AboutContentModel()
    private var updateStatusObserverID: UUID?
    private var projectURL: URL?
    private var updateFeatureAvailable = false
    private var versionInfo = ""
    private var copyResetWorkItem: DispatchWorkItem?
    private var diagnosticSaveResetWorkItem: DispatchWorkItem?

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
    var displayedDiagnosticSaveButtonTitle: String {
        AboutDiagnosticSavePresentation.buttonTitle(
            for: contentModel.diagnosticSaveState
        )
    }
    var displayedDiagnosticSaveButtonIsEnabled: Bool {
        contentModel.diagnosticSaveState != .saving
    }
    var displayedRendererSelfTestButtonTitle: String {
        AboutRendererSelfTestPresentation.buttonTitle(
            for: contentModel.rendererSelfTestState
        )
    }
    var displayedRendererSelfTestButtonIsEnabled: Bool {
        contentModel.rendererSelfTestState != .running
    }
    var displayedDiagnosticsButtonTitle: String {
        AboutDiagnosticsPresentation.buttonTitle(
            selfTestState: contentModel.rendererSelfTestState,
            saveState: contentModel.diagnosticSaveState
        )
    }
    var displayedDiagnosticsButtonIsEnabled: Bool {
        contentModel.rendererSelfTestState != .running
            && contentModel.diagnosticSaveState != .saving
    }
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

    func saveDiagnosticLogsForTesting(
        window: DiagnosticExportWindow
    ) async -> AboutDiagnosticSaveResult {
        await saveDiagnosticLogs(window: window)
    }

    func runRendererSelfTestForTesting() {
        runRendererSelfTest()
    }
#endif

    init(
        updateController: UpdateController = .disabled(),
        diagnosticLogger: DiagnosticLogger = .shared,
        diagnosticSaveDependencies: AboutDiagnosticLogSaveDependencies = .live(),
        rendererSelfTestDependencies: AboutRendererSelfTestDependencies? = nil,
        onVisibilityChange: @escaping (Bool) -> Void = { _ in },
        onShowSettings: @escaping () -> Void = {}
    ) {
        self.updateController = updateController
        self.diagnosticLogger = diagnosticLogger
        self.diagnosticSaveDependencies = diagnosticSaveDependencies
        self.rendererSelfTestDependencies = rendererSelfTestDependencies ?? .live(
            diagnosticLogger: diagnosticLogger
        )
        self.onVisibilityChange = onVisibilityChange
        let window = AppWindow(
            contentRect: NSRect(origin: .zero, size: AboutLayout.windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("about.window_title", defaultValue: "About md2png")
        window.isReleasedWhenClosed = false
        window.showSettingsHandler = onShowSettings
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
                onRunRendererSelfTest: { [weak self] in self?.runRendererSelfTest() },
                onSaveDiagnosticLogs: { [weak self] window in
                    Task { @MainActor in
                        await self?.saveDiagnosticLogs(window: window)
                    }
                },
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
        let isBecomingVisible = window?.isVisible != true
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
        resetDiagnosticSaveButton()

        if isBecomingVisible {
            onVisibilityChange(true)
        }
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

    private func saveDiagnosticLogs(
        window: DiagnosticExportWindow
    ) async -> AboutDiagnosticSaveResult {
        guard contentModel.diagnosticSaveState != .saving else {
            return .cancelled
        }
        diagnosticSaveResetWorkItem?.cancel()
        diagnosticSaveResetWorkItem = nil
        contentModel.showDiagnosticSaveStarted()

        let suggestedFileName = DiagnosticExportFileName.make(window: window)
        guard let destinationURL = await diagnosticSaveDependencies.chooseDestination(
            self.window,
            suggestedFileName
        ) else {
            contentModel.showDiagnosticSaveReady()
            return .cancelled
        }

        do {
            let export = try await diagnosticLogger.export(window: window)
            try await diagnosticSaveDependencies.writeExport(export, destinationURL)
            contentModel.showDiagnosticSaveSucceeded()
            scheduleDiagnosticSaveReset()
            return .saved
        } catch {
            contentModel.showDiagnosticSaveReady()
            diagnosticSaveDependencies.presentFailure(self.window)
            return .failed
        }
    }

    private func runRendererSelfTest() {
        guard contentModel.rendererSelfTestState != .running else { return }
        contentModel.showRendererSelfTestStarted()
        rendererSelfTestDependencies.run { [weak self] result in
            guard let self else { return }
            self.contentModel.showRendererSelfTestReady()
            self.rendererSelfTestDependencies.presentResult(self.window, result)
        }
    }

    private func scheduleDiagnosticSaveReset() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.resetDiagnosticSaveButton()
        }
        diagnosticSaveResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func resetDiagnosticSaveButton() {
        diagnosticSaveResetWorkItem?.cancel()
        diagnosticSaveResetWorkItem = nil
        contentModel.showDiagnosticSaveReady()
    }

    private func closeAbout() {
        copyResetWorkItem?.cancel()
        diagnosticSaveResetWorkItem?.cancel()
        close()
    }

    func windowWillClose(_ notification: Notification) {
        updateController.installLater()
        onVisibilityChange(false)
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
