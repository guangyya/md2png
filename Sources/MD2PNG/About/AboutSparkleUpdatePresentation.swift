import Foundation

extension AboutUpdatePresentation {
    static func makeSparkle(
        status: UpdateStatus,
        allowsInteractiveCheck: Bool,
        localizationBundle: Bundle?
    ) -> AboutUpdatePresentation {
        switch status.phase {
        case let .sparkleUpdateAvailable(update):
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: "arrow.down.circle.fill",
                tint: .blue,
                title: L10n.format(
                    "about.update_available_transition",
                    defaultValue: "Update available · %1$@ → %2$@",
                    bundle: localizationBundle,
                    update.installedVersion,
                    update.displayVersion
                ),
                detail: updateMetadataDetail(
                    update,
                    localizationBundle: localizationBundle
                ),
                primaryAction: AboutUpdateActionPresentation(
                    title: L10n.text(
                        "about.update_download",
                        defaultValue: "Download Update",
                        bundle: localizationBundle
                    ),
                    isEnabled: allowsInteractiveCheck && !status.isChecking,
                    isEmphasized: true,
                    toolTip: nil,
                    action: .download
                ),
                secondaryAction: nil,
                releaseNotes: releaseNotesPresentation(
                    update,
                    localizationBundle: localizationBundle
                )
            )
        case let .sparkleDownloading(update, progressPercent):
            let title = progressPercent.map {
                L10n.format(
                    "about.update_downloading_progress",
                    defaultValue: "Downloading md2png %1$@ — %2$ld%%",
                    bundle: localizationBundle,
                    update.displayVersion,
                    $0
                )
            } ?? L10n.format(
                "about.update_downloading_version",
                defaultValue: "Downloading md2png %@…",
                bundle: localizationBundle,
                update.displayVersion
            )
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: "arrow.down.circle",
                tint: .blue,
                title: title,
                detail: nil,
                primaryAction: AboutUpdateActionPresentation(
                    title: L10n.text(
                        "common.cancel",
                        defaultValue: "Cancel",
                        bundle: localizationBundle
                    ),
                    isEnabled: allowsInteractiveCheck,
                    isEmphasized: false,
                    toolTip: nil,
                    action: .cancel
                ),
                secondaryAction: nil,
                releaseNotes: releaseNotesPresentation(
                    update,
                    localizationBundle: localizationBundle
                )
            )
        case let .sparkleExtracting(update, progressPercent):
            let title = progressPercent.map {
                L10n.format(
                    "about.update_preparing_progress",
                    defaultValue: "Preparing md2png %1$@ — %2$ld%%",
                    bundle: localizationBundle,
                    update.displayVersion,
                    $0
                )
            } ?? L10n.format(
                "about.update_preparing_version",
                defaultValue: "Preparing md2png %@…",
                bundle: localizationBundle,
                update.displayVersion
            )
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: "checkmark.shield",
                tint: .blue,
                title: title,
                detail: L10n.text(
                    "about.update_preparing_detail",
                    defaultValue: "Verifying the signed update and getting it ready to install.",
                    bundle: localizationBundle
                ),
                primaryAction: nil,
                secondaryAction: nil,
                releaseNotes: releaseNotesPresentation(
                    update,
                    localizationBundle: localizationBundle
                )
            )
        case let .sparkleReadyToInstall(update):
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: "checkmark.circle.fill",
                tint: .green,
                title: L10n.format(
                    "about.update_ready",
                    defaultValue: "Ready to install · %@",
                    bundle: localizationBundle,
                    update.displayVersion
                ),
                detail: L10n.text(
                    "about.update_relaunch_memory_detail",
                    defaultValue: "Relaunch clears Last Render and Last Markdown. The clipboard is unchanged.",
                    bundle: localizationBundle
                ),
                primaryAction: AboutUpdateActionPresentation(
                    title: L10n.text(
                        "about.update_install_relaunch",
                        defaultValue: "Install and Relaunch",
                        bundle: localizationBundle
                    ),
                    isEnabled: allowsInteractiveCheck,
                    isEmphasized: true,
                    toolTip: nil,
                    action: .installAndRelaunch
                ),
                secondaryAction: AboutUpdateSecondaryActionPresentation(
                    title: L10n.text(
                        "about.update_later",
                        defaultValue: "Later",
                        bundle: localizationBundle
                    ),
                    action: .installLater
                ),
                releaseNotes: releaseNotesPresentation(
                    update,
                    localizationBundle: localizationBundle
                )
            )
        case let .sparkleInstalling(update):
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: "arrow.triangle.2.circlepath",
                tint: .blue,
                title: L10n.format(
                    "about.update_installing_version",
                    defaultValue: "Installing md2png %@…",
                    bundle: localizationBundle,
                    update.displayVersion
                ),
                detail: L10n.text(
                    "about.update_installing_detail",
                    defaultValue: "md2png will quit and reopen when installation completes.",
                    bundle: localizationBundle
                ),
                primaryAction: nil,
                secondaryAction: nil,
                releaseNotes: releaseNotesPresentation(
                    update,
                    localizationBundle: localizationBundle
                )
            )
        case let .sparkleFailed(message, update):
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: "exclamationmark.triangle.fill",
                tint: .orange,
                title: L10n.text(
                    "about.update_failed",
                    defaultValue: "Update failed",
                    bundle: localizationBundle
                ),
                detail: message,
                primaryAction: update.map { _ in
                    AboutUpdateActionPresentation(
                        title: L10n.text(
                            "about.update_retry_download",
                            defaultValue: "Retry Download",
                            bundle: localizationBundle
                        ),
                        isEnabled: allowsInteractiveCheck,
                        isEmphasized: true,
                        toolTip: nil,
                        action: .download
                    )
                },
                secondaryAction: AboutUpdateSecondaryActionPresentation(
                    title: L10n.text(
                        "about.update_manual_download",
                        defaultValue: "Manual Download",
                        bundle: localizationBundle
                    ),
                    action: .viewReleases
                ),
                releaseNotes: update.map {
                    releaseNotesPresentation(
                        $0,
                        localizationBundle: localizationBundle
                    )
                }
            )
        case .unknown, .upToDate, .runningNewerVersion,
             .failed:
            preconditionFailure("Expected a Sparkle update phase")
        }
    }

    private static func updateMetadataDetail(
        _ update: SeamlessUpdate,
        localizationBundle: Bundle?
    ) -> String? {
        let date = update.publishedAt?.formatted(date: .abbreviated, time: .omitted)
        let size = update.contentLength.map { length in
            ByteCountFormatter.string(
                fromByteCount: Int64(clamping: length),
                countStyle: .file
            )
        }
        switch (date, size) {
        case let (.some(date), .some(size)):
            return L10n.format(
                "about.update_release_date_size",
                defaultValue: "Released %1$@ · %2$@",
                bundle: localizationBundle,
                date,
                size
            )
        case let (.some(date), .none):
            return L10n.format(
                "about.update_release_date",
                defaultValue: "Released %@",
                bundle: localizationBundle,
                date
            )
        case let (.none, .some(size)):
            return L10n.format(
                "about.update_download_size",
                defaultValue: "Download size: %@",
                bundle: localizationBundle,
                size
            )
        case (.none, .none):
            return nil
        }
    }

    private static func releaseNotesPresentation(
        _ update: SeamlessUpdate,
        localizationBundle: Bundle?
    ) -> AboutUpdateReleaseNotesPresentation {
        var sections = update.releaseNotes.map { notes in
            var heading = L10n.format(
                "about.update_release_version",
                defaultValue: "Version %@",
                bundle: localizationBundle,
                notes.version
            )
            if let publishedAt = notes.publishedAt {
                heading += " · " + publishedAt.formatted(date: .abbreviated, time: .omitted)
            }
            let text = notes.text ?? L10n.text(
                "about.update_release_notes_unavailable",
                defaultValue: "Release notes unavailable.",
                bundle: localizationBundle
            )
            return "\(heading)\n\(text)"
        }
        if sections.isEmpty {
            sections = [L10n.text(
                "about.update_release_notes_unavailable",
                defaultValue: "Release notes unavailable.",
                bundle: localizationBundle
            )]
        }
        if update.historyIsTruncated {
            sections.append(L10n.text(
                "about.update_history_truncated",
                defaultValue: "Earlier release notes are not shown here. View the complete history online.",
                bundle: localizationBundle
            ))
        }
        return AboutUpdateReleaseNotesPresentation(
            title: L10n.format(
                "about.whats_new",
                defaultValue: "What’s new in %@",
                bundle: localizationBundle,
                update.displayVersion
            ),
            text: sections.joined(separator: "\n\n"),
            showsFullReleaseNotesAction: update.fullReleaseNotesURL != nil
        )
    }
}
