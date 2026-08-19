import AppKit

@MainActor
final class ApplicationFeedbackPresenter {
    struct Actions {
        let statusItemButton: () -> NSStatusBarButton?
        let saveFailedRenderAsSplitPNGs: () -> Void
    }

    private let actions: Actions
    private let splitImageExportCompletionPresenter: SplitImageExportCompletionPresenter
    private let rendererErrorDetailsPresenter: RendererErrorDetailsPresenter
    private lazy var hud = HUDController(announce: { [weak self] message, priority in
        self?.announce(message, priority: priority)
    })

    init(
        actions: Actions,
        splitImageExportCompletionPresenter: SplitImageExportCompletionPresenter =
            SplitImageExportCompletionPresenter(),
        rendererErrorDetailsPresenter: RendererErrorDetailsPresenter =
            RendererErrorDetailsPresenter()
    ) {
        self.actions = actions
        self.splitImageExportCompletionPresenter = splitImageExportCompletionPresenter
        self.rendererErrorDetailsPresenter = rendererErrorDetailsPresenter
    }

    func showHUD(
        _ message: String,
        symbol: String,
        style: HUDStyle,
        announces: Bool = false
    ) {
        hud.show(message, symbol: symbol, style: style, announces: announces)
    }

    func showShortcutConflict() {
        hud.show(
            L10n.text(
                "hud.shortcut_conflict",
                defaultValue: "A global shortcut is already in use — menu commands still work"
            ),
            symbol: "keyboard.badge.ellipsis",
            style: .error
        )
    }

    func showPreviewCopied() {
        hud.show(
            L10n.text(
                "hud.png_copied_again",
                defaultValue: "PNG copied again — paste with Command-V"
            ),
            symbol: "doc.on.clipboard.fill",
            accessibilityAnnouncement: L10n.text(
                "hud.png_copied_again_accessibility",
                defaultValue: "PNG copied again and ready to paste with Command-V"
            )
        )
    }

    func show(_ notice: RenderCoordinatorNotice) {
        switch notice {
        case .imageCopied:
            hud.show(
                L10n.text(
                    "hud.png_copied",
                    defaultValue: "PNG copied — paste with Command-V"
                ),
                symbol: "checkmark.circle.fill",
                accessibilityAnnouncement: L10n.text(
                    "hud.png_copied_accessibility",
                    defaultValue: "PNG copied and ready to paste with Command-V"
                )
            )
        case .markdownRestored:
            hud.show(
                L10n.text(
                    "hud.markdown_restored",
                    defaultValue: "Markdown restored — paste with Command-V"
                ),
                symbol: "doc.on.clipboard.fill",
                accessibilityAnnouncement: L10n.text(
                    "hud.markdown_restored_accessibility",
                    defaultValue: "Markdown restored and ready to paste with Command-V"
                )
            )
        case let .splitImagesSaved(count, directoryURL):
            splitImageExportCompletionPresenter.show(
                count: count,
                directoryURL: directoryURL
            )
        }
    }

    func show(_ error: Error) {
        if let report = error as? RendererErrorReport {
            switch rendererErrorDetailsPresenter.show(report) {
            case .detailsCopied:
                hud.show(
                    L10n.text(
                        "renderer_error.details_copied",
                        defaultValue: "Error details copied"
                    ),
                    symbol: "doc.on.clipboard.fill",
                    style: .informational
                )
            case .splitExportRequested:
                actions.saveFailedRenderAsSplitPNGs()
            case .dismissed:
                break
            }
            return
        }
        hud.show(
            error.localizedDescription,
            symbol: "exclamationmark.triangle.fill",
            style: .error
        )
    }

    func confirmClipboardOverwrite(_ action: ClipboardOverwriteAction) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text(
            "confirmation.clipboard_changed.title",
            defaultValue: "Clipboard Changed"
        )
        alert.informativeText = switch action {
        case .rerenderLastMarkdown:
            L10n.text(
                "confirmation.clipboard_changed.rerender",
                defaultValue: "Another app changed the clipboard. Replace it with a new PNG rendered from the last Markdown?"
            )
        case .restoreLastMarkdown:
            L10n.text(
                "confirmation.clipboard_changed.restore",
                defaultValue: "Another app changed the clipboard. Replace it with the last Markdown?"
            )
        }
        let primaryButtonTitle = switch action {
        case .rerenderLastMarkdown:
            L10n.text(
                "confirmation.render_and_replace",
                defaultValue: "Render and Replace"
            )
        case .restoreLastMarkdown:
            L10n.text("common.replace", defaultValue: "Replace")
        }
        let primaryButton = alert.addButton(withTitle: primaryButtonTitle)
        let cancelButton = alert.addButton(withTitle: L10n.text(
            "common.cancel",
            defaultValue: "Cancel"
        ))
        AlertKeyboard.configureDefaultAndCancel(
            in: alert,
            defaultButton: primaryButton,
            cancelButton: cancelButton
        )
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func approveInstallAndRelaunch(
        _ update: SeamlessUpdate,
        canBeginUpdateInstall: Bool,
        hasTransientContent: Bool
    ) -> Bool {
        guard canBeginUpdateInstall else {
            hud.show(
                L10n.text(
                    "update.finish_render_before_install",
                    defaultValue: "Finish the current render, then choose Install and Relaunch again."
                ),
                symbol: "hourglass",
                style: .error
            )
            return false
        }
        guard hasTransientContent else { return true }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.format(
            "update.confirm_relaunch_title",
            defaultValue: "Install md2png %@ and relaunch?",
            update.displayVersion
        )
        alert.informativeText = L10n.text(
            "update.confirm_relaunch_detail",
            defaultValue: "Relaunching clears Last Render and Last Markdown because they exist only in memory. Your clipboard will not be changed."
        )
        let installButton = alert.addButton(withTitle: L10n.text(
            "about.update_install_relaunch",
            defaultValue: "Install and Relaunch"
        ))
        let laterButton = alert.addButton(withTitle: L10n.text(
            "about.update_later",
            defaultValue: "Later"
        ))
        AlertKeyboard.configureDefaultAndCancel(
            in: alert,
            defaultButton: installButton,
            cancelButton: laterButton
        )
        return alert.runModal() == .alertFirstButtonReturn
    }

    func announce(
        _ message: String,
        priority: NSAccessibilityPriorityLevel
    ) {
        guard let button = actions.statusItemButton() else { return }
        NSAccessibility.post(
            element: button,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: priority.rawValue
            ]
        )
    }
}
