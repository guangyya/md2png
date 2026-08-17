import Foundation

extension AboutUpdatePresentation {
    static func makeLegacy(
        status: UpdateStatus,
        allowsInteractiveCheck: Bool,
        canDownload: (AvailableUpdate) -> Bool,
        localizationBundle: Bundle?,
        retryTimeText: (Date) -> String
    ) -> AboutUpdatePresentation {
        switch status.phase {
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
                    defaultValue: "Downloading md2png %1$@ — %2$ld%%",
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
        case .unknown, .upToDate, .runningNewerVersion,
             .sparkleUpdateAvailable, .sparkleDownloading, .sparkleExtracting,
             .sparkleReadyToInstall, .sparkleInstalling, .sparkleFailed:
            preconditionFailure("Expected a legacy update phase")
        }
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
}
