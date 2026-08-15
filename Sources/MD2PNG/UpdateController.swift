import AppKit

enum UpdatePhase: Equatable, Sendable {
    case unknown
    case upToDate(version: SemanticVersion)
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
        case .downloading, .verifying, .opening:
            return true
        case .unknown, .upToDate, .updateAvailable, .readyToInstall, .failed:
            return false
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
        case .unknown, .upToDate:
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

    private static let publishedVersion = SemanticVersion("0.1.0")!
    private static let publishedAssetName = "md2png-0.1.0-macOS-arm64-developer-id.dmg"
    private static let publishedAssetSize: Int64 = 3_312_367
    private static let publishedAssetSHA256 =
        "40fc785583a7cfaf1e476ae8649d2eb4e8461b49680e9a0fddfc35075b79bed7"

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
            guard let repository, let update = publishedUpdate(repository: repository) else {
                return nil
            }
            return UpdateStatus(phase: .failed(
                message: UpdateError.digestMismatch.localizedDescription,
                releasesURL: repository.releasesURL,
                retryAt: nil,
                availableUpdate: update
            ))
        case .readyToInstall:
            guard let repository, let update = publishedUpdate(repository: repository),
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
                releasesURL: repository.releasesURL,
                retryAt: nil,
                availableUpdate: update
            ))
        }
    }

    private func publishedUpdate(repository: GitHubRepository) -> AvailableUpdate? {
        guard let downloadURL = URL(string:
            "https://github.com/\(repository.owner)/\(repository.name)/releases/download/v0.1.0/\(Self.publishedAssetName)"
        ) else {
            return nil
        }
        return AvailableUpdate(
            version: Self.publishedVersion,
            tagName: "v0.1.0",
            assetName: Self.publishedAssetName,
            downloadURL: downloadURL,
            size: Self.publishedAssetSize,
            sha256: Self.publishedAssetSHA256
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
    private let checkPolicy: UpdateCheckPolicy
    private let installedVersion: () -> String?
    private let repository: () -> GitHubRepository?
    private let openFile: (URL) -> Bool
    private let revealFile: (URL) -> Void
    private let openWebPage: (URL) -> Bool
    private let now: () -> Date
    private var checkTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var cooldownTask: Task<Void, Never>?
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

    var isUpdating: Bool { checkTask != nil || downloadTask != nil }

    init(
        service: UpdateService = UpdateService(),
        installedVersion: @escaping () -> String? = {
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        },
        repository: @escaping () -> GitHubRepository? = { ProjectLinks.githubRepository },
        openFile: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        revealFile: @escaping (URL) -> Void = {
            NSWorkspace.shared.activateFileViewerSelecting([$0])
        },
        openWebPage: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        automaticCheckInterval: TimeInterval = UpdateController.automaticCheckInterval,
        manualCheckCooldown: TimeInterval = UpdateController.manualCheckCooldown
    ) {
        self.service = service
        self.installedVersion = installedVersion
        self.repository = repository
        self.openFile = openFile
        self.revealFile = revealFile
        self.openWebPage = openWebPage
        self.now = now
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
            repository: repository()
           ) {
            usesTestingStatusOverride = true
            usesPackagedTestingStatusOverride = true
            status = mockStatus
        }
#endif
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
        guard checkTask == nil, downloadTask == nil else { return }
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
        beginCheck(
            repository: configuration.repository,
            installedVersion: configuration.installedVersion,
            preservesExistingResultOnFailure: false,
            isManual: true
        )
    }

    func downloadAvailableUpdate() {
        guard checkTask == nil, downloadTask == nil,
              let update = status.phase.availableUpdate else {
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
        guard checkTask == nil, downloadTask == nil,
              case let .readyToInstall(update, fileURL) = status.phase else {
            return
        }
        guard FileManager.default.fileExists(atPath: fileURL.path),
              openFile(fileURL) else {
            finishDownload(with: .failed(
                message: UpdateError.openFailed.localizedDescription,
                releasesURL: repository()?.releasesURL,
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
                releasesURL: repository()?.releasesURL,
                retryAt: nil,
                availableUpdate: update
            ))
            return
        }
        revealFile(fileURL)
    }

    func viewReleasesFallback() {
        guard let releasesURL = repository()?.releasesURL else { return }
        _ = openWebPage(releasesURL)
    }

    private typealias Configuration = (repository: GitHubRepository, installedVersion: String)

    private func configurationOrShowFailure() -> Configuration? {
        guard let installedVersion = installedVersion() else {
            updateStatus(phase: .failed(
                message: UpdateError.invalidInstalledVersion.localizedDescription,
                releasesURL: repository()?.releasesURL,
                retryAt: nil,
                availableUpdate: nil
            ))
            return nil
        }
        guard let repository = repository() else {
            updateStatus(phase: .failed(
                message: UpdateError.unsupportedRepository.localizedDescription,
                releasesURL: nil,
                retryAt: nil,
                availableUpdate: nil
            ))
            return nil
        }
        return (repository, installedVersion)
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
                releasesURL: repository()?.releasesURL,
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
