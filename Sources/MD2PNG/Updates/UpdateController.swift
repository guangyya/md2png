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

    private let session: any UpdateSession
    private let channel: () -> UpdateChannel
    private let openWebPage: (URL) -> Bool
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
        status.isChecking || status.phase.isDownloadActive || session.isUpdating
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
        self.channel = channel
        self.openWebPage = openWebPage

        if let updateDriver {
            session = SparkleUpdateSession(
                updateDriver: updateDriver,
                channel: channel,
                installedVersion: installedVersion,
                openWebPage: openWebPage,
                defaults: defaults,
                now: now,
                manualCheckCooldown: manualCheckCooldown,
                beforeInstallAndRelaunch: beforeInstallAndRelaunch,
                onInstallAccepted: onInstallAccepted,
                onInstallEndedWithoutRelaunch: onInstallEndedWithoutRelaunch
            )
        } else {
            session = LegacyUpdateSession(
                service: service,
                channel: channel,
                installedVersion: installedVersion,
                openFile: openFile,
                revealFile: revealFile,
                openWebPage: openWebPage,
                defaults: defaults,
                now: now,
                automaticCheckInterval: automaticCheckInterval,
                manualCheckCooldown: manualCheckCooldown
            )
        }

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
            session.setStatusForTesting(mockStatus)
            status = mockStatus
        } else {
            status = session.status
        }
#else
        status = session.status
#endif

        session.onStatusChange = { [weak self] status in
            guard let self else { return }
#if DEBUG
            guard !self.usesTestingStatusOverride else { return }
#endif
            self.status = status
        }
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
        session.setStatusForTesting(newStatus)
        status = newStatus
    }
#endif

    func refreshIfNeeded() {
#if DEBUG
        if usesTestingStatusOverride {
            if usesPackagedTestingStatusOverride {
                session.refreshManualCheckAvailability()
                status = session.status
            }
            return
        }
#endif
        session.refreshIfNeeded()
    }

    func checkAgain() {
#if DEBUG
        guard !usesTestingStatusOverride else { return }
#endif
        session.checkAgain()
    }

    func downloadAvailableUpdate() {
        session.downloadAvailableUpdate()
    }

    func cancelUpdate() {
        session.cancelUpdate()
    }

    func installAndRelaunch() {
        session.installAndRelaunch()
    }

    func installLater() {
        session.installLater()
    }

    func cancelPreparedInstallationForApplicationTermination(
        completion: @escaping @MainActor () -> Void
    ) -> Bool {
        session.cancelPreparedInstallationForApplicationTermination(
            completion: completion
        )
    }

    func viewFullReleaseNotes() {
        session.viewFullReleaseNotes()
    }

    func openDownloadedUpdate() {
        session.openDownloadedUpdate()
    }

    func revealDownloadedUpdate() {
        session.revealDownloadedUpdate()
    }

    func viewReleasesFallback() {
#if DEBUG
        if usesPackagedTestingStatusOverride,
           let releasesURL = ProjectLinks.githubRepository?.releasesURL {
            _ = openWebPage(releasesURL)
            return
        }
#endif
        session.viewReleasesFallback()
    }
}
