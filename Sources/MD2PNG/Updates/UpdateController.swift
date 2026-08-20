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

    func status(
        installedVersion: String?,
        repository: GitHubRepository?
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
            return UpdateStatus(phase: .sparkleFailed(
                message: UpdateError.digestMismatch.localizedDescription,
                update: fixtureSeamlessUpdate(
                    installedVersion: installedVersion,
                    releasesURL: repository?.releasesURL
                )
            ))
        case .readyToInstall:
            return UpdateStatus(phase: .sparkleReadyToInstall(
                fixtureSeamlessUpdate(
                    installedVersion: installedVersion,
                    releasesURL: repository?.releasesURL
                )
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
    private let diagnosticLogger: DiagnosticLogger
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

    static func disabled(
        diagnosticLogger: DiagnosticLogger = .disabled,
        installedVersion: @escaping () -> String? = {
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        },
        openWebPage: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) -> UpdateController {
        UpdateController(
            diagnosticLogger: diagnosticLogger,
            channel: { .disabled },
            installedVersion: installedVersion,
            openWebPage: openWebPage,
            defaults: defaults,
            now: now,
            updateDriver: DisabledUpdateDriver()
        )
    }

    convenience init(
        diagnosticLogger: DiagnosticLogger = .disabled,
        channel: @escaping () -> UpdateChannel = { .current() },
        installedVersion: @escaping () -> String? = {
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        },
        openWebPage: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        manualCheckCooldown: TimeInterval = UpdateController.manualCheckCooldown,
        updateDriver: UpdateDriving,
        beforeInstallAndRelaunch: @escaping @MainActor (SeamlessUpdate) -> Bool = { _ in
            true
        },
        onInstallAccepted: @escaping @MainActor () -> Void = {},
        onInstallEndedWithoutRelaunch: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            session: SparkleUpdateSession(
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
            ),
            diagnosticLogger: diagnosticLogger,
            channel: channel,
            installedVersion: installedVersion,
            openWebPage: openWebPage
        )
    }

    convenience init(
        legacyService service: UpdateService,
        diagnosticLogger: DiagnosticLogger = .disabled,
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
        manualCheckCooldown: TimeInterval = UpdateController.manualCheckCooldown
    ) {
        self.init(
            session: LegacyUpdateSession(
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
            ),
            diagnosticLogger: diagnosticLogger,
            channel: channel,
            installedVersion: installedVersion,
            openWebPage: openWebPage
        )
    }

    private init(
        session: any UpdateSession,
        diagnosticLogger: DiagnosticLogger,
        channel: @escaping () -> UpdateChannel,
        installedVersion: @escaping () -> String?,
        openWebPage: @escaping (URL) -> Bool
    ) {
        self.session = session
        self.channel = channel
        self.openWebPage = openWebPage
        self.diagnosticLogger = diagnosticLogger

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
        diagnosticLogger.record(
            category: .releases,
            stage: .fullReleaseNotesOpen,
            result: .started
        )
        session.viewFullReleaseNotes()
    }

    func openDownloadedUpdate() {
        session.openDownloadedUpdate()
    }

    func revealDownloadedUpdate() {
        session.revealDownloadedUpdate()
    }

    func viewReleasesFallback() {
        diagnosticLogger.record(
            category: .releases,
            stage: .releasesOpen,
            result: .started
        )
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
