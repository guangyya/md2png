import Foundation

enum StatusMenuCommand: String, CaseIterable, Hashable {
    case renderClipboard
    case renderMarkdownFile
    case showLastRender
    case rerenderLastMarkdown
    case restoreLastMarkdown
    case theme
    case outputWidth
    case examples
    case settings
    case showWelcome
    case about
    case quit
}

enum StatusMenuLayout {
    // Keep the primary render and preview commands together, then move
    // progressively from recovery and rendering choices to infrequent commands.
    static let sections: [[StatusMenuCommand]] = [
        [.renderClipboard, .renderMarkdownFile, .showLastRender],
        [.rerenderLastMarkdown, .restoreLastMarkdown],
        [.theme, .outputWidth, .examples],
        [.settings, .showWelcome, .about],
        [.quit]
    ]
}

struct StatusMenuState: Equatable {
    let clipboardContainsMarkdown: Bool
    let hasLastSource: Bool
    let hasLastRender: Bool
    let isRendering: Bool
    let isUpdateInstallPending: Bool
}

struct StatusMenuItemPresentation: Equatable {
    let title: String
    let isEnabled: Bool
}

struct StatusMenuPresentation: Equatable {
    private let items: [StatusMenuCommand: StatusMenuItemPresentation]

    init(
        state: StatusMenuState,
        localizationBundle: Bundle? = nil
    ) {
        let blocksRenderingChanges = state.isRendering || state.isUpdateInstallPending
        let canUseLastSource = state.hasLastSource && !blocksRenderingChanges

        items = Dictionary(uniqueKeysWithValues: StatusMenuCommand.allCases.map { command in
            let isEnabled = switch command {
            case .renderClipboard:
                state.clipboardContainsMarkdown && !blocksRenderingChanges
            case .renderMarkdownFile:
                !blocksRenderingChanges
            case .showLastRender:
                state.hasLastRender
            case .rerenderLastMarkdown, .restoreLastMarkdown:
                canUseLastSource
            case .theme, .outputWidth, .examples:
                !blocksRenderingChanges
            case .settings, .showWelcome, .about, .quit:
                true
            }
            return (
                command,
                StatusMenuItemPresentation(
                    title: Self.title(for: command, localizationBundle: localizationBundle),
                    isEnabled: isEnabled
                )
            )
        })
    }

    subscript(command: StatusMenuCommand) -> StatusMenuItemPresentation {
        items[command]!
    }

    static func title(
        for command: StatusMenuCommand,
        localizationBundle: Bundle? = nil
    ) -> String {
        switch command {
        case .renderClipboard:
            L10n.text(
                "menu.render",
                defaultValue: "Render Clipboard as Image",
                bundle: localizationBundle
            )
        case .renderMarkdownFile:
            L10n.text(
                "menu.render_markdown_file",
                defaultValue: "Render Markdown File…",
                bundle: localizationBundle
            )
        case .showLastRender:
            L10n.text(
                "menu.show_last_render",
                defaultValue: "Show Last Render",
                bundle: localizationBundle
            )
        case .rerenderLastMarkdown:
            L10n.text(
                "menu.rerender_last_markdown",
                defaultValue: "Re-render Last Markdown",
                bundle: localizationBundle
            )
        case .restoreLastMarkdown:
            L10n.text(
                "menu.restore_last_markdown",
                defaultValue: "Restore Last Markdown",
                bundle: localizationBundle
            )
        case .theme:
            L10n.text(
                "menu.render_theme",
                defaultValue: "Theme",
                bundle: localizationBundle
            )
        case .outputWidth:
            L10n.text(
                "menu.render_width",
                defaultValue: "Output Width",
                bundle: localizationBundle
            )
        case .examples:
            L10n.text(
                "menu.examples",
                defaultValue: "Examples",
                bundle: localizationBundle
            )
        case .settings:
            L10n.text(
                "menu.settings",
                defaultValue: "Settings…",
                bundle: localizationBundle
            )
        case .showWelcome:
            L10n.text(
                "menu.show_welcome",
                defaultValue: "Show Welcome",
                bundle: localizationBundle
            )
        case .about:
            L10n.text(
                "menu.about",
                defaultValue: "About md2png",
                bundle: localizationBundle
            )
        case .quit:
            L10n.text(
                "menu.quit",
                defaultValue: "Quit md2png",
                bundle: localizationBundle
            )
        }
    }
}
