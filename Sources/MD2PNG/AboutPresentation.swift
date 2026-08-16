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
    case openDownloadedUpdate
}

enum AboutUpdateSecondaryAction: Equatable {
    case viewReleases
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

struct AboutUpdatePresentation: Equatable {
    let isVisible: Bool
    let symbolName: String
    let tint: AboutUpdateTint
    let title: String
    let detail: String?
    let primaryAction: AboutUpdateActionPresentation?
    let secondaryAction: AboutUpdateSecondaryActionPresentation?

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
                isVisible: false,
                symbolName: "",
                tint: .blue,
                title: "",
                detail: nil,
                primaryAction: nil,
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
