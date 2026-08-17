import AppKit

enum AboutRendererSelfTestState: Equatable {
    case idle
    case running
}

struct AboutRendererSelfTestDependencies {
    let run: @MainActor (@escaping PackagedRenderSelfTest.Completion) -> Void
    let presentResult: @MainActor (
        _ parentWindow: NSWindow?,
        _ result: Result<PackagedRenderSelfTestReport, PackagedRenderSelfTestFailure>
    ) -> Void

    @MainActor
    static func live(
        diagnosticLogger: DiagnosticLogger
    ) -> AboutRendererSelfTestDependencies {
        let selfTest = PackagedRenderSelfTest(diagnosticLogger: diagnosticLogger)
        return AboutRendererSelfTestDependencies(
            run: { completion in
                selfTest.run(completion: completion)
            },
            presentResult: { parentWindow, result in
                let alert = NSAlert()
                switch result {
                case let .success(report):
                    alert.alertStyle = .informational
                    alert.messageText = L10n.text(
                        "about.self_test_passed_title",
                        defaultValue: "Renderer Self-Test Passed"
                    )
                    alert.informativeText = L10n.format(
                        "about.self_test_passed_message",
                        defaultValue: "The bundled renderer produced a valid %1$ld × %2$ld PNG. The clipboard was not read or changed.",
                        report.width,
                        report.height
                    )
                case let .failure(failure):
                    alert.alertStyle = .warning
                    alert.messageText = L10n.text(
                        "about.self_test_failed_title",
                        defaultValue: "Renderer Self-Test Failed"
                    )
                    alert.informativeText = failure.userMessage()
                }
                alert.addButton(withTitle: L10n.text("common.ok", defaultValue: "OK"))
                if let parentWindow, parentWindow.isVisible {
                    alert.beginSheetModal(for: parentWindow)
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            }
        )
    }
}

enum AboutRendererSelfTestPresentation {
    static func buttonTitle(for state: AboutRendererSelfTestState) -> String {
        switch state {
        case .idle:
            return L10n.text(
                "about.run_renderer_self_test",
                defaultValue: "Renderer Self-Test"
            )
        case .running:
            return L10n.text(
                "about.renderer_self_test_running",
                defaultValue: "Testing…"
            )
        }
    }

    static func symbolName(for state: AboutRendererSelfTestState) -> String {
        switch state {
        case .idle: "stethoscope"
        case .running: "hourglass"
        }
    }
}

enum AboutDiagnosticsPresentation {
    static func buttonTitle(
        selfTestState: AboutRendererSelfTestState,
        saveState: AboutDiagnosticSaveState
    ) -> String {
        if selfTestState == .running {
            return AboutRendererSelfTestPresentation.buttonTitle(for: selfTestState)
        }
        if saveState != .idle {
            return AboutDiagnosticSavePresentation.buttonTitle(for: saveState)
        }
        return L10n.text(
            "about.diagnostics",
            defaultValue: "Diagnostics…"
        )
    }

    static func symbolName(
        selfTestState: AboutRendererSelfTestState,
        saveState: AboutDiagnosticSaveState
    ) -> String {
        if selfTestState == .running {
            return AboutRendererSelfTestPresentation.symbolName(for: selfTestState)
        }
        if saveState != .idle {
            return AboutDiagnosticSavePresentation.symbolName(for: saveState)
        }
        return "stethoscope"
    }
}

extension PackagedRenderSelfTestFailure {
    func userMessage(localizationBundle: Bundle? = nil) -> String {
        switch self {
        case .notPackagedApplication:
            return L10n.text(
                "about.self_test_failure_not_packaged",
                defaultValue: "Self-Test is available only from the packaged md2png app.",
                bundle: localizationBundle
            )
        case .rendererResourcesUnavailable, .markdownResourceUnavailable,
             .invalidMarkdownResource:
            return L10n.text(
                "about.self_test_failure_resources",
                defaultValue: "A bundled renderer resource is missing or invalid. Reinstall md2png and try again. The clipboard was not changed.",
                bundle: localizationBundle
            )
        case .renderingFailed, .invalidImage:
            return L10n.text(
                "about.self_test_failure_rendering",
                defaultValue: "The bundled renderer did not produce a valid PNG. Save diagnostic logs and include them with your report. The clipboard was not changed.",
                bundle: localizationBundle
            )
        case .timedOut:
            return L10n.text(
                "about.self_test_failure_timeout",
                defaultValue: "The bundled renderer self-test timed out. Reopen md2png and try again. The clipboard was not changed.",
                bundle: localizationBundle
            )
        }
    }
}
