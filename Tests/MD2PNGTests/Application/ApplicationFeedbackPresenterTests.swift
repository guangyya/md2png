import AppKit
import XCTest
@testable import MD2PNG

@MainActor
final class ApplicationFeedbackPresenterTests: XCTestCase {
    func testCommonSuccessAndRecoveryFeedbackUsesAccessibleMessages() {
        var announcements: [(String, NSAccessibilityPriorityLevel)] = []
        let hud = HUDController(isVoiceOverEnabled: { false }) { message, priority in
            announcements.append((message, priority))
        }
        defer { hud.dismiss() }
        let presenter = makePresenter(hud: hud)

        presenter.showShortcutConflict()
        presenter.showPreviewCopied()
        presenter.show(.imageCopied)
        presenter.show(.markdownRestored)

        XCTAssertEqual(announcements.map(\.0), [
            "Global shortcut unavailable — use the same command from the md2png menu",
            "PNG copied again and ready to paste with Command-V",
            "PNG copied and ready to paste with Command-V",
            "Markdown restored and ready to paste with Command-V"
        ])
        XCTAssertEqual(announcements.map(\.1), [.high, .medium, .medium, .medium])
    }

    func testGenericErrorUsesItsSafeLocalizedDescription() {
        var announcements: [(String, NSAccessibilityPriorityLevel)] = []
        let hud = HUDController(isVoiceOverEnabled: { false }) { message, priority in
            announcements.append((message, priority))
        }
        defer { hud.dismiss() }
        let presenter = makePresenter(hud: hud)

        presenter.show(AppError.markdownFileInvalidEncoding)

        XCTAssertEqual(announcements.count, 1)
        XCTAssertEqual(
            announcements[0].0,
            "The selected file isn’t valid UTF-8. The clipboard is unchanged. Save it as UTF-8 and try again."
        )
        XCTAssertEqual(announcements[0].1, .high)
    }

    func testRendererDetailsCopyReportsSuccessWithoutExposingMarkdown() throws {
        var announcements: [String] = []
        var copiedText: String?
        let hud = HUDController(isVoiceOverEnabled: { false }) { message, _ in
            announcements.append(message)
        }
        defer { hud.dismiss() }
        let rendererPresenter = RendererErrorDetailsPresenter(
            dependencies: RendererErrorDetailsDependencies(
                present: { _ in .copy },
                copy: { text in
                    copiedText = text
                    return true
                }
            )
        )
        let presenter = makePresenter(
            rendererErrorDetailsPresenter: rendererPresenter,
            hud: hud
        )
        let report = RendererErrorReport(
            failure: RendererFailure(
                kind: .mermaidSyntax,
                diagramNumber: 2,
                sourceLine: 8
            ),
            operationID: try XCTUnwrap(DiagnosticOperationID(rawValue: "012345abcdef"))
        )

        presenter.show(report)

        XCTAssertEqual(announcements, ["Error details copied"])
        XCTAssertTrue(try XCTUnwrap(copiedText).contains("Issue: mermaid_syntax"))
        XCTAssertFalse(try XCTUnwrap(copiedText).contains("```mermaid"))
    }

    func testSizeLimitRecoveryDelegatesOnlyAfterExplicitRequest() throws {
        var splitRequests = 0
        let rendererPresenter = RendererErrorDetailsPresenter(
            dependencies: RendererErrorDetailsDependencies(
                present: { presentation in
                    XCTAssertTrue(presentation.offersSplitExport)
                    return .saveSplitPNGs
                },
                copy: { _ in
                    XCTFail("Split recovery must not copy diagnostic text")
                    return false
                }
            )
        )
        let presenter = ApplicationFeedbackPresenter(
            actions: .init(
                statusItemButton: { nil },
                saveFailedRenderAsSplitPNGs: { splitRequests += 1 }
            ),
            rendererErrorDetailsPresenter: rendererPresenter
        )
        let report = RendererErrorReport(
            failure: RendererFailure(
                kind: .sizeLimit,
                width: 1_120,
                height: 20_000
            ),
            operationID: try XCTUnwrap(DiagnosticOperationID(rawValue: "012345abcdef"))
        )

        presenter.show(report)

        XCTAssertEqual(splitRequests, 1)
    }

    private func makePresenter(
        rendererErrorDetailsPresenter: RendererErrorDetailsPresenter =
            RendererErrorDetailsPresenter(),
        hud: HUDController
    ) -> ApplicationFeedbackPresenter {
        ApplicationFeedbackPresenter(
            actions: .init(
                statusItemButton: { nil },
                saveFailedRenderAsSplitPNGs: {}
            ),
            rendererErrorDetailsPresenter: rendererErrorDetailsPresenter,
            hud: hud
        )
    }
}
