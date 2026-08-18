import AppKit
import XCTest
@testable import MD2PNG

final class RendererDiagnosticTests: XCTestCase {
    func testJavaScriptResponseAcceptsOnlyBoundedStructuredValues() {
        XCTAssertEqual(
            RendererJavaScriptResponse([
                "ok": true,
                "width": 640,
                "height": 480
            ]),
            .success(width: 640, height: 480)
        )
        XCTAssertEqual(
            RendererJavaScriptResponse([
                "ok": false,
                "kind": "mermaid_syntax",
                "diagramNumber": 2,
                "sourceLine": 17
            ]),
            .failure(RendererFailure(
                kind: .mermaidSyntax,
                diagramNumber: 2,
                sourceLine: 17
            ))
        )

        XCTAssertNil(RendererJavaScriptResponse(nil))
        XCTAssertNil(RendererJavaScriptResponse(["ok": 1, "width": 640, "height": 480]))
        XCTAssertNil(RendererJavaScriptResponse(["ok": true, "width": "640", "height": 480]))
        XCTAssertNil(RendererJavaScriptResponse(["ok": true, "width": true, "height": 480]))
        XCTAssertNil(RendererJavaScriptResponse([
            "ok": true,
            "width": Double.greatestFiniteMagnitude,
            "height": 480
        ]))
        XCTAssertNil(RendererJavaScriptResponse([
            "ok": false,
            "kind": "mermaid_syntax",
            "diagramNumber": 1,
            "message": "PRIVATE RAW ERROR"
        ]))
        XCTAssertNil(RendererJavaScriptResponse([
            "ok": false,
            "kind": "mermaid_syntax",
            "diagramNumber": 1,
            "sourceLine": "PRIVATE RAW ERROR"
        ]))
        XCTAssertNil(RendererJavaScriptResponse([
            "ok": false,
            "kind": "mermaid_syntax",
            "diagramNumber": 0
        ]))
    }

    func testAppErrorsMapToActionableRendererCategories() {
        XCTAssertEqual(RendererFailure.from(AppError.rendererUnavailable).kind, .rendererResources)
        XCTAssertEqual(RendererFailure.from(AppError.rendererRecoveryFailed).kind, .webKitRecovery)
        XCTAssertEqual(RendererFailure.from(AppError.rendererTimedOut).kind, .timeout)
        XCTAssertEqual(RendererFailure.from(AppError.invalidRendererResponse).kind, .invalidResponse)
        XCTAssertEqual(RendererFailure.from(AppError.rendererPNGEncodingFailed).kind, .pngCreation)

        let size = RendererFailure.from(AppError.contentTooLarge(width: 1_601, height: 16_001))
        XCTAssertEqual(size.kind, .sizeLimit)
        XCTAssertEqual(size.width, 1_601)
        XCTAssertEqual(size.height, 16_001)
    }

    func testCopiedDetailsContainSafeContextWithoutRawErrorOrMarkdown() throws {
        let operationID = try XCTUnwrap(DiagnosticOperationID(rawValue: "012345abcdef"))
        let canary = "PRIVATE_MARKDOWN /Users/private/file.md?token=secret"
        let report = RendererErrorReport(
            failure: RendererFailure.from(NSError(
                domain: canary,
                code: 99,
                userInfo: [NSLocalizedDescriptionKey: canary]
            )),
            operationID: operationID
        )

        let details = report.copiedDetails(
            application: DiagnosticApplicationInfo(
                name: "md2png",
                version: "0.9.0",
                build: "9",
                sourceCommit: "abcdef0",
                configuration: "debug"
            ),
            system: DiagnosticSystemInfo(
                macOSVersion: "26.0.0",
                architecture: "arm64"
            )
        )

        XCTAssertTrue(details.contains("Issue: unknown"))
        XCTAssertTrue(details.contains("Operation ID: 012345abcdef"))
        XCTAssertTrue(details.contains("App: md2png 0.9.0 (9)"))
        XCTAssertTrue(details.contains("Commit: abcdef0"))
        XCTAssertTrue(details.contains("Markdown included: no"))
        XCTAssertTrue(details.contains("Raw error included: no"))
        XCTAssertFalse(details.contains(canary))
        XCTAssertFalse(details.contains("/Users/private"))
        XCTAssertFalse(details.contains("token=secret"))
    }

    func testRendererDetailsAreLocalizedAndKeepStableSupportCodes() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))
        let failure = RendererFailure(
            kind: .mermaidDiagramType,
            diagramNumber: 3,
            sourceLine: 21
        )

        XCTAssertEqual(
            failure.summary(localizationBundle: english),
            "Couldn’t render Mermaid diagram 3 near Markdown line 21."
        )
        XCTAssertEqual(
            failure.summary(localizationBundle: chinese),
            "无法渲染第 3 个 Mermaid 图，问题可能在 Markdown 第 21 行附近。"
        )
        XCTAssertTrue(failure.suggestion(localizationBundle: english).contains("flowchart"))
        XCTAssertTrue(failure.suggestion(localizationBundle: chinese).contains("sequenceDiagram"))
        XCTAssertEqual(RendererFailure.errorDomain, "md2png.renderer")
        XCTAssertEqual(failure.errorCode, 2)
    }

    func testSizeLimitSuggestionRoutesTallContentToExplicitSplitExport() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))
        let failure = RendererFailure(
            kind: .sizeLimit,
            width: 1_120,
            height: 20_000
        )

        XCTAssertTrue(
            failure.suggestion(localizationBundle: english)
                .contains("split PNGs")
        )
        XCTAssertTrue(
            failure.suggestion(localizationBundle: chinese)
                .contains("分片保存为 PNG")
        )

        let wideFailure = RendererFailure(
            kind: .sizeLimit,
            width: 1_601,
            height: 4_000
        )
        XCTAssertFalse(wideFailure.supportsSplitExportRecovery)
        XCTAssertTrue(
            wideFailure.suggestion(localizationBundle: english)
                .contains("narrower Output Width")
        )

        let extremelyTallFailure = RendererFailure(
            kind: .sizeLimit,
            width: 1_120,
            height: 80_000
        )
        XCTAssertFalse(extremelyTallFailure.supportsSplitExportRecovery)
    }

    @MainActor
    func testPresenterCopiesOnlyAfterExplicitCopyAction() throws {
        let operationID = try XCTUnwrap(DiagnosticOperationID(rawValue: "012345abcdef"))
        let report = RendererErrorReport(
            failure: RendererFailure(kind: .mermaidSyntax, diagramNumber: 1, sourceLine: 4),
            operationID: operationID
        )
        var action = RendererErrorDetailsAction.done
        var presented: RendererErrorDetailsPresentation?
        var copied: [String] = []
        let presenter = RendererErrorDetailsPresenter(
            dependencies: RendererErrorDetailsDependencies(
                present: { presentation in
                    presented = presentation
                    return action
                },
                copy: { text in
                    copied.append(text)
                    return true
                }
            ),
            application: DiagnosticApplicationInfo(
                name: "md2png",
                version: "0.9.0",
                build: "9",
                sourceCommit: nil,
                configuration: "debug"
            ),
            system: DiagnosticSystemInfo(macOSVersion: "26.0.0", architecture: "arm64")
        )

        XCTAssertEqual(presenter.show(report), .dismissed)
        XCTAssertNotNil(presented)
        XCTAssertFalse(try XCTUnwrap(presented).offersSplitExport)
        XCTAssertTrue(copied.isEmpty)

        action = .copy
        XCTAssertEqual(presenter.show(report), .detailsCopied)
        XCTAssertEqual(copied.count, 1)
        XCTAssertTrue(copied[0].contains("Issue: mermaid_syntax"))
        XCTAssertFalse(copied[0].contains("```mermaid"))

        action = .saveSplitPNGs
        XCTAssertEqual(presenter.show(report), .dismissed)
    }

    @MainActor
    func testSizeLimitOffersSplitExportAndReturnsRecoveryRequest() throws {
        let operationID = try XCTUnwrap(DiagnosticOperationID(rawValue: "012345abcdef"))
        let report = RendererErrorReport(
            failure: RendererFailure(kind: .sizeLimit, width: 1_120, height: 20_000),
            operationID: operationID
        )
        var presented: RendererErrorDetailsPresentation?
        var copied: [String] = []
        let presenter = RendererErrorDetailsPresenter(
            dependencies: RendererErrorDetailsDependencies(
                present: { presentation in
                    presented = presentation
                    return .saveSplitPNGs
                },
                copy: { text in
                    copied.append(text)
                    return true
                }
            )
        )

        XCTAssertEqual(presenter.show(report), .splitExportRequested)
        XCTAssertTrue(try XCTUnwrap(presented).offersSplitExport)
        XCTAssertTrue(copied.isEmpty)
    }

    @MainActor
    func testWideSizeLimitDoesNotOfferSplitExport() throws {
        let operationID = try XCTUnwrap(DiagnosticOperationID(rawValue: "012345abcdef"))
        let report = RendererErrorReport(
            failure: RendererFailure(kind: .sizeLimit, width: 1_601, height: 4_000),
            operationID: operationID
        )
        var presented: RendererErrorDetailsPresentation?
        let presenter = RendererErrorDetailsPresenter(
            dependencies: RendererErrorDetailsDependencies(
                present: { presentation in
                    presented = presentation
                    return .saveSplitPNGs
                },
                copy: { _ in true }
            )
        )

        XCTAssertEqual(presenter.show(report), .dismissed)
        XCTAssertFalse(try XCTUnwrap(presented).offersSplitExport)
    }
}
