import AppKit

@MainActor
final class LegacyUpdateSession: UpdateSession {
    private typealias Configuration = (
        repository: GitHubRepository,
        installedVersion: String
    )

    private let service: UpdateService
    private let checkPolicy: UpdateCheckPolicy
    private let channel: () -> UpdateChannel
    private let installedVersion: () -> String?
    private let openFile: (URL) -> Bool
    private let revealFile: (URL) -> Void
    private let openWebPage: (URL) -> Bool
    private let now: () -> Date
    private var checkTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var cooldownTask: Task<Void, Never>?

    var onStatusChange: (@MainActor (UpdateStatus) -> Void)?
    private(set) var status = UpdateStatus() {
        didSet { onStatusChange?(status) }
    }

    var isUpdating: Bool {
        status.isChecking
            || status.phase.isDownloadActive
            || checkTask != nil
            || downloadTask != nil
    }

    init(
        service: UpdateService,
        channel: @escaping () -> UpdateChannel,
        installedVersion: @escaping () -> String?,
        openFile: @escaping (URL) -> Bool,
        revealFile: @escaping (URL) -> Void,
        openWebPage: @escaping (URL) -> Bool,
        defaults: UserDefaults,
        now: @escaping () -> Date,
        automaticCheckInterval: TimeInterval,
        manualCheckCooldown: TimeInterval
    ) {
        self.service = service
        self.channel = channel
        self.installedVersion = installedVersion
        self.openFile = openFile
        self.revealFile = revealFile
        self.openWebPage = openWebPage
        self.now = now
        checkPolicy = UpdateCheckPolicy(
            defaults: defaults,
            automaticCheckInterval: automaticCheckInterval,
            manualCheckCooldown: manualCheckCooldown
        )
    }

    deinit {
        checkTask?.cancel()
        downloadTask?.cancel()
        cooldownTask?.cancel()
    }

    func refreshIfNeeded() {
        if case .readyToInstall = status.phase { return }
        guard checkTask == nil,
              downloadTask == nil,
              !status.phase.isDownloadActive,
              let configuration = configurationOrShowFailure() else {
            return
        }

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
        if let cachedRecord,
           cachedPhase != nil,
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

    func checkAgain() {
        guard checkTask == nil,
              downloadTask == nil,
              !status.phase.isDownloadActive,
              let configuration = configurationOrShowFailure() else {
            return
        }
        let currentDate = now()
        guard checkPolicy.canMakeRequest(at: currentDate) else {
            let retryAt = checkPolicy.nextAllowedRequestDate(at: currentDate)
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
        beginCheck(
            repository: configuration.repository,
            installedVersion: configuration.installedVersion,
            preservesExistingResultOnFailure: false,
            isManual: true
        )
    }

    func downloadAvailableUpdate() {
        guard checkTask == nil,
              downloadTask == nil,
              let update = status.phase.availableUpdate,
              channel().allowsDownload(update) else {
            return
        }
        status.phase = .downloading(update, progressPercent: 0)
        downloadTask = Task { [weak self] in
            guard let self else { return }
            await downloadAndOpen(update)
        }
    }

    func cancelUpdate() {
        downloadTask?.cancel()
    }

    func openDownloadedUpdate() {
        guard checkTask == nil,
              downloadTask == nil,
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
        guard checkTask == nil,
              downloadTask == nil,
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

    func refreshManualCheckAvailability() {
        publishManualCheckAvailability(at: now())
    }

#if DEBUG
    func setStatusForTesting(_ status: UpdateStatus) {
        self.status = status
    }
#endif

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
        channel().repository?.releasesURL
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
            finishDownload(with: .readyToInstall(
                update: update,
                fileURL: downloadedURL
            ))
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

    private func applyDownloadEvent(
        _ event: UpdateDownloadEvent,
        update: AvailableUpdate
    ) {
        switch event {
        case let .progress(received, expected):
            guard expected > 0,
                  case let .downloading(currentUpdate, _) = status.phase,
                  currentUpdate == update else {
                return
            }
            let percent = min(
                max(Int((Double(received) / Double(expected)) * 100), 0),
                100
            )
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

    private func showRateLimitFailure(
        repository: GitHubRepository,
        retryAt: Date?
    ) {
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
