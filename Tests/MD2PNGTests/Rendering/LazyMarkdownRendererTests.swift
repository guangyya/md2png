import AppKit
import XCTest
@testable import MD2PNG

final class LazyMarkdownRendererTests: XCTestCase {
    @MainActor
    func testLiveCoordinatorDependenciesConstructAndReuseRendererOnDemand() throws {
        let suiteName = "LazyMarkdownRendererTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let renderer = RecordingMarkdownRenderer()
        var factoryInvocationCount = 0
        let dependencies = RenderCoordinator.Dependencies.live(
            rendererFactory: {
                factoryInvocationCount += 1
                return renderer
            },
            widthPreference: RenderWidthPreference(defaults: defaults),
            themePreference: RenderThemePreference(defaults: defaults),
            diagnosticLogger: .disabled
        )
        let coordinator = RenderCoordinator(
            dependencies: dependencies,
            confirmClipboardOverwrite: { _ in false },
            onStateChange: { _ in },
            onNotice: { _ in },
            onError: { _ in },
            onPreviewRequested: { _ in }
        )

        XCTAssertEqual(factoryInvocationCount, 0)
        XCTAssertEqual(coordinator.state.selectedWidthPreset, .standard)
        XCTAssertEqual(coordinator.state.selectedTheme, .cleanLight)
        XCTAssertEqual(factoryInvocationCount, 0)

        let firstOperationID = try XCTUnwrap(DiagnosticOperationID(rawValue: "012345abcdef"))
        var singleCompletionCount = 0
        dependencies.render(
            "# First",
            .wide,
            .dark,
            firstOperationID
        ) { _ in
            singleCompletionCount += 1
        }

        XCTAssertEqual(factoryInvocationCount, 1)
        XCTAssertEqual(singleCompletionCount, 1)
        XCTAssertEqual(renderer.singleRequests, [RecordingMarkdownRenderer.Request(
            markdown: "# First",
            widthPreset: .wide,
            theme: .dark,
            operationID: firstOperationID,
            maximumSliceHeight: nil
        )])

        let secondOperationID = try XCTUnwrap(DiagnosticOperationID(rawValue: "fedcba543210"))
        dependencies.render(
            "# Second",
            .compact,
            .warmPaper,
            secondOperationID
        ) { _ in
            singleCompletionCount += 1
        }
        var splitCompletionCount = 0
        dependencies.renderSplit(
            "# Split",
            .standard,
            .cleanLight,
            secondOperationID
        ) { _ in
            splitCompletionCount += 1
        }

        XCTAssertEqual(factoryInvocationCount, 1)
        XCTAssertEqual(singleCompletionCount, 2)
        XCTAssertEqual(splitCompletionCount, 1)
        XCTAssertEqual(renderer.singleRequests.count, 2)
        XCTAssertEqual(renderer.splitRequests, [RecordingMarkdownRenderer.Request(
            markdown: "# Split",
            widthPreset: .standard,
            theme: .cleanLight,
            operationID: secondOperationID,
            maximumSliceHeight: SplitImageExportPolicy.maximumSliceHeight
        )])
    }
}

@MainActor
private final class RecordingMarkdownRenderer: MarkdownRendering {
    struct Request: Equatable {
        let markdown: String
        let widthPreset: RenderWidthPreset
        let theme: RenderTheme
        let operationID: DiagnosticOperationID
        let maximumSliceHeight: Int?
    }

    private(set) var singleRequests: [Request] = []
    private(set) var splitRequests: [Request] = []

    func render(
        _ markdown: String,
        widthPreset: RenderWidthPreset,
        theme: RenderTheme,
        operationID: DiagnosticOperationID,
        completion: @escaping (Result<NSImage, Error>) -> Void
    ) {
        singleRequests.append(Request(
            markdown: markdown,
            widthPreset: widthPreset,
            theme: theme,
            operationID: operationID,
            maximumSliceHeight: nil
        ))
        completion(.failure(StubRendererError.expected))
    }

    func renderSplit(
        _ markdown: String,
        widthPreset: RenderWidthPreset,
        theme: RenderTheme,
        maximumSliceHeight: Int,
        operationID: DiagnosticOperationID,
        completion: @escaping (Result<SplitRenderResult, Error>) -> Void
    ) {
        splitRequests.append(Request(
            markdown: markdown,
            widthPreset: widthPreset,
            theme: theme,
            operationID: operationID,
            maximumSliceHeight: maximumSliceHeight
        ))
        completion(.failure(StubRendererError.expected))
    }
}

private enum StubRendererError: Error {
    case expected
}
