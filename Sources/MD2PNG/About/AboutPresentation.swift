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
}

enum AboutUpdateSecondaryAction: Equatable {
    case viewReleases
    case viewFullReleaseNotes
    case installLater
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
        localizationBundle: Bundle? = nil,
        retryTimeText: (Date) -> String = {
            $0.formatted(date: .omitted, time: .shortened)
        }
    ) -> AboutUpdatePresentation {
        switch status.phase {
        case .unknown, .upToDate, .runningNewerVersion, .failed:
            return makeCommon(
                status: status,
                allowsInteractiveCheck: allowsInteractiveCheck,
                localizationBundle: localizationBundle,
                retryTimeText: retryTimeText
            )
        case .sparkleUpdateAvailable, .sparkleDownloading, .sparkleExtracting,
             .sparkleReadyToInstall, .sparkleInstalling, .sparkleFailed:
            return makeSparkle(
                status: status,
                allowsInteractiveCheck: allowsInteractiveCheck,
                localizationBundle: localizationBundle
            )
        }
    }

    private static func makeCommon(
        status: UpdateStatus,
        allowsInteractiveCheck: Bool,
        localizationBundle: Bundle?,
        retryTimeText: (Date) -> String
    ) -> AboutUpdatePresentation {
        switch status.phase {
        case .unknown:
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: status.isChecking
                    ? "arrow.triangle.2.circlepath"
                    : "arrow.down.circle",
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
            let actionTitle = upToDateActionTitle(
                status: status,
                localizationBundle: localizationBundle
            )
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
            let canPerformAction = allowsInteractiveCheck
                && !status.isChecking
                && status.nextManualCheckAt == nil
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
        case let .failed(message, releasesURL, _):
            let canPerformAction = allowsInteractiveCheck
                && !status.isChecking
                && status.nextManualCheckAt == nil
            let actionTitle: String
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
            return AboutUpdatePresentation(
                isVisible: true,
                symbolName: "exclamationmark.triangle.fill",
                tint: .orange,
                title: L10n.text(
                    "about.update_check_failed",
                    defaultValue: "Update check failed",
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
                    action: .checkAgain
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
        case .sparkleUpdateAvailable, .sparkleDownloading, .sparkleExtracting,
             .sparkleReadyToInstall, .sparkleInstalling, .sparkleFailed:
            preconditionFailure("Expected a common update phase")
        }
    }

    private static func upToDateActionTitle(
        status: UpdateStatus,
        localizationBundle: Bundle?
    ) -> String {
        switch status.manualCheckFeedback {
        case .checking:
            return L10n.text(
                "about.update_checking",
                defaultValue: "Checking…",
                bundle: localizationBundle
            )
        case .completed where status.nextManualCheckAt != nil:
            return L10n.text(
                "about.update_checked_recently",
                defaultValue: "Checked just now",
                bundle: localizationBundle
            )
        case .none where status.nextManualCheckAt != nil:
            return L10n.text(
                "about.update_check_again_later",
                defaultValue: "Check Again Later",
                bundle: localizationBundle
            )
        case .none, .completed:
            return L10n.text(
                "about.update_check_again",
                defaultValue: "Check Again",
                bundle: localizationBundle
            )
        }
    }

    static func retryToolTip(
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
