import AppKit

@MainActor
final class ApplicationMenuCoordinator {
    struct Actions {
        let renderClipboard: () -> Void
        let renderMarkdownFile: () -> Void
        let showLastRender: () -> Void
        let rerenderLastMarkdown: () -> Void
        let restoreLastMarkdown: () -> Void
        let renderExample: (ExampleKind) -> Void
        let selectWidthPreset: (RenderWidthPreset) -> Void
        let selectTheme: (RenderTheme) -> Void
        let showSettings: () -> Void
        let showWelcome: () -> Void
        let showAbout: () -> Void
        let dismissTransientPresentation: () -> Void
        let quit: () -> Void
    }

    private let updateController: UpdateController
    private let updateStatusPresenter: UpdateStatusPresenter
    private let currentRenderState: () -> RenderCoordinatorState
    private let currentShortcutConfiguration: () -> GlobalShortcutConfiguration
    private let actions: Actions
    private var statusMenuController: StatusMenuController?
    private var clipboardContainsMarkdown = false
    private var updateStatusObserverID: UUID?

    init(
        updateController: UpdateController,
        updateStatusPresenter: UpdateStatusPresenter,
        currentRenderState: @escaping () -> RenderCoordinatorState,
        currentShortcutConfiguration: @escaping () -> GlobalShortcutConfiguration,
        actions: Actions
    ) {
        self.updateController = updateController
        self.updateStatusPresenter = updateStatusPresenter
        self.currentRenderState = currentRenderState
        self.currentShortcutConfiguration = currentShortcutConfiguration
        self.actions = actions
    }

    var button: NSStatusBarButton? {
        statusMenuController?.button
    }

#if DEBUG
    var clipboardPreviewUpdateCountForTesting: Int {
        statusMenuController?.clipboardPreviewUpdateCount ?? 0
    }
#endif

    func configure() {
        guard statusMenuController == nil else { return }
        let renderState = currentRenderState()
        let controller = StatusMenuController(
            selectedWidthPreset: renderState.selectedWidthPreset,
            selectedTheme: renderState.selectedTheme,
            shortcutConfiguration: currentShortcutConfiguration(),
            actions: StatusMenuController.Actions(
                menuWillOpen: { [weak self] in self?.menuWillOpen() },
                renderClipboard: actions.renderClipboard,
                renderMarkdownFile: actions.renderMarkdownFile,
                showLastRender: actions.showLastRender,
                rerenderLastMarkdown: actions.rerenderLastMarkdown,
                restoreLastMarkdown: actions.restoreLastMarkdown,
                renderExample: actions.renderExample,
                selectWidthPreset: actions.selectWidthPreset,
                selectTheme: actions.selectTheme,
                showSettings: actions.showSettings,
                showWelcome: actions.showWelcome,
                showAbout: actions.showAbout,
                quit: actions.quit
            )
        )
        statusMenuController = controller
        refreshClipboardState()
        apply(renderState)

        updateStatusObserverID = updateController.observeStatus { [weak self] status in
            self?.updateStatusPresenter.apply(status)
        }
    }

    func apply(_ state: RenderCoordinatorState) {
        guard let statusMenuController else { return }
        statusMenuController.selectWidthPreset(state.selectedWidthPreset)
        statusMenuController.selectTheme(state.selectedTheme)
        statusMenuController.apply(StatusMenuPresentation(state: StatusMenuState(
            clipboardContainsMarkdown: clipboardContainsMarkdown,
            hasLastSource: state.hasLastSource,
            hasLastRender: state.hasLastRender,
            isRendering: state.isRendering,
            isUpdateInstallPending: state.isUpdateInstallPending
        )))
        updateStatusPresenter.apply(state)
    }

    func applyShortcuts(_ configuration: GlobalShortcutConfiguration) {
        statusMenuController?.applyShortcuts(configuration)
    }

    func applyStatusItem(_ presentation: StatusItemPresentation) {
        statusMenuController?.applyStatusItem(presentation)
    }

    func tearDown() {
        if let updateStatusObserverID {
            updateController.removeStatusObserver(updateStatusObserverID)
            self.updateStatusObserverID = nil
        }
        statusMenuController?.removeStatusItem()
        statusMenuController = nil
    }

    private func menuWillOpen() {
        actions.dismissTransientPresentation()
        refreshClipboardState()
    }

    private func refreshClipboardState() {
        let state = Clipboard.menuState(includeLabel: false)
        clipboardContainsMarkdown = state.containsMarkdown
        statusMenuController?.updateClipboardPreview(state.preview)
        apply(currentRenderState())
    }
}
