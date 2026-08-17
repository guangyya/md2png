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
            _ operationID: DiagnosticOperationID,
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
            renderer: MarkdownRenderer? = nil,
            widthPreference: RenderWidthPreference = RenderWidthPreference(),
            themePreference: RenderThemePreference = RenderThemePreference(),
            diagnosticLogger: DiagnosticLogger = .shared
        ) -> Dependencies {
            let renderer = renderer ?? MarkdownRenderer(
                diagnosticLogger: diagnosticLogger
            )
            return Dependencies(
                render: { markdown, widthPreset, theme, operationID, completion in
                    renderer.render(
                        markdown,
                        widthPreset: widthPreset,
                        theme: theme,
                        operationID: operationID,
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
    private let diagnosticLogger: DiagnosticLogger

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
        diagnosticLogger: DiagnosticLogger = .disabled,
        confirmClipboardOverwrite: @escaping (ClipboardOverwriteAction) -> Bool,
        onStateChange: @escaping (RenderCoordinatorState) -> Void,
        onNotice: @escaping (RenderCoordinatorNotice) -> Void,
        onError: @escaping (Error) -> Void,
        onPreviewRequested: @escaping (LastRender) -> Void
    ) {
        self.dependencies = dependencies
        self.selectedWidthPreset = selectedWidthPreset
        self.selectedTheme = selectedTheme
        self.diagnosticLogger = diagnosticLogger
        self.confirmClipboardOverwrite = confirmClipboardOverwrite
        self.onStateChange = onStateChange
        self.onNotice = onNotice
        self.onError = onError
        self.onPreviewRequested = onPreviewRequested
    }

    convenience init(
        diagnosticLogger: DiagnosticLogger = .shared,
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
                themePreference: themePreference,
                diagnosticLogger: diagnosticLogger
            ),
            selectedWidthPreset: widthPreference.selectedPreset,
            selectedTheme: themePreference.selectedTheme,
            diagnosticLogger: diagnosticLogger,
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
            let markdown = try dependencies.readClipboardMarkdown()
            diagnosticLogger.record(
                category: .clipboard,
                stage: .clipboardRead,
                result: .succeeded,
                clipboardType: .markdown
            )
            render(markdown)
        } catch {
            diagnosticLogger.record(
                category: .clipboard,
                stage: .clipboardRead,
                result: .failed,
                level: .error,
                error: error,
                clipboardType: .empty
            )
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
            diagnosticLogger.record(
                category: .clipboard,
                stage: .clipboardWrite,
                result: .succeeded,
                clipboardType: .markdown,
                clipboardOwnership: .owned
            )
            onNotice(.markdownRestored)
        } catch {
            diagnosticLogger.record(
                category: .clipboard,
                stage: .clipboardWrite,
                result: .failed,
                level: .error,
                error: error,
                clipboardType: .markdown,
                clipboardOwnership: .unknown
            )
            onError(error)
        }
    }

    func renderExample(_ kind: ExampleKind) {
        guard canStartRenderAction else { return }
        let markdown: String
        do {
            markdown = try dependencies.loadExample(kind)
            diagnosticLogger.record(
                category: .resource,
                stage: .exampleResourceLookup,
                result: .available
            )
        } catch {
            diagnosticLogger.record(
                category: .resource,
                stage: .exampleResourceLookup,
                result: .unavailable,
                level: .error,
                error: error
            )
            onError(error)
            return
        }

        do {
            let changeCount = try dependencies.writeMarkdown(markdown)
            lastSource.recordOwnedClipboardWrite(changeCount: changeCount)
            diagnosticLogger.record(
                category: .clipboard,
                stage: .clipboardWrite,
                result: .succeeded,
                clipboardType: .markdown,
                clipboardOwnership: .owned
            )
            render(markdown, showsPreviewOnSuccess: true)
        } catch {
            diagnosticLogger.record(
                category: .clipboard,
                stage: .clipboardWrite,
                result: .failed,
                level: .error,
                error: error,
                clipboardType: .markdown,
                clipboardOwnership: .unknown
            )
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
        let operationID = DiagnosticOperationID()
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let requestedWidthPreset = selectedWidthPreset
        let requestedTheme = selectedTheme
        diagnosticLogger.record(
            category: .renderer,
            stage: .renderRequest,
            result: .started,
            operationID: operationID
        )
        notifyStateChange()

        dependencies.render(
            markdown,
            requestedWidthPreset,
            requestedTheme,
            operationID
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
                    let dimensions = Self.pixelDimensions(for: image)
                    self.lastImage = image
                    self.lastRenderWidthPreset = requestedWidthPreset
                    self.lastSource.recordSuccessfulRender(
                        markdown: markdown,
                        clipboardChangeCount: changeCount
                    )
                    self.diagnosticLogger.record(
                        category: .clipboard,
                        stage: .clipboardWrite,
                        result: .succeeded,
                        operationID: operationID,
                        clipboardType: .png,
                        clipboardOwnership: .owned,
                        dimensions: dimensions
                    )
                    self.diagnosticLogger.record(
                        category: .renderer,
                        stage: .renderCompletion,
                        result: .succeeded,
                        operationID: operationID,
                        durationMilliseconds: DiagnosticDuration.milliseconds(
                            since: startedAt
                        ),
                        dimensions: dimensions
                    )
                    self.onNotice(.imageCopied)
                    if showsPreviewOnSuccess, let lastRender = self.lastRender {
                        self.onPreviewRequested(lastRender)
                    }
                } catch {
                    self.diagnosticLogger.record(
                        category: .clipboard,
                        stage: .clipboardWrite,
                        result: .failed,
                        level: .error,
                        operationID: operationID,
                        error: error,
                        clipboardType: .png,
                        clipboardOwnership: .unknown
                    )
                    self.diagnosticLogger.record(
                        category: .renderer,
                        stage: .renderCompletion,
                        result: .failed,
                        level: .error,
                        operationID: operationID,
                        durationMilliseconds: DiagnosticDuration.milliseconds(
                            since: startedAt
                        ),
                        error: error
                    )
                    self.onError(error)
                }
            case let .failure(error):
                self.diagnosticLogger.record(
                    category: .renderer,
                    stage: .renderCompletion,
                    result: .failed,
                    level: .error,
                    operationID: operationID,
                    durationMilliseconds: DiagnosticDuration.milliseconds(
                        since: startedAt
                    ),
                    error: error
                )
                self.onError(RendererErrorReport(
                    failure: RendererFailure.from(error),
                    operationID: operationID
                ))
            }
        }
    }

    private func confirmClipboardOverwriteIfNeeded(
        for action: ClipboardOverwriteAction
    ) -> Bool {
        guard lastSource.requiresConfirmation(
            currentClipboardChangeCount: dependencies.clipboardChangeCount()
        ) else {
            diagnosticLogger.record(
                category: .clipboard,
                stage: .clipboardOwnership,
                result: .owned,
                level: .verbose,
                clipboardOwnership: .owned
            )
            return true
        }
        diagnosticLogger.record(
            category: .clipboard,
            stage: .clipboardOwnership,
            result: .external,
            clipboardOwnership: .external
        )
        guard !isPresentingClipboardConfirmation else { return false }
        isPresentingClipboardConfirmation = true
        defer { isPresentingClipboardConfirmation = false }
        let isConfirmed = confirmClipboardOverwrite(action)
        diagnosticLogger.record(
            category: .clipboard,
            stage: .clipboardOwnership,
            result: isConfirmed ? .accepted : .cancelled,
            clipboardOwnership: .external
        )
        return isConfirmed
    }

    private func notifyStateChange() {
        onStateChange(state)
    }

    private static func pixelDimensions(for image: NSImage) -> DiagnosticDimensions {
        if let bitmap = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { lhs, rhs in
                lhs.pixelsWide * lhs.pixelsHigh < rhs.pixelsWide * rhs.pixelsHigh
            }) {
            return DiagnosticDimensions(
                width: bitmap.pixelsWide,
                height: bitmap.pixelsHigh
            )
        }
        return DiagnosticDimensions(
            width: Int(image.size.width.rounded()),
            height: Int(image.size.height.rounded())
        )
    }
}
