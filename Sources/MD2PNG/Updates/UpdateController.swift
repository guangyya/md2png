import AppKit

enum UpdatePhase: Equatable, Sendable {
    case unknown
    case upToDate(version: SemanticVersion)
    case runningNewerVersion(version: String)
    case sparkleUpdateAvailable(SeamlessUpdate)
    case sparkleDownloading(SeamlessUpdate, progressPercent: Int?)
    case sparkleExtracting(SeamlessUpdate, progressPercent: Int?)
    case sparkleReadyToInstall(SeamlessUpdate)
    case sparkleInstalling(SeamlessUpdate)
    case sparkleFailed(message: String, update: SeamlessUpdate?)
    case updateAvailable(AvailableUpdate)
    case downloading(AvailableUpdate, progressPercent: Int)
    case verifying(AvailableUpdate)
    case opening(AvailableUpdate)
    case readyToInstall(update: AvailableUpdate, fileURL: URL)
    case failed(
        message: String,
        releasesURL: URL?,
        retryAt: Date?,
        availableUpdate: AvailableUpdate?
    )

    var isDownloadActive: Bool {
        switch self {
        case .sparkleDownloading, .sparkleExtracting,
             .downloading, .verifying, .opening:
            return true
        case .unknown, .upToDate, .runningNewerVersion,
             .sparkleUpdateAvailable, .sparkleReadyToInstall, .sparkleInstalling,
             .sparkleFailed, .updateAvailable, .readyToInstall, .failed:
            return false
        }
    }

    var seamlessUpdate: SeamlessUpdate? {
        switch self {
        case let .sparkleUpdateAvailable(update),
             let .sparkleDownloading(update, _),
             let .sparkleExtracting(update, _),
             let .sparkleReadyToInstall(update),
             let .sparkleInstalling(update):
            return update
        case let .sparkleFailed(_, update):
            return update
        case .unknown, .upToDate, .runningNewerVersion,
             .updateAvailable, .downloading, .verifying, .opening,
             .readyToInstall, .failed:
            return nil
        }
    }

    var availableUpdate: AvailableUpdate? {
        switch self {
        case let .updateAvailable(update),
             let .downloading(update, _),
             let .verifying(update),
             let .opening(update),
             let .readyToInstall(update, _):
            return update
        case let .failed(_, _, _, update):
            return update
        case .unknown, .upToDate, .runningNewerVersion,
             .sparkleUpdateAvailable, .sparkleDownloading, .sparkleExtracting,
             .sparkleReadyToInstall, .sparkleInstalling, .sparkleFailed:
            return nil
        }
    }
}

struct UpdateStatus: Equatable, Sendable {
    var phase: UpdatePhase = .unknown
    var isChecking = false
    var nextManualCheckAt: Date?
    var manualCheckFeedback: ManualCheckFeedback = .none
}

enum ManualCheckFeedback: Equatable, Sendable {
    case none
    case checking
    case completed
}

#if DEBUG
enum DebugUpdateMockState: String {
    case upToDate = "up-to-date"
    case checkFailed = "check-failed"
    case downloadFailed = "download-failed"
    case readyToInstall = "ready-to-install"
    case seamlessUpdateAvailable = "seamless-update-available"
    case seamlessReadyToInstall = "seamless-ready-to-install"

    private static let fixtureVersion = SemanticVersion("0.1.0")!
    private static let fixtureAssetName = "md2png-debug-update-fixture.dmg"
    private static let fixtureAssetSize: Int64 = 3
    private static let fixtureAssetSHA256 =
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    func status(
        installedVersion: String?,
        repository: GitHubRepository?,
        updatesDirectory: URL? = nil
    ) -> UpdateStatus? {
        switch self {
        case .upToDate:
            guard let version = installedVersion.flatMap(SemanticVersion.init) else {
                return nil
            }
            return UpdateStatus(phase: .upToDate(version: version))
        case .checkFailed:
            return UpdateStatus(phase: .failed(
                message: UpdateError.networkUnavailable.localizedDescription,
                releasesURL: repository?.releasesURL,
                retryAt: nil,
                availableUpdate: nil
            ))
        case .downloadFailed:
            guard let update = fixtureUpdate() else { return nil }
            return UpdateStatus(phase: .failed(
                message: UpdateError.digestMismatch.localizedDescription,
                releasesURL: repository?.releasesURL,
                retryAt: nil,
                availableUpdate: update
            ))
        case .readyToInstall:
            guard let update = fixtureUpdate(),
                  let directory = updatesDirectory ?? FileManager.default.urls(
                    for: .cachesDirectory,
                    in: .userDomainMask
                  ).first?
                    .appendingPathComponent("io.github.guangyya.md2png", isDirectory: true)
                    .appendingPathComponent("Updates", isDirectory: true) else {
                return nil
            }
            let fileURL = directory.appendingPathComponent(update.assetName)
            if (try? UpdateArtifactVerifier().verifyFile(at: fileURL, update: update)) != nil {
                return UpdateStatus(phase: .readyToInstall(update: update, fileURL: fileURL))
            }
            return UpdateStatus(phase: .failed(
                message: UpdateError.revealFailed.localizedDescription,
                releasesURL: repository?.releasesURL,
                retryAt: nil,
                availableUpdate: update
            ))
        case .seamlessUpdateAvailable:
            return UpdateStatus(phase: .sparkleUpdateAvailable(
                fixtureSeamlessUpdate(
                    installedVersion: installedVersion,
                    releasesURL: repository?.releasesURL
                )
            ))
        case .seamlessReadyToInstall:
            return UpdateStatus(phase: .sparkleReadyToInstall(
                fixtureSeamlessUpdate(
                    installedVersion: installedVersion,
                    releasesURL: repository?.releasesURL
                )
            ))
        }
    }

    private func fixtureSeamlessUpdate(
        installedVersion: String?,
        releasesURL: URL?
    ) -> SeamlessUpdate {
        let targetVersion = "0.8.0"
        return SeamlessUpdate(
            installedVersion: installedVersion ?? "0.7.0",
            displayVersion: targetVersion,
            buildVersion: "8",
            publishedAt: Date(timeIntervalSince1970: 1_787_000_000),
            contentLength: 4_200_000,
            releaseNotes: [
                SeamlessUpdateReleaseNotes(
                    version: targetVersion,
                    publishedAt: Date(timeIntervalSince1970: 1_787_000_000),
                    text: "Added\n- Preview signed release notes in About.\n- Install and relaunch without opening a DMG."
                )
            ],
            historyIsTruncated: false,
            fullReleaseNotesURL: releasesURL
        )
    }

    private func fixtureUpdate() -> AvailableUpdate? {
        guard let downloadURL = URL(
            string: "https://updates.invalid/\(Self.fixtureAssetName)"
        ) else {
            return nil
        }
        return AvailableUpdate(
            version: Self.fixtureVersion,
            tagName: "debug-fixture",
            assetName: Self.fixtureAssetName,
            downloadURL: downloadURL,
            size: Self.fixtureAssetSize,
            sha256: Self.fixtureAssetSHA256
        )
    }
}
#endif

@MainActor
final class UpdateController {
    typealias StatusObserver = @MainActor (UpdateStatus) -> Void

    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60
    static let manualCheckCooldown: TimeInterval = 60

    private let service: UpdateService
    private let updateDriver: UpdateDriving?
    private let checkPolicy: UpdateCheckPolicy
    private let channel: () -> UpdateChannel
    private let installedVersion: () -> String?
    private let openFile: (URL) -> Bool
    private let revealFile: (URL) -> Void
    private let openWebPage: (URL) -> Bool
    private let now: () -> Date
    private let beforeInstallAndRelaunch: @MainActor (SeamlessUpdate) -> Bool
    private let onInstallAccepted: @MainActor () -> Void
    private let onInstallEndedWithoutRelaunch: @MainActor () -> Void
    private let relaunchMarker: UpdateRelaunchMarker
    private var checkTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var cooldownTask: Task<Void, Never>?
    private var installRequestAccepted = false
    private var isDeferringPreparedInstallation = false
    private var deferredInstallationTerminationCompletion: (@MainActor () -> Void)?
    private var statusObservers: [UUID: StatusObserver] = [:]
#if DEBUG
    private var usesTestingStatusOverride = false
    private var usesPackagedTestingStatusOverride = false
#endif

    private(set) var status = UpdateStatus() {
        didSet {
            for observer in statusObservers.values {
                observer(status)
            }
        }
    }

    var isUpdating: Bool {
        status.isChecking
            || status.phase.isDownloadActive
            || checkTask != nil
            || downloadTask != nil
    }

    var allowsUpdatePresentation: Bool {
#if DEBUG
        if usesTestingStatusOverride {
            return true
        }
#endif
        return channel().allowsUpdateChecks
    }

    var allowsInteractiveCheck: Bool {
#if DEBUG
        if usesTestingStatusOverride {
            return false
        }
#endif
        return channel().allowsUpdateChecks
    }

    func canDownload(_ update: AvailableUpdate) -> Bool {
        channel().allowsDownload(update)
    }

    init(
        service: UpdateService = UpdateService(),
        channel: @escaping () -> UpdateChannel = { .current() },
        installedVersion: @escaping () -> String? = {
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        },
        openFile: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        revealFile: @escaping (URL) -> Void = {
            NSWorkspace.shared.activateFileViewerSelecting([$0])
        },
        openWebPage: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        automaticCheckInterval: TimeInterval = UpdateController.automaticCheckInterval,
        manualCheckCooldown: TimeInterval = UpdateController.manualCheckCooldown,
        updateDriver: UpdateDriving? = nil,
        beforeInstallAndRelaunch: @escaping @MainActor (SeamlessUpdate) -> Bool = { _ in
            true
        },
        onInstallAccepted: @escaping @MainActor () -> Void = {},
        onInstallEndedWithoutRelaunch: @escaping @MainActor () -> Void = {}
    ) {
        self.service = service
        self.updateDriver = updateDriver
        self.channel = channel
        self.installedVersion = installedVersion
        self.openFile = openFile
        self.revealFile = revealFile
        self.openWebPage = openWebPage
        self.now = now
        self.beforeInstallAndRelaunch = beforeInstallAndRelaunch
        self.onInstallAccepted = onInstallAccepted
        self.onInstallEndedWithoutRelaunch = onInstallEndedWithoutRelaunch
        relaunchMarker = UpdateRelaunchMarker(defaults: defaults)
        checkPolicy = UpdateCheckPolicy(
            defaults: defaults,
            automaticCheckInterval: automaticCheckInterval,
            manualCheckCooldown: manualCheckCooldown
        )
#if DEBUG
        if let rawValue = Bundle.main.object(
            forInfoDictionaryKey: "MD2PNGTestUpdateState"
        ) as? String,
           let mockState = DebugUpdateMockState(rawValue: rawValue),
           let mockStatus = mockState.status(
            installedVersion: installedVersion(),
            repository: ProjectLinks.githubRepository
           ) {
            usesTestingStatusOverride = true
            usesPackagedTestingStatusOverride = true
            status = mockStatus
        }
#endif
        updateDriver?.setEventHandler { [weak self] event in
            self?.handleUpdateDriverEvent(event)
        }
    }

    deinit {
        checkTask?.cancel()
        downloadTask?.cancel()
        cooldownTask?.cancel()
    }

    @discardableResult
    func observeStatus(_ observer: @escaping StatusObserver) -> UUID {
        let id = UUID()
        statusObservers[id] = observer
        observer(status)
        return id
    }

    func removeStatusObserver(_ id: UUID) {
        statusObservers.removeValue(forKey: id)
    }

#if DEBUG
    func setStatusForTesting(_ newStatus: UpdateStatus) {
        usesTestingStatusOverride = true
        status = newStatus
    }
#endif

    /// Called when About is shown. A fresh cached result is used without making a request.
    func refreshIfNeeded() {
#if DEBUG
        if usesTestingStatusOverride {
            if usesPackagedTestingStatusOverride {
                publishManualCheckAvailability(at: now())
            }
            return
        }
#endif
        // Sparkle checks are intentionally user-initiated from About. The legacy
        // service path remains available only to isolated tests and debug fixtures.
        if updateDriver != nil { return }
        if case .readyToInstall = status.phase { return }
        guard checkTask == nil, downloadTask == nil, !status.phase.isDownloadActive else { return }
        guard let configuration = configurationOrShowFailure() else { return }

        let cachedRecord = checkPolicy.cachedRelease(for: configuration.repository)
        let cachedPhase = cachedRecord.flatMap {
            try? phase(
                for: $0.release,
                repository: configuration.repository,
                installedVersion: configuration.installedVersion
            )
        }
        if let cachedPhase {
            updateStatus(phase: cachedPhase)
        }

        let currentDate = now()
        if let cachedRecord, cachedPhase != nil,
           checkPolicy.isFresh(cachedRecord, at: currentDate) {
            publishManualCheckAvailability(at: currentDate)
            return
        }

        guard checkPolicy.canMakeRequest(at: currentDate) else {
            if cachedPhase == nil {
                showRateLimitFailure(
                    repository: configuration.repository,
                    retryAt: checkPolicy.nextAllowedRequestDate(at: currentDate)
                )
            } else {
                publishManualCheckAvailability(at: currentDate)
            }
            return
        }

        beginCheck(
            repository: configuration.repository,
            installedVersion: configuration.installedVersion,
            preservesExistingResultOnFailure: cachedPhase != nil,
            isManual: false
        )
    }

    /// Explicit checks bypass the 24-hour cache, but still respect the local and server cooldowns.
    func checkAgain() {
#if DEBUG
        guard !usesTestingStatusOverride else { return }
#endif
        guard checkTask == nil, downloadTask == nil,
              !status.phase.isDownloadActive else { return }
        guard let configuration = configurationOrShowFailure() else { return }
        let currentDate = now()
        guard checkPolicy.canMakeRequest(at: currentDate) else {
            let retryAt = checkPolicy.nextAllowedRequestDate(at: currentDate)
            if case .unknown = status.phase {
                showRateLimitFailure(repository: configuration.repository, retryAt: retryAt)
            } else {
                publishManualCheckAvailability(at: currentDate)
            }
            return
        }
        if updateDriver != nil {
            beginSparkleProbe(
                repository: configuration.repository,
                installedVersion: configuration.installedVersion,
                at: currentDate
            )
            return
        }
        beginCheck(
            repository: configuration.repository,
            installedVersion: configuration.installedVersion,
            preservesExistingResultOnFailure: false,
            isManual: true
        )
    }

    func downloadAvailableUpdate() {
        if let update = status.phase.seamlessUpdate,
           updateDriver != nil {
            switch status.phase {
            case .sparkleUpdateAvailable, .sparkleFailed:
                break
            default:
                return
            }
            status.phase = .sparkleDownloading(update, progressPercent: 0)
            updateDriver?.downloadUpdate(expectedBuildVersion: update.buildVersion)
            return
        }
        guard checkTask == nil, downloadTask == nil,
              let update = status.phase.availableUpdate,
              canDownload(update) else {
            return
        }
        status.phase = .downloading(update, progressPercent: 0)
        downloadTask = Task { [weak self] in
            guard let self else { return }
            await downloadAndOpen(update)
        }
    }

    func cancelUpdate() {
        if case .sparkleDownloading = status.phase {
            updateDriver?.cancelDownload()
            return
        }
        downloadTask?.cancel()
    }

    func installAndRelaunch() {
        guard case let .sparkleReadyToInstall(update) = status.phase,
              !isDeferringPreparedInstallation,
              beforeInstallAndRelaunch(update) else {
            return
        }
        guard updateDriver?.installAndRelaunch() == true else { return }
        relaunchMarker.mark(expectedVersion: update.displayVersion, at: now())
        installRequestAccepted = true
        onInstallAccepted()
    }

    func installLater() {
        guard case .sparkleReadyToInstall = status.phase,
              !isDeferringPreparedInstallation else { return }
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

    func openDownloadedUpdate() {
        guard checkTask == nil, downloadTask == nil,
              case let .readyToInstall(update, fileURL) = status.phase else {
            return
        }
        guard FileManager.default.fileExists(atPath: fileURL.path),
              openFile(fileURL) else {
            finishDownload(with: .failed(
                message: UpdateError.openFailed.localizedDescription,
                releasesURL: fallbackReleasesURL,
                retryAt: nil,
                availableUpdate: update
            ))
            return
        }
    }

    func revealDownloadedUpdate() {
        guard checkTask == nil, downloadTask == nil,
              case let .readyToInstall(update, fileURL) = status.phase else {
            return
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            finishDownload(with: .failed(
                message: UpdateError.revealFailed.localizedDescription,
                releasesURL: fallbackReleasesURL,
                retryAt: nil,
                availableUpdate: update
            ))
            return
        }
        revealFile(fileURL)
    }

    func viewReleasesFallback() {
        guard let releasesURL = fallbackReleasesURL else { return }
        _ = openWebPage(releasesURL)
    }

    private typealias Configuration = (repository: GitHubRepository, installedVersion: String)

    private func beginSparkleProbe(
        repository: GitHubRepository,
        installedVersion: String,
        at requestDate: Date
    ) {
        guard let updateDriver else { return }
        checkPolicy.recordAttempt(at: requestDate)
        var checkingStatus = status
        checkingStatus.isChecking = true
        checkingStatus.manualCheckFeedback = .checking
        status = checkingStatus
        publishManualCheckAvailability(at: requestDate)

        updateDriver.probe(installedVersion: installedVersion) { [weak self] result in
            self?.finishSparkleProbe(
                result,
                repository: repository,
                installedVersion: installedVersion
            )
        }
    }

    private func finishSparkleProbe(
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
                retryAt: nil,
                availableUpdate: nil
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
        let didBegin = updateDriver?.deferInstallation { [weak self] in
            guard let self else { return }
            self.isDeferringPreparedInstallation = false
            let completion = self.deferredInstallationTerminationCompletion
            self.deferredInstallationTerminationCompletion = nil
            completion?()
        } == true
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
                    retryAt: nil,
                    availableUpdate: nil
                )
            }
            return .upToDate(version: version)
        case .onNewerThanLatestVersion:
            return .runningNewerVersion(version: latestDisplayVersion ?? installedVersion)
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
            retryAt: nil,
            availableUpdate: nil
        )
    }

    private func configurationOrShowFailure() -> Configuration? {
        guard let repository = channel().repository else { return nil }
        guard let installedVersion = installedVersion() else {
            updateStatus(phase: .failed(
                message: UpdateError.invalidInstalledVersion.localizedDescription,
                releasesURL: repository.releasesURL,
                retryAt: nil,
                availableUpdate: nil
            ))
            return nil
        }
        return (repository, installedVersion)
    }

    private var fallbackReleasesURL: URL? {
        if let releasesURL = channel().repository?.releasesURL {
            return releasesURL
        }
#if DEBUG
        if usesPackagedTestingStatusOverride {
            return ProjectLinks.githubRepository?.releasesURL
        }
#endif
        return nil
    }

    private func beginCheck(
        repository: GitHubRepository,
        installedVersion: String,
        preservesExistingResultOnFailure: Bool,
        isManual: Bool
    ) {
        let requestDate = now()
        checkPolicy.recordAttempt(at: requestDate)
        var checkingStatus = status
        checkingStatus.isChecking = true
        checkingStatus.manualCheckFeedback = isManual ? .checking : .none
        status = checkingStatus
        publishManualCheckAvailability(at: requestDate)

        checkTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await service.checkForUpdate(
                    repository: repository,
                    installedVersion: installedVersion,
                    now: requestDate
                )
                try Task.checkCancellation()
                checkPolicy.cache(
                    release: response.release,
                    repository: repository,
                    checkedAt: now()
                )
                checkPolicy.applySuccessfulRateLimit(response.rateLimit, at: now())
                finishCheck(with: Self.phase(for: response.result))
            } catch is CancellationError {
                finishCheck(with: status.phase)
            } catch {
                let retryAt: Date?
                if case let UpdateError.rateLimited(serverRetryAt) = error {
                    checkPolicy.recordServerRetry(at: serverRetryAt)
                    retryAt = serverRetryAt
                } else {
                    retryAt = nil
                }

                if preservesExistingResultOnFailure {
                    finishCheck(with: status.phase)
                } else {
                    finishCheck(with: .failed(
                        message: error.localizedDescription,
                        releasesURL: repository.releasesURL,
                        retryAt: retryAt,
                        availableUpdate: nil
                    ))
                }
            }
        }
    }

    private func finishCheck(with phase: UpdatePhase) {
        let completedManualCheck = status.manualCheckFeedback == .checking
        checkTask = nil
        var completedStatus = status
        completedStatus.phase = phase
        completedStatus.isChecking = false
        completedStatus.manualCheckFeedback = completedManualCheck ? .completed : .none
        status = completedStatus
        publishManualCheckAvailability(at: now())
    }

    private func downloadAndOpen(_ update: AvailableUpdate) async {
        do {
            let downloadedURL = try await service.download(update) { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.applyDownloadEvent(event, update: update)
                }
            }
            try Task.checkCancellation()
            status.phase = .opening(update)
            guard openFile(downloadedURL) else {
                throw UpdateError.openFailed
            }
            finishDownload(with: .readyToInstall(update: update, fileURL: downloadedURL))
        } catch is CancellationError {
            finishDownload(with: .updateAvailable(update))
        } catch {
            finishDownload(with: .failed(
                message: error.localizedDescription,
                releasesURL: fallbackReleasesURL,
                retryAt: nil,
                availableUpdate: update
            ))
        }
    }

    private func applyDownloadEvent(_ event: UpdateDownloadEvent, update: AvailableUpdate) {
        switch event {
        case let .progress(received, expected):
            guard expected > 0,
                  case let .downloading(currentUpdate, _) = status.phase,
                  currentUpdate == update else {
                return
            }
            let percent = min(max(Int((Double(received) / Double(expected)) * 100), 0), 100)
            status.phase = .downloading(update, progressPercent: percent)
        case .verifying:
            guard case let .downloading(currentUpdate, _) = status.phase,
                  currentUpdate == update else {
                return
            }
            status.phase = .verifying(update)
        }
    }

    private func finishDownload(with phase: UpdatePhase) {
        downloadTask = nil
        status.phase = phase
    }

    private func phase(
        for release: UpdateRelease,
        repository: GitHubRepository,
        installedVersion: String
    ) throws -> UpdatePhase {
        Self.phase(for: try UpdateReleaseResolver.resolve(
            release: release,
            repository: repository,
            installedVersionString: installedVersion
        ))
    }

    private static func phase(for result: UpdateCheckResult) -> UpdatePhase {
        switch result {
        case let .upToDate(installed, latest):
            return .upToDate(version: max(installed, latest))
        case let .updateAvailable(update):
            return .updateAvailable(update)
        }
    }

    private func updateStatus(phase: UpdatePhase) {
        status.phase = phase
        status.isChecking = false
        publishManualCheckAvailability(at: now())
    }

    private func showRateLimitFailure(repository: GitHubRepository, retryAt: Date?) {
        let retryDate = retryAt ?? checkPolicy.localRetryDate(after: now())
        updateStatus(phase: .failed(
            message: UpdateError.rateLimited(retryAt: retryDate).localizedDescription,
            releasesURL: repository.releasesURL,
            retryAt: retryDate,
            availableUpdate: nil
        ))
    }

    private func publishManualCheckAvailability(at date: Date) {
        let nextAllowed = checkPolicy.nextAllowedRequestDate(at: date)
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
