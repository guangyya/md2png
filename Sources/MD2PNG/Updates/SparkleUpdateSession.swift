import Foundation

@MainActor
final class SparkleUpdateSession: UpdateSession {
    private typealias Configuration = (
        repository: GitHubRepository,
        installedVersion: String
    )

    private let updateDriver: UpdateDriving
    private let checkPolicy: UpdateCheckPolicy
    private let channel: () -> UpdateChannel
    private let installedVersion: () -> String?
    private let openWebPage: (URL) -> Bool
    private let now: () -> Date
    private let beforeInstallAndRelaunch: @MainActor (SeamlessUpdate) -> Bool
    private let onInstallAccepted: @MainActor () -> Void
    private let onInstallEndedWithoutRelaunch: @MainActor () -> Void
    private let relaunchMarker: UpdateRelaunchMarker
    private var cooldownTask: Task<Void, Never>?
    private var installRequestAccepted = false
    private var isDeferringPreparedInstallation = false
    private var deferredInstallationTerminationCompletion: (@MainActor () -> Void)?

    var onStatusChange: (@MainActor (UpdateStatus) -> Void)?
    private(set) var status = UpdateStatus() {
        didSet { onStatusChange?(status) }
    }

    var isUpdating: Bool {
        status.isChecking || status.phase.isDownloadActive
    }

    init(
        updateDriver: UpdateDriving,
        channel: @escaping () -> UpdateChannel,
        installedVersion: @escaping () -> String?,
        openWebPage: @escaping (URL) -> Bool,
        defaults: UserDefaults,
        now: @escaping () -> Date,
        manualCheckCooldown: TimeInterval,
        beforeInstallAndRelaunch: @escaping @MainActor (SeamlessUpdate) -> Bool,
        onInstallAccepted: @escaping @MainActor () -> Void,
        onInstallEndedWithoutRelaunch: @escaping @MainActor () -> Void
    ) {
        self.updateDriver = updateDriver
        self.channel = channel
        self.installedVersion = installedVersion
        self.openWebPage = openWebPage
        self.now = now
        self.beforeInstallAndRelaunch = beforeInstallAndRelaunch
        self.onInstallAccepted = onInstallAccepted
        self.onInstallEndedWithoutRelaunch = onInstallEndedWithoutRelaunch
        relaunchMarker = UpdateRelaunchMarker(defaults: defaults)
        checkPolicy = UpdateCheckPolicy(
            defaults: defaults,
            manualCheckCooldown: manualCheckCooldown
        )
        updateDriver.setEventHandler { [weak self] event in
            self?.handleUpdateDriverEvent(event)
        }
    }

    deinit {
        cooldownTask?.cancel()
    }

    func checkAgain() {
        guard !status.isChecking, !status.phase.isDownloadActive else { return }
        guard let configuration = configurationOrShowFailure() else { return }
        let currentDate = now()
        guard checkPolicy.canMakeRequest(at: currentDate) else {
            let retryAt = checkPolicy.nextAllowedRequestDate()
            if case .unknown = status.phase {
                showRateLimitFailure(
                    repository: configuration.repository,
                    retryAt: retryAt
                )
            } else {
                publishManualCheckAvailability(at: currentDate)
            }
            return
        }
        beginProbe(
            repository: configuration.repository,
            installedVersion: configuration.installedVersion,
            at: currentDate
        )
    }

    func downloadAvailableUpdate() {
        guard let update = status.phase.seamlessUpdate else { return }
        switch status.phase {
        case .sparkleUpdateAvailable, .sparkleFailed:
            break
        default:
            return
        }
        status.phase = .sparkleDownloading(update, progressPercent: 0)
        updateDriver.downloadUpdate(expectedBuildVersion: update.buildVersion)
    }

    func cancelUpdate() {
        guard case .sparkleDownloading = status.phase else { return }
        updateDriver.cancelDownload()
    }

    func installAndRelaunch() {
        guard case let .sparkleReadyToInstall(update) = status.phase,
              !isDeferringPreparedInstallation,
              beforeInstallAndRelaunch(update) else {
            return
        }
        guard updateDriver.installAndRelaunch() else { return }
        relaunchMarker.mark(expectedVersion: update.displayVersion, at: now())
        installRequestAccepted = true
        onInstallAccepted()
    }

    func installLater() {
        guard case .sparkleReadyToInstall = status.phase,
              !isDeferringPreparedInstallation else {
            return
        }
        _ = beginDeferringPreparedInstallation()
    }

    func cancelPreparedInstallationForApplicationTermination(
        completion: @escaping @MainActor () -> Void
    ) -> Bool {
        guard !installRequestAccepted else { return false }
        if isDeferringPreparedInstallation {
            deferredInstallationTerminationCompletion = completion
            return true
        }
        switch status.phase {
        case .sparkleExtracting, .sparkleReadyToInstall:
            break
        default:
            return false
        }
        return beginDeferringPreparedInstallation(
            terminationCompletion: completion
        )
    }

    func viewFullReleaseNotes() {
        guard let url = status.phase.seamlessUpdate?.fullReleaseNotesURL else {
            viewReleasesFallback()
            return
        }
        _ = openWebPage(url)
    }

    func viewReleasesFallback() {
        guard let releasesURL = channel().repository?.releasesURL else { return }
        _ = openWebPage(releasesURL)
    }

#if DEBUG
    func setStatusForTesting(_ status: UpdateStatus) {
        self.status = status
    }
#endif

    private func beginProbe(
        repository: GitHubRepository,
        installedVersion: String,
        at requestDate: Date
    ) {
        checkPolicy.recordAttempt(at: requestDate)
        var checkingStatus = status
        checkingStatus.isChecking = true
        checkingStatus.manualCheckFeedback = .checking
        status = checkingStatus
        publishManualCheckAvailability(at: requestDate)

        updateDriver.probe(installedVersion: installedVersion) { [weak self] result in
            self?.finishProbe(
                result,
                repository: repository,
                installedVersion: installedVersion
            )
        }
    }

    private func finishProbe(
        _ result: UpdateProbeResult,
        repository: GitHubRepository,
        installedVersion: String
    ) {
        let phase: UpdatePhase
        switch result {
        case let .updateAvailable(update):
            phase = .sparkleUpdateAvailable(update)
        case let .noUpdate(reason, latestDisplayVersion):
            phase = phaseForNoUpdate(
                reason: reason,
                latestDisplayVersion: latestDisplayVersion,
                installedVersion: installedVersion,
                repository: repository
            )
        case let .failed(message):
            phase = .failed(
                message: message,
                releasesURL: repository.releasesURL,
                retryAt: nil
            )
        }
        finishCheck(with: phase)
    }

    private func handleUpdateDriverEvent(_ event: UpdateDriverEvent) {
        let currentUpdate = status.phase.seamlessUpdate
        switch event {
        case let .updateChanged(update):
            finishAcceptedInstallWithoutRelaunch()
            status.phase = .sparkleUpdateAvailable(update)
        case let .downloading(received, expected):
            guard let update = currentUpdate else { return }
            let progressPercent = expected.flatMap { expected -> Int? in
                guard expected > 0 else { return nil }
                return min(max(Int((Double(received) / Double(expected)) * 100), 0), 100)
            }
            status.phase = .sparkleDownloading(update, progressPercent: progressPercent)
        case let .extracting(progress):
            guard let update = currentUpdate else { return }
            let progressPercent = min(max(Int(progress * 100), 0), 100)
            status.phase = .sparkleExtracting(update, progressPercent: progressPercent)
        case .readyToInstall:
            guard let update = currentUpdate else { return }
            status.phase = .sparkleReadyToInstall(update)
        case .installing:
            guard let update = currentUpdate else { return }
            status.phase = .sparkleInstalling(update)
        case .cancelled:
            guard let update = currentUpdate else { return }
            status.phase = .sparkleUpdateAvailable(update)
        case let .failed(message):
            finishAcceptedInstallWithoutRelaunch()
            status.phase = .sparkleFailed(message: message, update: currentUpdate)
        }
    }

    private func finishAcceptedInstallWithoutRelaunch() {
        guard installRequestAccepted else { return }
        installRequestAccepted = false
        relaunchMarker.clearPendingResult()
        onInstallEndedWithoutRelaunch()
    }

    private func beginDeferringPreparedInstallation(
        terminationCompletion: (@MainActor () -> Void)? = nil
    ) -> Bool {
        isDeferringPreparedInstallation = true
        deferredInstallationTerminationCompletion = terminationCompletion
        let didBegin = updateDriver.deferInstallation { [weak self] in
            guard let self else { return }
            self.isDeferringPreparedInstallation = false
            let completion = self.deferredInstallationTerminationCompletion
            self.deferredInstallationTerminationCompletion = nil
            completion?()
        }
        if !didBegin {
            isDeferringPreparedInstallation = false
            deferredInstallationTerminationCompletion = nil
        }
        return didBegin
    }

    private func phaseForNoUpdate(
        reason: UpdateProbeNoUpdateReason,
        latestDisplayVersion: String?,
        installedVersion: String,
        repository: GitHubRepository
    ) -> UpdatePhase {
        switch reason {
        case .onLatestVersion:
            guard let version = SemanticVersion(installedVersion) else {
                return .failed(
                    message: UpdateError.invalidInstalledVersion.localizedDescription,
                    releasesURL: repository.releasesURL,
                    retryAt: nil
                )
            }
            return .upToDate(version: version)
        case .onNewerThanLatestVersion:
            return .runningNewerVersion(
                version: latestDisplayVersion ?? installedVersion
            )
        case .systemIsTooOld:
            return incompatibleUpdatePhase(
                message: L10n.text(
                    "about.update_requires_newer_macos",
                    defaultValue: "The latest update requires a newer version of macOS."
                ),
                repository: repository
            )
        case .systemIsTooNew:
            return incompatibleUpdatePhase(
                message: L10n.text(
                    "about.update_requires_older_macos",
                    defaultValue: "The latest update does not support this version of macOS."
                ),
                repository: repository
            )
        case .hardwareDoesNotSupportARM64:
            return incompatibleUpdatePhase(
                message: L10n.text(
                    "about.update_requires_apple_silicon",
                    defaultValue: "The latest update requires an Apple silicon Mac."
                ),
                repository: repository
            )
        case .unknown:
            return incompatibleUpdatePhase(
                message: L10n.text(
                    "about.update_no_compatible_release",
                    defaultValue: "No compatible update was found."
                ),
                repository: repository
            )
        }
    }

    private func incompatibleUpdatePhase(
        message: String,
        repository: GitHubRepository
    ) -> UpdatePhase {
        .failed(
            message: message,
            releasesURL: repository.releasesURL,
            retryAt: nil
        )
    }

    private func configurationOrShowFailure() -> Configuration? {
        guard let repository = channel().repository else { return nil }
        guard let installedVersion = installedVersion() else {
            updateStatus(phase: .failed(
                message: UpdateError.invalidInstalledVersion.localizedDescription,
                releasesURL: repository.releasesURL,
                retryAt: nil
            ))
            return nil
        }
        return (repository, installedVersion)
    }

    private func finishCheck(with phase: UpdatePhase) {
        let completedManualCheck = status.manualCheckFeedback == .checking
        var completedStatus = status
        completedStatus.phase = phase
        completedStatus.isChecking = false
        completedStatus.manualCheckFeedback = completedManualCheck ? .completed : .none
        status = completedStatus
        publishManualCheckAvailability(at: now())
    }

    private func updateStatus(phase: UpdatePhase) {
        status.phase = phase
        status.isChecking = false
        publishManualCheckAvailability(at: now())
    }

    private func showRateLimitFailure(
        repository: GitHubRepository,
        retryAt: Date?
    ) {
        let retryDate = retryAt ?? checkPolicy.localRetryDate(after: now())
        updateStatus(phase: .failed(
            message: UpdateError.rateLimited(retryAt: retryDate).localizedDescription,
            releasesURL: repository.releasesURL,
            retryAt: retryDate
        ))
    }

    private func publishManualCheckAvailability(at date: Date) {
        let nextAllowed = checkPolicy.nextAllowedRequestDate()
        status.nextManualCheckAt = nextAllowed.flatMap { $0 > date ? $0 : nil }
        scheduleManualCheckAvailabilityRefresh()
    }

    private func scheduleManualCheckAvailabilityRefresh() {
        cooldownTask?.cancel()
        guard let nextManualCheckAt = status.nextManualCheckAt else {
            cooldownTask = nil
            return
        }
        let delay = max(nextManualCheckAt.timeIntervalSince(now()), 0)
        cooldownTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self else { return }
                var refreshedStatus = self.status
                refreshedStatus.nextManualCheckAt = nil
                if refreshedStatus.manualCheckFeedback == .completed {
                    refreshedStatus.manualCheckFeedback = .none
                }
                self.status = refreshedStatus
                self.cooldownTask = nil
            } catch {}
        }
    }
}
