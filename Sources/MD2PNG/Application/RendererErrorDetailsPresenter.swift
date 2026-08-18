import AppKit

enum RendererErrorDetailsAction: Equatable {
    case done
    case copy
    case saveSplitPNGs
}

enum RendererErrorDetailsResult: Equatable {
    case dismissed
    case detailsCopied
    case splitExportRequested
}

struct RendererErrorDetailsPresentation: Equatable {
    let title: String
    let summary: String
    let suggestion: String
    let clipboardNotice: String
    let copyText: String
    let offersSplitExport: Bool

    static func make(
        report: RendererErrorReport,
        application: DiagnosticApplicationInfo = .current(),
        system: DiagnosticSystemInfo = .current,
        localizationBundle: Bundle? = nil
    ) -> RendererErrorDetailsPresentation {
        RendererErrorDetailsPresentation(
            title: L10n.text(
                "renderer_error.details_title",
                defaultValue: "Rendering Failed",
                bundle: localizationBundle
            ),
            summary: report.failure.summary(localizationBundle: localizationBundle),
            suggestion: report.failure.suggestion(localizationBundle: localizationBundle),
            clipboardNotice: L10n.text(
                "renderer_error.clipboard_unchanged",
                defaultValue: "The clipboard was not changed.",
                bundle: localizationBundle
            ),
            copyText: report.copiedDetails(
                application: application,
                system: system,
                localizationBundle: localizationBundle
            ),
            offersSplitExport: report.failure.supportsSplitExportRecovery
        )
    }
}

@MainActor
struct RendererErrorDetailsDependencies {
    let present: (RendererErrorDetailsPresentation) -> RendererErrorDetailsAction
    let copy: (String) -> Bool

    static let live = RendererErrorDetailsDependencies(
        present: { presentation in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = presentation.title
            alert.informativeText = [
                presentation.summary,
                presentation.suggestion,
                presentation.clipboardNotice
            ].joined(separator: "\n\n")
            if presentation.offersSplitExport {
                let splitButton = alert.addButton(withTitle: L10n.text(
                    "renderer_error.save_split_pngs",
                    defaultValue: "Save as Split PNGs…"
                ))
                let doneButton = alert.addButton(withTitle: L10n.text(
                    "about.done",
                    defaultValue: "Done"
                ))
                let copyButton = alert.addButton(withTitle: L10n.text(
                    "renderer_error.copy_details",
                    defaultValue: "Copy Error Details"
                ))
                copyButton.keyEquivalent = ""
                AlertKeyboard.configureDefaultAndCancel(
                    in: alert,
                    defaultButton: splitButton,
                    cancelButton: doneButton
                )
            } else {
                let doneButton = alert.addButton(withTitle: L10n.text(
                    "about.done",
                    defaultValue: "Done"
                ))
                doneButton.keyEquivalent = "\r"
                let copyButton = alert.addButton(withTitle: L10n.text(
                    "renderer_error.copy_details",
                    defaultValue: "Copy Error Details"
                ))
                copyButton.keyEquivalent = ""
            }
            NSApp.activate(ignoringOtherApps: true)
            return switch alert.runModal() {
            case .alertFirstButtonReturn:
                presentation.offersSplitExport ? .saveSplitPNGs : .done
            case .alertSecondButtonReturn:
                presentation.offersSplitExport ? .done : .copy
            case .alertThirdButtonReturn:
                presentation.offersSplitExport ? .copy : .done
            default:
                .done
            }
        },
        copy: { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        }
    )
}

@MainActor
final class RendererErrorDetailsPresenter {
    private let dependencies: RendererErrorDetailsDependencies
    private let application: DiagnosticApplicationInfo
    private let system: DiagnosticSystemInfo

    init(
        dependencies: RendererErrorDetailsDependencies = .live,
        application: DiagnosticApplicationInfo = .current(),
        system: DiagnosticSystemInfo = .current
    ) {
        self.dependencies = dependencies
        self.application = application
        self.system = system
    }

    func show(_ report: RendererErrorReport) -> RendererErrorDetailsResult {
        let presentation = RendererErrorDetailsPresentation.make(
            report: report,
            application: application,
            system: system
        )
        switch dependencies.present(presentation) {
        case .saveSplitPNGs where presentation.offersSplitExport:
            return .splitExportRequested
        case .copy:
            return dependencies.copy(presentation.copyText) ? .detailsCopied : .dismissed
        case .done, .saveSplitPNGs:
            return .dismissed
        }
    }
}
