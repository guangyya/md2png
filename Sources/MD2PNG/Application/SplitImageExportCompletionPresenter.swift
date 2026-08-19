import AppKit

struct SplitImageExportCompletionPresentation: Equatable {
    let title: String
    let message: String
    let showInFinderTitle: String
    let doneTitle: String

    static func make(
        count: Int,
        directoryURL: URL,
        localizationBundle: Bundle? = nil
    ) -> SplitImageExportCompletionPresentation {
        SplitImageExportCompletionPresentation(
            title: count == 1
                ? L10n.text(
                    "split_export.saved_one_title",
                    defaultValue: "Saved 1 Split PNG",
                    bundle: localizationBundle
                )
                : L10n.format(
                    "split_export.saved_many_title",
                    defaultValue: "Saved %ld Split PNGs",
                    bundle: localizationBundle,
                    count
                ),
            message: L10n.format(
                "split_export.saved_message",
                defaultValue: "The numbered PNG files were saved in “%@”.",
                bundle: localizationBundle,
                directoryURL.lastPathComponent
            ),
            showInFinderTitle: L10n.text(
                "common.show_in_finder",
                defaultValue: "Show in Finder",
                bundle: localizationBundle
            ),
            doneTitle: L10n.text(
                "common.done",
                defaultValue: "Done",
                bundle: localizationBundle
            )
        )
    }
}

@MainActor
final class SplitImageExportCompletionPresenter {
    struct Dependencies {
        let confirmShowInFinder: (SplitImageExportCompletionPresentation) -> Bool
        let revealFiles: ([URL]) -> Void

        @MainActor
        static func live() -> Dependencies {
            Dependencies(confirmShowInFinder: { presentation in
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = presentation.title
                alert.informativeText = presentation.message
                let showButton = alert.addButton(withTitle: presentation.showInFinderTitle)
                let doneButton = alert.addButton(withTitle: presentation.doneTitle)
                AlertKeyboard.configureDefaultAndCancel(
                    in: alert,
                    defaultButton: showButton,
                    cancelButton: doneButton
                )
                NSApp.activate(ignoringOtherApps: true)
                return alert.runModal() == .alertFirstButtonReturn
            },
            revealFiles: { fileURLs in
                NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
            })
        }
    }

    private let dependencies: Dependencies

    convenience init() {
        self.init(dependencies: .live())
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func show(count: Int, directoryURL: URL) {
        let presentation = SplitImageExportCompletionPresentation.make(
            count: count,
            directoryURL: directoryURL
        )
        guard dependencies.confirmShowInFinder(presentation) else { return }
        dependencies.revealFiles(SplitImageExportNaming.fileNames(
            directoryName: directoryURL.lastPathComponent,
            count: count
        ).map { directoryURL.appendingPathComponent($0, isDirectory: false) })
    }
}
