import AppKit

enum ClipboardOverwriteAction: Equatable {
    case rerenderLastMarkdown
    case restoreLastMarkdown
}

enum RenderCoordinatorNotice: Equatable {
    case imageCopied
    case markdownRestored
}

struct RenderCoordinatorState: Equatable {
    let isRendering: Bool
    let hasLastSource: Bool
    let hasLastRender: Bool
    let isUpdateInstallPending: Bool
    let isPresentingClipboardConfirmation: Bool
    let selectedWidthPreset: RenderWidthPreset
    let selectedTheme: RenderTheme
}

struct LastRender {
    let image: NSImage
    let widthPreset: RenderWidthPreset
    let markdown: String
}

@MainActor
final class RenderCoordinator {
    typealias RenderCompletion = (Result<NSImage, Error>) -> Void

    @MainActor
    struct Dependencies {
        let render: (
            _ markdown: String,
            _ widthPreset: RenderWidthPreset,
            _ theme: RenderTheme,
            _ completion: @escaping RenderCompletion
        ) -> Void
        let readClipboardMarkdown: () throws -> String
        let clipboardChangeCount: () -> Int
        let writeImage: (NSImage) throws -> Int
        let writeMarkdown: (String) throws -> Int
        let loadExample: (ExampleKind) throws -> String
        let selectWidthPreset: (RenderWidthPreset) -> Void
        let selectTheme: (RenderTheme) -> Void

        static func live(
            renderer: MarkdownRenderer = MarkdownRenderer(),
            widthPreference: RenderWidthPreference = RenderWidthPreference(),
            themePreference: RenderThemePreference = RenderThemePreference()
        ) -> Dependencies {
            Dependencies(
                render: { markdown, widthPreset, theme, completion in
                    renderer.render(
                        markdown,
                        widthPreset: widthPreset,
                        theme: theme,
                        completion: completion
                    )
                },
                readClipboardMarkdown: Clipboard.markdownText,
                clipboardChangeCount: { Clipboard.changeCount },
                writeImage: Clipboard.write(image:),
                writeMarkdown: Clipboard.write(markdown:),
                loadExample: AppResources.exampleMarkdown(for:),
                selectWidthPreset: widthPreference.select,
                selectTheme: themePreference.select
            )
        }
    }

    private let dependencies: Dependencies
    private let confirmClipboardOverwrite: (ClipboardOverwriteAction) -> Bool
    private let onStateChange: (RenderCoordinatorState) -> Void
    private let onNotice: (RenderCoordinatorNotice) -> Void
    private let onError: (Error) -> Void
    private let onPreviewRequested: (LastRender) -> Void

    private var lastSource = LastSourceState()
    private var lastImage: NSImage?
    private var lastRenderWidthPreset: RenderWidthPreset?
    private var isPresentingClipboardConfirmation = false
    private(set) var isRendering = false
    private(set) var isUpdateInstallPending = false
    private(set) var selectedWidthPreset: RenderWidthPreset
    private(set) var selectedTheme: RenderTheme

    init(
        dependencies: Dependencies,
        selectedWidthPreset: RenderWidthPreset = .standard,
        selectedTheme: RenderTheme = .cleanLight,
        confirmClipboardOverwrite: @escaping (ClipboardOverwriteAction) -> Bool,
        onStateChange: @escaping (RenderCoordinatorState) -> Void,
        onNotice: @escaping (RenderCoordinatorNotice) -> Void,
        onError: @escaping (Error) -> Void,
        onPreviewRequested: @escaping (LastRender) -> Void
    ) {
        self.dependencies = dependencies
        self.selectedWidthPreset = selectedWidthPreset
        self.selectedTheme = selectedTheme
        self.confirmClipboardOverwrite = confirmClipboardOverwrite
        self.onStateChange = onStateChange
        self.onNotice = onNotice
        self.onError = onError
        self.onPreviewRequested = onPreviewRequested
    }

    convenience init(
        confirmClipboardOverwrite: @escaping (ClipboardOverwriteAction) -> Bool,
        onStateChange: @escaping (RenderCoordinatorState) -> Void,
        onNotice: @escaping (RenderCoordinatorNotice) -> Void,
        onError: @escaping (Error) -> Void,
        onPreviewRequested: @escaping (LastRender) -> Void
    ) {
        let widthPreference = RenderWidthPreference()
        let themePreference = RenderThemePreference()
        self.init(
            dependencies: .live(
                widthPreference: widthPreference,
                themePreference: themePreference
            ),
            selectedWidthPreset: widthPreference.selectedPreset,
            selectedTheme: themePreference.selectedTheme,
            confirmClipboardOverwrite: confirmClipboardOverwrite,
            onStateChange: onStateChange,
            onNotice: onNotice,
            onError: onError,
            onPreviewRequested: onPreviewRequested
        )
    }

    var state: RenderCoordinatorState {
        RenderCoordinatorState(
            isRendering: isRendering,
            hasLastSource: lastSource.isAvailable,
            hasLastRender: lastImage != nil,
            isUpdateInstallPending: isUpdateInstallPending,
            isPresentingClipboardConfirmation: isPresentingClipboardConfirmation,
            selectedWidthPreset: selectedWidthPreset,
            selectedTheme: selectedTheme
        )
    }

    var hasTransientContent: Bool {
        lastImage != nil || lastSource.isAvailable
    }

    var canBeginUpdateInstall: Bool {
        !isRendering && !isUpdateInstallPending && !isPresentingClipboardConfirmation
    }

    func setUpdateInstallPending(_ isPending: Bool) {
        guard isUpdateInstallPending != isPending else { return }
        isUpdateInstallPending = isPending
        notifyStateChange()
    }

    func renderClipboard() {
        guard canStartRenderAction else { return }
        do {
            render(try dependencies.readClipboardMarkdown())
        } catch {
            onError(error)
        }
    }

    func showLastRender() {
        guard let lastRender else { return }
        onPreviewRequested(lastRender)
    }

    func rerenderLastMarkdown() {
        guard canStartRenderAction,
              let markdown = lastSource.markdown,
              confirmClipboardOverwriteIfNeeded(for: .rerenderLastMarkdown) else {
            return
        }
        render(markdown)
    }

    func restoreLastMarkdown() {
        guard canStartRenderAction,
              let markdown = lastSource.markdown,
              confirmClipboardOverwriteIfNeeded(for: .restoreLastMarkdown) else {
            return
        }
        do {
            let changeCount = try dependencies.writeMarkdown(markdown)
            lastSource.recordOwnedClipboardWrite(changeCount: changeCount)
            onNotice(.markdownRestored)
        } catch {
            onError(error)
        }
    }

    func renderExample(_ kind: ExampleKind) {
        guard canStartRenderAction else { return }
        do {
            let markdown = try dependencies.loadExample(kind)
            let changeCount = try dependencies.writeMarkdown(markdown)
            lastSource.recordOwnedClipboardWrite(changeCount: changeCount)
            render(markdown, showsPreviewOnSuccess: true)
        } catch {
            onError(error)
        }
    }

    func selectWidthPreset(_ preset: RenderWidthPreset) {
        guard !isRendering, !isUpdateInstallPending else { return }
        selectedWidthPreset = preset
        dependencies.selectWidthPreset(preset)
        notifyStateChange()
    }

    func selectTheme(_ theme: RenderTheme) {
        guard !isRendering, !isUpdateInstallPending else { return }
        selectedTheme = theme
        dependencies.selectTheme(theme)
        notifyStateChange()
    }

    func recordOwnedClipboardWrite(changeCount: Int) {
        lastSource.recordOwnedClipboardWrite(changeCount: changeCount)
    }

    private var canStartRenderAction: Bool {
        !isRendering && !isUpdateInstallPending && !isPresentingClipboardConfirmation
    }

    private var lastRender: LastRender? {
        guard let image = lastImage,
              let widthPreset = lastRenderWidthPreset,
              let markdown = lastSource.markdown else {
            return nil
        }
        return LastRender(image: image, widthPreset: widthPreset, markdown: markdown)
    }

    private func render(
        _ markdown: String,
        showsPreviewOnSuccess: Bool = false
    ) {
        guard canStartRenderAction else { return }
        isRendering = true
        let requestedWidthPreset = selectedWidthPreset
        let requestedTheme = selectedTheme
        notifyStateChange()

        dependencies.render(
            markdown,
            requestedWidthPreset,
            requestedTheme
        ) { [weak self] result in
            guard let self else { return }
            defer {
                self.isRendering = false
                self.notifyStateChange()
            }

            switch result {
            case let .success(image):
                do {
                    let changeCount = try self.dependencies.writeImage(image)
                    self.lastImage = image
                    self.lastRenderWidthPreset = requestedWidthPreset
                    self.lastSource.recordSuccessfulRender(
                        markdown: markdown,
                        clipboardChangeCount: changeCount
                    )
                    self.onNotice(.imageCopied)
                    if showsPreviewOnSuccess, let lastRender = self.lastRender {
                        self.onPreviewRequested(lastRender)
                    }
                } catch {
                    self.onError(error)
                }
            case let .failure(error):
                self.onError(error)
            }
        }
    }

    private func confirmClipboardOverwriteIfNeeded(
        for action: ClipboardOverwriteAction
    ) -> Bool {
        guard lastSource.requiresConfirmation(
            currentClipboardChangeCount: dependencies.clipboardChangeCount()
        ) else {
            return true
        }
        guard !isPresentingClipboardConfirmation else { return false }
        isPresentingClipboardConfirmation = true
        defer { isPresentingClipboardConfirmation = false }
        return confirmClipboardOverwrite(action)
    }

    private func notifyStateChange() {
        onStateChange(state)
    }
}
