import Foundation

@MainActor
final class SplitImageExportController {
    typealias RenderCompletion = (Result<SplitRenderResult, Error>) -> Void

    struct Dependencies {
        let chooseDestination: (_ suggestedDirectoryName: String) -> URL?
        let render: (
            _ markdown: String,
            _ widthPreset: RenderWidthPreset,
            _ theme: RenderTheme,
            _ operationID: DiagnosticOperationID,
            _ completion: @escaping RenderCompletion
        ) -> Void
        let write: (
            _ result: SplitRenderResult,
            _ destinationDirectoryURL: URL
        ) async throws -> Void
    }

    private let dependencies: Dependencies
    private let diagnosticLogger: DiagnosticLogger
    private let onExportingChange: (Bool) -> Void
    private let onSuccess: (Int) -> Void
    private let onError: (Error) -> Void
    private(set) var isExporting = false

    init(
        dependencies: Dependencies,
        diagnosticLogger: DiagnosticLogger,
        onExportingChange: @escaping (Bool) -> Void,
        onSuccess: @escaping (Int) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.dependencies = dependencies
        self.diagnosticLogger = diagnosticLogger
        self.onExportingChange = onExportingChange
        self.onSuccess = onSuccess
        self.onError = onError
    }

    func start(
        markdown: String,
        widthPreset: RenderWidthPreset,
        theme: RenderTheme
    ) {
        guard !isExporting else { return }
        let operationID = DiagnosticOperationID()
        let startedAt = DispatchTime.now().uptimeNanoseconds
        setExporting(true)
        diagnosticLogger.record(
            category: .renderer,
            stage: .renderRequest,
            result: .started,
            operationID: operationID
        )

        let suggestedDirectoryName = SplitImageExportNaming
            .suggestedDirectoryName(from: markdown)
        guard let destinationDirectoryURL = dependencies
            .chooseDestination(suggestedDirectoryName) else {
            diagnosticLogger.record(
                category: .renderer,
                stage: .renderCompletion,
                result: .cancelled,
                operationID: operationID,
                durationMilliseconds: DiagnosticDuration.milliseconds(
                    since: startedAt
                )
            )
            setExporting(false)
            return
        }

        dependencies.render(
            markdown,
            widthPreset,
            theme,
            operationID
        ) { [weak self] result in
            self?.renderDidFinish(
                result,
                destinationDirectoryURL: destinationDirectoryURL,
                operationID: operationID,
                startedAt: startedAt
            )
        }
    }

    private func renderDidFinish(
        _ result: Result<SplitRenderResult, Error>,
        destinationDirectoryURL: URL,
        operationID: DiagnosticOperationID,
        startedAt: UInt64
    ) {
        switch result {
        case let .success(splitResult):
            Task { @MainActor [weak self] in
                await self?.write(
                    splitResult,
                    destinationDirectoryURL: destinationDirectoryURL,
                    operationID: operationID,
                    startedAt: startedAt
                )
            }
        case let .failure(error):
            diagnosticLogger.record(
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
            onError(presentedError(for: error, operationID: operationID))
            setExporting(false)
        }
    }

    private func write(
        _ result: SplitRenderResult,
        destinationDirectoryURL: URL,
        operationID: DiagnosticOperationID,
        startedAt: UInt64
    ) async {
        do {
            try await dependencies.write(result, destinationDirectoryURL)
            diagnosticLogger.record(
                category: .renderer,
                stage: .renderCompletion,
                result: .succeeded,
                operationID: operationID,
                durationMilliseconds: DiagnosticDuration.milliseconds(
                    since: startedAt
                ),
                dimensions: DiagnosticDimensions(
                    width: Int(result.contentSize.width.rounded()),
                    height: Int(result.contentSize.height.rounded())
                ),
                itemCount: result.parts.count
            )
            onSuccess(result.parts.count)
        } catch {
            diagnosticLogger.record(
                category: .renderer,
                stage: .renderCompletion,
                result: .failed,
                level: .error,
                operationID: operationID,
                durationMilliseconds: DiagnosticDuration.milliseconds(
                    since: startedAt
                ),
                error: error,
                itemCount: result.parts.count
            )
            onError(error)
        }
        setExporting(false)
    }

    private func setExporting(_ isExporting: Bool) {
        guard self.isExporting != isExporting else { return }
        self.isExporting = isExporting
        onExportingChange(isExporting)
    }

    private func presentedError(
        for error: Error,
        operationID: DiagnosticOperationID
    ) -> Error {
        if let appError = error as? AppError,
           case let .contentTooLarge(width, height) = appError {
            return AppError.splitExportContentTooLarge(
                width: width,
                height: height
            )
        }
        return RendererErrorReport(
            failure: RendererFailure.from(error),
            operationID: operationID
        )
    }
}
