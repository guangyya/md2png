import AppKit

@MainActor
protocol MarkdownRendering: AnyObject {
    func render(
        _ markdown: String,
        widthPreset: RenderWidthPreset,
        theme: RenderTheme,
        operationID: DiagnosticOperationID,
        completion: @escaping (Result<NSImage, Error>) -> Void
    )

    func renderSplit(
        _ markdown: String,
        widthPreset: RenderWidthPreset,
        theme: RenderTheme,
        maximumSliceHeight: Int,
        operationID: DiagnosticOperationID,
        completion: @escaping (Result<SplitRenderResult, Error>) -> Void
    )
}

extension MarkdownRenderer: MarkdownRendering {}

@MainActor
final class LazyMarkdownRenderer: MarkdownRendering {
    typealias Factory = () -> any MarkdownRendering

    private let factory: Factory
    private var renderer: (any MarkdownRendering)?

    init(factory: @escaping Factory) {
        self.factory = factory
    }

    func render(
        _ markdown: String,
        widthPreset: RenderWidthPreset,
        theme: RenderTheme,
        operationID: DiagnosticOperationID,
        completion: @escaping (Result<NSImage, Error>) -> Void
    ) {
        resolve().render(
            markdown,
            widthPreset: widthPreset,
            theme: theme,
            operationID: operationID,
            completion: completion
        )
    }

    func renderSplit(
        _ markdown: String,
        widthPreset: RenderWidthPreset,
        theme: RenderTheme,
        maximumSliceHeight: Int,
        operationID: DiagnosticOperationID,
        completion: @escaping (Result<SplitRenderResult, Error>) -> Void
    ) {
        resolve().renderSplit(
            markdown,
            widthPreset: widthPreset,
            theme: theme,
            maximumSliceHeight: maximumSliceHeight,
            operationID: operationID,
            completion: completion
        )
    }

    private func resolve() -> any MarkdownRendering {
        if let renderer {
            return renderer
        }
        let renderer = factory()
        self.renderer = renderer
        return renderer
    }
}
