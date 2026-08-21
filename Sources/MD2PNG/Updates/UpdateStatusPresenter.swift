import Foundation

struct UpdateStatusPresentation {
    static func statusItem(
        renderState: RenderCoordinatorState?,
        updateStatus: UpdateStatus
    ) -> StatusItemPresentation {
        if renderState?.isRendering == true {
            return StatusItemPresentation(
                symbolName: "hourglass",
                accessibilityLabel: L10n.text(
                    "accessibility.rendering",
                    defaultValue: "Rendering"
                )
            )
        }
        if renderState?.isUpdateInstallPending == true {
            return StatusItemPresentation(
                symbolName: "arrow.triangle.2.circlepath",
                accessibilityLabel: L10n.text(
                    "update.install_pending_accessibility",
                    defaultValue: "md2png — update installation is starting"
                )
            )
        }

        let symbolName: String? = switch updateStatus.phase {
        case .sparkleDownloading:
            "arrow.down.circle"
        case .sparkleExtracting:
            "checkmark.shield"
        case .sparkleInstalling:
            "arrow.triangle.2.circlepath"
        case .unknown, .upToDate, .runningNewerVersion,
             .sparkleUpdateAvailable, .sparkleReadyToInstall, .sparkleFailed,
             .failed:
            nil
        }
        return StatusItemPresentation(
            symbolName: symbolName,
            accessibilityLabel: symbolName == nil
                ? L10n.text("accessibility.app", defaultValue: "md2png")
                : L10n.format(
                    "accessibility.update_status",
                    defaultValue: "md2png — %@",
                    accessibilityStatus(for: updateStatus.phase)
                )
        )
    }

    static func accessibilityStatus(for phase: UpdatePhase) -> String {
        switch phase {
        case let .sparkleDownloading(update, progressPercent):
            if let progressPercent {
                return L10n.format(
                    "about.update_downloading_progress",
                    defaultValue: "Downloading md2png %1$@ — %2$ld%%",
                    update.displayVersion,
                    progressPercent
                )
            }
            return L10n.format(
                "about.update_downloading_version",
                defaultValue: "Downloading md2png %@…",
                update.displayVersion
            )
        case let .sparkleExtracting(update, progressPercent):
            if let progressPercent {
                return L10n.format(
                    "about.update_preparing_progress",
                    defaultValue: "Preparing md2png %1$@ — %2$ld%%",
                    update.displayVersion,
                    progressPercent
                )
            }
            return L10n.format(
                "about.update_preparing_version",
                defaultValue: "Preparing md2png %@…",
                update.displayVersion
            )
        case let .sparkleInstalling(update):
            return L10n.format(
                "about.update_installing_version",
                defaultValue: "Installing md2png %@…",
                update.displayVersion
            )
        case .unknown, .upToDate, .runningNewerVersion,
             .sparkleUpdateAvailable, .sparkleReadyToInstall, .sparkleFailed,
             .failed:
            return L10n.text("accessibility.app", defaultValue: "md2png")
        }
    }
}

@MainActor
final class UpdateStatusPresenter {
    typealias ShowHUD = (_ message: String, _ symbol: String, _ style: HUDStyle) -> Void

    private let showHUD: ShowHUD
    private let applyStatusItem: (StatusItemPresentation) -> Void
    private let isAboutVisible: () -> Bool
    private let announce: (String) -> Void
    private let runningVersion: () -> String
    private let relaunchMarker: UpdateRelaunchMarker
    private var renderState: RenderCoordinatorState?
    private var updateStatus = UpdateStatus()

    init(
        showHUD: @escaping ShowHUD,
        applyStatusItem: @escaping (StatusItemPresentation) -> Void,
        isAboutVisible: @escaping () -> Bool,
        announce: @escaping (String) -> Void,
        runningVersion: @escaping () -> String = {
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? ""
        },
        relaunchMarker: UpdateRelaunchMarker = UpdateRelaunchMarker()
    ) {
        self.showHUD = showHUD
        self.applyStatusItem = applyStatusItem
        self.isAboutVisible = isAboutVisible
        self.announce = announce
        self.runningVersion = runningVersion
        self.relaunchMarker = relaunchMarker
    }

    func apply(_ renderState: RenderCoordinatorState) {
        self.renderState = renderState
        applyCurrentStatusItem()
    }

    func apply(_ status: UpdateStatus) {
        let previousPhase = updateStatus.phase
        updateStatus = status
        applyCurrentStatusItem()
        guard previousPhase != status.phase else { return }
        presentTransition(from: previousPhase, to: status.phase)
    }

    func presentRelaunchResultIfNeeded() {
        guard let result = relaunchMarker.reconcile(
            runningVersion: runningVersion()
        ) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch result {
            case let .updated(version):
                self.showHUD(
                    L10n.format(
                        "update.updated_to_version",
                        defaultValue: "Updated to version %@",
                        version
                    ),
                    "checkmark.circle.fill",
                    .informational
                )
            case let .notUpdated(expectedVersion, runningVersion):
                self.showHUD(
                    L10n.format(
                        "update.relaunch_not_updated",
                        defaultValue: "Update to %1$@ did not complete — still running %2$@. Open About md2png to retry.",
                        expectedVersion,
                        runningVersion
                    ),
                    "exclamationmark.triangle.fill",
                    .error
                )
            }
        }
    }

    private func applyCurrentStatusItem() {
        applyStatusItem(UpdateStatusPresentation.statusItem(
            renderState: renderState,
            updateStatus: updateStatus
        ))
    }

    private func presentTransition(
        from previousPhase: UpdatePhase,
        to phase: UpdatePhase
    ) {
        switch phase {
        case .unknown:
            break
        case let .upToDate(version):
            announce(L10n.format(
                "update.accessibility.up_to_date",
                defaultValue: "md2png %@ is up to date.",
                version.description
            ))
        case .runningNewerVersion:
            announce(L10n.text(
                "update.accessibility.running_newer",
                defaultValue: "This md2png build is newer than the latest published version."
            ))
        case let .sparkleUpdateAvailable(update):
            announce(L10n.format(
                "update.accessibility.available",
                defaultValue: "md2png %@ is available.",
                update.displayVersion
            ))
        case let .sparkleDownloading(update, _):
            if case .sparkleDownloading = previousPhase { return }
            announce(L10n.format(
                "update.accessibility.downloading",
                defaultValue: "Downloading md2png %@.",
                update.displayVersion
            ))
        case let .sparkleExtracting(update, _):
            if case .sparkleExtracting = previousPhase { return }
            announce(L10n.format(
                "update.accessibility.preparing",
                defaultValue: "Preparing md2png %@ for installation.",
                update.displayVersion
            ))
        case let .sparkleReadyToInstall(update):
            let message = L10n.format(
                "update.accessibility.ready_to_relaunch",
                defaultValue: "md2png %@ is ready to install and relaunch.",
                update.displayVersion
            )
            if !isAboutVisible() {
                showHUD(message, "arrow.down.app.fill", .informational)
            }
            announce(message)
        case let .sparkleInstalling(update):
            announce(L10n.format(
                "update.accessibility.installing",
                defaultValue: "Installing md2png %@ and relaunching.",
                update.displayVersion
            ))
        case let .sparkleFailed(message, _):
            if previousPhase.isDownloadActive, !isAboutVisible() {
                showHUD(
                    L10n.format(
                        "update.hud.failed",
                        defaultValue: "%@ Open About md2png to retry.",
                        message
                    ),
                    "exclamationmark.triangle.fill",
                    .error
                )
            }
            announce(message)
        case let .failed(message, _, _):
            if previousPhase.isDownloadActive, !isAboutVisible() {
                showHUD(
                    L10n.format(
                        "update.hud.failed",
                        defaultValue: "%@ Open About md2png to retry.",
                        message
                    ),
                    "exclamationmark.triangle.fill",
                    .error
                )
            }
            announce(message)
        }
    }
}
