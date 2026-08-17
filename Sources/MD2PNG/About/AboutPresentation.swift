import Foundation

enum AboutUpdateTint: Equatable {
    case green
    case blue
    case orange
}

enum AboutUpdatePrimaryAction: Equatable {
    case checkAgain
    case download
    case cancel
    case installAndRelaunch
    case openDownloadedUpdate
}

enum AboutUpdateSecondaryAction: Equatable {
    case viewReleases
    case viewFullReleaseNotes
    case installLater
    case revealDownloadedUpdate
}

struct AboutUpdateActionPresentation: Equatable {
    let title: String
    let isEnabled: Bool
    let isEmphasized: Bool
    let toolTip: String?
    let action: AboutUpdatePrimaryAction
}

struct AboutUpdateSecondaryActionPresentation: Equatable {
    let title: String
    let action: AboutUpdateSecondaryAction
}

struct AboutUpdateReleaseNotesPresentation: Equatable {
    let title: String
    let text: String
    let showsFullReleaseNotesAction: Bool
}

struct AboutUpdatePresentation: Equatable {
    let isVisible: Bool
    let symbolName: String
    let tint: AboutUpdateTint
    let title: String
    let detail: String?
    let primaryAction: AboutUpdateActionPresentation?
    let secondaryAction: AboutUpdateSecondaryActionPresentation?
    let releaseNotes: AboutUpdateReleaseNotesPresentation?

    init(
        isVisible: Bool,
        symbolName: String,
        tint: AboutUpdateTint,
        title: String,
        detail: String?,
        primaryAction: AboutUpdateActionPresentation?,
        secondaryAction: AboutUpdateSecondaryActionPresentation?,
        releaseNotes: AboutUpdateReleaseNotesPresentation? = nil
    ) {
        self.isVisible = isVisible
        self.symbolName = symbolName
        self.tint = tint
        self.title = title
        self.detail = detail
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.releaseNotes = releaseNotes
    }

    static func make(
        status: UpdateStatus,
        allowsInteractiveCheck: Bool,
        canDownload: (AvailableUpdate) -> Bool,
        localizationBundle: Bundle? = nil,
        retryTimeText: (Date) -> String = {
            $0.formatted(date: .omitted, time: .shortened)
        }
    ) -> AboutUpdatePresentation {
        switch status.phase {
        case .unknown:
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: status.isChecking ? "arrow.triangle.2.circlepath" : "arrow.down.circle",
                tint: .blue,
                title: status.isChecking
                    ? L10n.text(
                        "about.update_checking",
                        defaultValue: "Checking…",
                        bundle: localizationBundle
                    )
                    : L10n.text(
                        "about.updates",
                        defaultValue: "Updates",
                        bundle: localizationBundle
                    ),
                detail: nil,
                primaryAction: AboutUpdateActionPresentation(
                    title: status.isChecking
                        ? L10n.text(
                            "about.update_checking",
                            defaultValue: "Checking…",
                            bundle: localizationBundle
                        )
                        : L10n.text(
                            "about.check_for_updates",
                            defaultValue: "Check for Updates…",
                            bundle: localizationBundle
                        ),
                    isEnabled: allowsInteractiveCheck && !status.isChecking,
                    isEmphasized: false,
                    toolTip: nil,
                    action: .checkAgain
                ),
                secondaryAction: nil
            )
        case let .upToDate(version):
            let actionTitle: String
            switch status.manualCheckFeedback {
            case .checking:
                actionTitle = L10n.text(
                    "about.update_checking",
                    defaultValue: "Checking…",
                    bundle: localizationBundle
                )
            case .completed where status.nextManualCheckAt != nil:
                actionTitle = L10n.text(
                    "about.update_checked_recently",
                    defaultValue: "Checked just now",
                    bundle: localizationBundle
                )
            case .none where status.nextManualCheckAt != nil:
                actionTitle = L10n.text(
                    "about.update_check_again_later",
                    defaultValue: "Check Again Later",
                    bundle: localizationBundle
                )
            case .none, .completed:
                actionTitle = L10n.text(
                    "about.update_check_again",
                    defaultValue: "Check Again",
                    bundle: localizationBundle
                )
            }
            let canPerformAction = allowsInteractiveCheck
                && !status.isChecking
                && status.nextManualCheckAt == nil
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: "checkmark.circle.fill",
                tint: .green,
                title: L10n.format(
                    "about.update_up_to_date",
                    defaultValue: "Up to Date · %@",
                    bundle: localizationBundle,
                    version.description
                ),
                detail: nil,
                primaryAction: AboutUpdateActionPresentation(
                    title: actionTitle,
                    isEnabled: canPerformAction,
                    isEmphasized: false,
                    toolTip: retryToolTip(
                        canPerformAction: canPerformAction,
                        retryAt: status.nextManualCheckAt,
                        localizationBundle: localizationBundle,
                        retryTimeText: retryTimeText
                    ),
                    action: .checkAgain
                ),
                secondaryAction: nil
            )
        case let .runningNewerVersion(version):
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: "checkmark.circle.fill",
                tint: .green,
                title: L10n.text(
                    "about.update_running_newer",
                    defaultValue: "You’re running a newer build",
                    bundle: localizationBundle
                ),
                detail: L10n.format(
                    "about.update_latest_published",
                    defaultValue: "Latest published version: %@",
                    bundle: localizationBundle,
                    version
                ),
                primaryAction: AboutUpdateActionPresentation(
                    title: L10n.text(
                        "about.update_check_again",
                        defaultValue: "Check Again",
                        bundle: localizationBundle
                    ),
                    isEnabled: allowsInteractiveCheck
                        && !status.isChecking
                        && status.nextManualCheckAt == nil,
                    isEmphasized: false,
                    toolTip: retryToolTip(
                        canPerformAction: status.nextManualCheckAt == nil,
                        retryAt: status.nextManualCheckAt,
                        localizationBundle: localizationBundle,
                        retryTimeText: retryTimeText
                    ),
                    action: .checkAgain
                ),
                secondaryAction: nil
            )
        case let .sparkleUpdateAvailable(update):
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: "arrow.down.circle.fill",
                tint: .blue,
                title: L10n.format(
                    "about.update_available_transition",
                    defaultValue: "Update available · %@ → %@",
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
                    defaultValue: "Downloading md2png %@ — %ld%%",
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
                    defaultValue: "Preparing md2png %@ — %ld%%",
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
                    defaultValue: "Relaunch clears Last Render and Last Source. The clipboard is unchanged.",
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
        case let .updateAvailable(update):
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: "arrow.down.circle.fill",
                tint: .blue,
                title: L10n.format(
                    "about.update_available",
                    defaultValue: "Update available · %@",
                    bundle: localizationBundle,
                    update.version.description
                ),
                detail: nil,
                primaryAction: AboutUpdateActionPresentation(
                    title: L10n.text(
                        "about.update_download",
                        defaultValue: "Download Update",
                        bundle: localizationBundle
                    ),
                    isEnabled: !status.isChecking && canDownload(update),
                    isEmphasized: true,
                    toolTip: nil,
                    action: .download
                ),
                secondaryAction: nil
            )
        case let .downloading(update, progressPercent):
            return cancellablePresentation(
                symbolName: "arrow.down.circle",
                title: L10n.format(
                    "about.update_downloading_progress",
                    defaultValue: "Downloading md2png %@ — %ld%%",
                    bundle: localizationBundle,
                    update.version.description,
                    progressPercent
                ),
                localizationBundle: localizationBundle
            )
        case let .verifying(update):
            return cancellablePresentation(
                symbolName: "checkmark.shield",
                title: L10n.format(
                    "about.update_verifying_version",
                    defaultValue: "Verifying md2png %@…",
                    bundle: localizationBundle,
                    update.version.description
                ),
                localizationBundle: localizationBundle
            )
        case let .opening(update):
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: "opticaldiscdrive",
                tint: .blue,
                title: L10n.format(
                    "about.update_opening_version",
                    defaultValue: "Opening md2png %@…",
                    bundle: localizationBundle,
                    update.version.description
                ),
                detail: nil,
                primaryAction: nil,
                secondaryAction: nil
            )
        case let .readyToInstall(update, _):
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: "checkmark.circle.fill",
                tint: .green,
                title: L10n.format(
                    "about.update_ready",
                    defaultValue: "Ready to install · %@",
                    bundle: localizationBundle,
                    update.version.description
                ),
                detail: L10n.text(
                    "about.update_ready_detail",
                    defaultValue: "Downloaded — open the DMG and drag md2png into Applications.",
                    bundle: localizationBundle
                ),
                primaryAction: AboutUpdateActionPresentation(
                    title: L10n.text(
                        "about.update_open_again",
                        defaultValue: "Open",
                        bundle: localizationBundle
                    ),
                    isEnabled: true,
                    isEmphasized: true,
                    toolTip: nil,
                    action: .openDownloadedUpdate
                ),
                secondaryAction: AboutUpdateSecondaryActionPresentation(
                    title: L10n.text(
                        "about.update_show_in_finder",
                        defaultValue: "Show in Finder",
                        bundle: localizationBundle
                    ),
                    action: .revealDownloadedUpdate
                )
            )
        case let .failed(message, releasesURL, _, availableUpdate):
            let canPerformAction: Bool
            let actionTitle: String
            let action: AboutUpdatePrimaryAction
            if let availableUpdate {
                canPerformAction = !status.isChecking && canDownload(availableUpdate)
                actionTitle = L10n.text(
                    "about.update_retry_download",
                    defaultValue: "Retry Download",
                    bundle: localizationBundle
                )
                action = .download
            } else {
                canPerformAction = allowsInteractiveCheck
                    && !status.isChecking
                    && status.nextManualCheckAt == nil
                if status.manualCheckFeedback == .checking {
                    actionTitle = L10n.text(
                        "about.update_checking",
                        defaultValue: "Checking…",
                        bundle: localizationBundle
                    )
                } else if status.nextManualCheckAt != nil {
                    actionTitle = L10n.text(
                        "about.update_try_again_later",
                        defaultValue: "Try Again Later",
                        bundle: localizationBundle
                    )
                } else {
                    actionTitle = L10n.text(
                        "about.update_retry_check",
                        defaultValue: "Try Again",
                        bundle: localizationBundle
                    )
                }
                action = .checkAgain
            }
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: "exclamationmark.triangle.fill",
                tint: .orange,
                title: availableUpdate == nil
                    ? L10n.text(
                        "about.update_check_failed",
                        defaultValue: "Update check failed",
                        bundle: localizationBundle
                    )
                    : L10n.text(
                        "about.update_download_failed",
                        defaultValue: "Download failed",
                        bundle: localizationBundle
                    ),
                detail: message,
                primaryAction: AboutUpdateActionPresentation(
                    title: actionTitle,
                    isEnabled: canPerformAction,
                    isEmphasized: true,
                    toolTip: retryToolTip(
                        canPerformAction: canPerformAction,
                        retryAt: status.nextManualCheckAt,
                        localizationBundle: localizationBundle,
                        retryTimeText: retryTimeText
                    ),
                    action: action
                ),
                secondaryAction: releasesURL.map { _ in
                    AboutUpdateSecondaryActionPresentation(
                        title: L10n.text(
                            "about.view_all_releases",
                            defaultValue: "View Releases",
                            bundle: localizationBundle
                        ),
                        action: .viewReleases
                    )
                }
            )
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
                defaultValue: "Released %@ · %@",
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

    private static func cancellablePresentation(
        symbolName: String,
        title: String,
        localizationBundle: Bundle?
    ) -> AboutUpdatePresentation {
        AboutUpdatePresentation(
            isVisible: true,
            symbolName: symbolName,
            tint: .blue,
            title: title,
            detail: nil,
            primaryAction: AboutUpdateActionPresentation(
                title: L10n.text(
                    "common.cancel",
                    defaultValue: "Cancel",
                    bundle: localizationBundle
                ),
                isEnabled: true,
                isEmphasized: false,
                toolTip: nil,
                action: .cancel
            ),
            secondaryAction: nil
        )
    }

    private static func retryToolTip(
        canPerformAction: Bool,
        retryAt: Date?,
        localizationBundle: Bundle?,
        retryTimeText: (Date) -> String
    ) -> String? {
        guard !canPerformAction, let retryAt else { return nil }
        return L10n.format(
            "about.update_retry_after",
            defaultValue: "Try again after %@.",
            bundle: localizationBundle,
            retryTimeText(retryAt)
        )
    }
}
