import AppKit
import Sparkle

enum UpdateProbeNoUpdateReason: Equatable, Sendable {
    case onLatestVersion
    case onNewerThanLatestVersion
    case systemIsTooOld
    case systemIsTooNew
    case hardwareDoesNotSupportARM64
    case unknown
}

enum UpdateProbeResult: Equatable, Sendable {
    case updateAvailable(SeamlessUpdate)
    case noUpdate(reason: UpdateProbeNoUpdateReason, latestDisplayVersion: String?)
    case failed(message: String)
}

enum UpdateDriverEvent: Equatable, Sendable {
    case updateChanged(SeamlessUpdate)
    case downloading(received: UInt64, expected: UInt64?)
    case extracting(progress: Double)
    case readyToInstall
    case installing
    case cancelled
    case failed(message: String)
}

@MainActor
protocol UpdateDriving: AnyObject {
    func setEventHandler(_ handler: @escaping @MainActor (UpdateDriverEvent) -> Void)
    func probe(
        installedVersion: String,
        completion: @escaping @MainActor (UpdateProbeResult) -> Void
    )
    func downloadUpdate(expectedBuildVersion: String)
    func cancelDownload()
    @discardableResult
    func deferInstallation(
        completion: (@MainActor () -> Void)?
    ) -> Bool
    func installAndRelaunch() -> Bool
}

@MainActor
final class DisabledUpdateDriver: UpdateDriving {
    func setEventHandler(_ handler: @escaping @MainActor (UpdateDriverEvent) -> Void) {}

    func probe(
        installedVersion: String,
        completion: @escaping @MainActor (UpdateProbeResult) -> Void
    ) {
        completion(.failed(message: L10n.text(
            "about.update_configuration_failed",
            defaultValue: "The signed updater could not be started."
        )))
    }

    func downloadUpdate(expectedBuildVersion: String) {}

    func cancelDownload() {}

    func deferInstallation(
        completion: (@MainActor () -> Void)?
    ) -> Bool {
        false
    }

    func installAndRelaunch() -> Bool {
        false
    }
}

@MainActor
final class SparkleUpdateDriver: NSObject, UpdateDriving, SPUUpdaterDelegate {
    private let feedURL: () -> URL?
    private var eventHandler: (@MainActor (UpdateDriverEvent) -> Void)?
    private var probeCompletion: (@MainActor (UpdateProbeResult) -> Void)?
    private var pendingProbeResult: UpdateProbeResult?
    private var probeInstalledVersion: String?
    private var loadedAppcastEntries: [SeamlessUpdateAppcastEntry] = []
    private var availableBuildVersion: String?
    private var deferInstallationCompletion: (@MainActor () -> Void)?
    private var updaterStarted = false

    private lazy var userDriver = AboutSparkleUserDriver { [weak self] event in
        self?.handleUserDriverEvent(event)
    }

    private lazy var updater = SPUUpdater(
        hostBundle: .main,
        applicationBundle: .main,
        userDriver: userDriver,
        delegate: self
    )

    init(feedURL: @escaping () -> URL?) {
        self.feedURL = feedURL
        super.init()
    }

    func setEventHandler(_ handler: @escaping @MainActor (UpdateDriverEvent) -> Void) {
        eventHandler = handler
    }

    func probe(
        installedVersion: String,
        completion: @escaping @MainActor (UpdateProbeResult) -> Void
    ) {
        guard probeCompletion == nil else { return }
        guard ensureUpdaterStarted() else {
            completion(.failed(message: L10n.text(
                "about.update_configuration_failed",
                defaultValue: "The signed updater could not be started."
            )))
            return
        }
        guard updater.canCheckForUpdates, !updater.sessionInProgress else {
            completion(.failed(message: L10n.text(
                "about.update_busy",
                defaultValue: "Another update check is already in progress."
            )))
            return
        }

        pendingProbeResult = nil
        probeInstalledVersion = installedVersion
        loadedAppcastEntries = []
        probeCompletion = completion
        updater.checkForUpdateInformation()
    }

    func downloadUpdate(expectedBuildVersion: String) {
        guard ensureUpdaterStarted() else {
            eventHandler?(.failed(message: L10n.text(
                "about.update_configuration_failed",
                defaultValue: "The signed updater could not be started."
            )))
            return
        }
        guard updater.canCheckForUpdates, !updater.sessionInProgress else {
            eventHandler?(.failed(message: L10n.text(
                "about.update_busy",
                defaultValue: "Another update operation is already in progress."
            )))
            return
        }
        availableBuildVersion = expectedBuildVersion
        userDriver.prepareDownload(expectedBuildVersion: expectedBuildVersion)
        updater.checkForUpdates()
    }

    func cancelDownload() {
        userDriver.cancelDownload()
    }

    @discardableResult
    func deferInstallation(
        completion: (@MainActor () -> Void)?
    ) -> Bool {
        guard userDriver.canDeferPreparedInstallation else { return false }
        deferInstallationCompletion = completion
        guard userDriver.deferInstallation() else {
            deferInstallationCompletion = nil
            return false
        }
        return true
    }

    func installAndRelaunch() -> Bool {
        if userDriver.installAndRelaunch() { return true }
        guard let availableBuildVersion else {
            eventHandler?(.failed(message: L10n.text(
                "about.update_not_ready",
                defaultValue: "The update is not ready to install yet."
            )))
            return false
        }
        guard updater.canCheckForUpdates, !updater.sessionInProgress else {
            eventHandler?(.failed(message: L10n.text(
                "about.update_busy",
                defaultValue: "Another update operation is already in progress."
            )))
            return false
        }
        userDriver.prepareInstall(expectedBuildVersion: availableBuildVersion)
        updater.checkForUpdates()
        return true
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feedURL()?.absoluteString
    }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        []
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        loadedAppcastEntries = appcast.items.map(appcastEntry)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard probeCompletion != nil,
              let installedVersion = probeInstalledVersion else {
            return
        }
        pendingProbeResult = makeAvailableResult(
            selectedItem: item,
            installedVersion: installedVersion
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        guard probeCompletion != nil else { return }
        let nsError = error as NSError
        let reasonValue = (nsError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue
        let latestItem = nsError.userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem
        pendingProbeResult = .noUpdate(
            reason: Self.noUpdateReason(rawValue: reasonValue),
            latestDisplayVersion: latestItem?.displayVersionString
        )
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        guard let completion = probeCompletion else {
            let deferCompletion = deferInstallationCompletion
            deferInstallationCompletion = nil
            deferCompletion?()
            return
        }
        let result = pendingProbeResult
            ?? error.map { .failed(message: $0.localizedDescription) }
            ?? .failed(message: L10n.text(
                "about.update_unknown_result",
                defaultValue: "The update check finished without a result."
            ))
        pendingProbeResult = nil
        probeInstalledVersion = nil
        probeCompletion = nil
        completion(result)
    }

    private func ensureUpdaterStarted() -> Bool {
        if updaterStarted { return true }
        do {
            try updater.start()
            updaterStarted = true
            return true
        } catch {
            return false
        }
    }

    private func makeAvailableResult(
        selectedItem: SUAppcastItem,
        installedVersion: String
    ) -> UpdateProbeResult {
        let entries = loadedAppcastEntries.isEmpty
            ? [appcastEntry(selectedItem)]
            : loadedAppcastEntries
        guard let update = SeamlessUpdateMetadataBuilder.make(
            installedVersion: installedVersion,
            selectedBuildVersion: selectedItem.versionString,
            entries: entries
        ) else {
            return .failed(message: L10n.text(
                "about.update_invalid_metadata",
                defaultValue: "The signed update feed contains invalid release information."
            ))
        }
        return .updateAvailable(update)
    }

    private func handleUserDriverEvent(_ event: AboutSparkleUserDriverEvent) {
        switch event {
        case let .updateChanged(item):
            let installedVersion = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? ""
            switch makeAvailableResult(
                selectedItem: item,
                installedVersion: installedVersion
            ) {
            case let .updateAvailable(update):
                eventHandler?(.updateChanged(update))
            case let .failed(message):
                eventHandler?(.failed(message: message))
            case .noUpdate:
                break
            }
        case let .downloading(received, expected):
            eventHandler?(.downloading(received: received, expected: expected))
        case let .extracting(progress):
            eventHandler?(.extracting(progress: progress))
        case .readyToInstall:
            eventHandler?(.readyToInstall)
        case .installing:
            eventHandler?(.installing)
        case .cancelled:
            eventHandler?(.cancelled)
        case let .failed(message):
            eventHandler?(.failed(message: message))
        }
    }

    private func appcastEntry(_ item: SUAppcastItem) -> SeamlessUpdateAppcastEntry {
        SeamlessUpdateAppcastEntry(
            displayVersion: item.displayVersionString,
            buildVersion: item.versionString,
            publishedAt: item.date,
            contentLength: item.contentLength > 0 ? item.contentLength : nil,
            releaseNotes: item.itemDescription,
            fullReleaseNotesURL: SeamlessUpdateLinkPolicy.trustedReleaseNotesURL(
                item.fullReleaseNotesURL ?? item.infoURL,
                feedURL: feedURL()
            )
        )
    }

    private static func noUpdateReason(rawValue: Int?) -> UpdateProbeNoUpdateReason {
        switch rawValue {
        case Int(SPUNoUpdateFoundReason.onLatestVersion.rawValue):
            return .onLatestVersion
        case Int(SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue):
            return .onNewerThanLatestVersion
        case Int(SPUNoUpdateFoundReason.systemIsTooOld.rawValue):
            return .systemIsTooOld
        case Int(SPUNoUpdateFoundReason.systemIsTooNew.rawValue):
            return .systemIsTooNew
        case Int(SPUNoUpdateFoundReason.hardwareDoesNotSupportARM64.rawValue):
            return .hardwareDoesNotSupportARM64
        default:
            return .unknown
        }
    }
}

enum AboutSparkleUserDriverEvent {
    case updateChanged(SUAppcastItem)
    case downloading(received: UInt64, expected: UInt64?)
    case extracting(progress: Double)
    case readyToInstall
    case installing
    case cancelled
    case failed(message: String)
}

@MainActor
final class AboutSparkleUserDriver: NSObject, SPUUserDriver {
    private let eventHandler: (AboutSparkleUserDriverEvent) -> Void
    private var expectedBuildVersion: String?
    private var checkCancellation: (() -> Void)?
    private var downloadCancellation: (() -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var receivedContentLength: UInt64 = 0
    private var expectedContentLength: UInt64?
    private var installsWhenReady = false
    private var isPreparingInstallation = false
    private var defersWhenReady = false

    var canDeferPreparedInstallation: Bool {
        isPreparingInstallation || installReply != nil
    }

    init(eventHandler: @escaping (AboutSparkleUserDriverEvent) -> Void) {
        self.eventHandler = eventHandler
        super.init()
    }

    func prepareDownload(expectedBuildVersion: String) {
        self.expectedBuildVersion = expectedBuildVersion
        installsWhenReady = false
        isPreparingInstallation = false
        defersWhenReady = false
        receivedContentLength = 0
        expectedContentLength = nil
    }

    func prepareInstall(expectedBuildVersion: String) {
        self.expectedBuildVersion = expectedBuildVersion
        installsWhenReady = true
        isPreparingInstallation = false
        defersWhenReady = false
    }

    func cancelDownload() {
        guard let cancellation = downloadCancellation ?? checkCancellation else { return }
        downloadCancellation = nil
        checkCancellation = nil
        cancellation()
        eventHandler(.cancelled)
    }

    @discardableResult
    func deferInstallation() -> Bool {
        if let reply = installReply {
            installReply = nil
            reply(.skip)
            return true
        }
        guard isPreparingInstallation else { return false }
        defersWhenReady = true
        return true
    }

    func installAndRelaunch() -> Bool {
        guard let reply = installReply else { return false }
        installReply = nil
        reply(.install)
        return true
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(
            automaticUpdateChecks: false,
            sendSystemProfile: false
        ))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        checkCancellation = cancellation
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        checkCancellation = nil
        guard !appcastItem.isInformationOnlyUpdate else {
            expectedBuildVersion = nil
            reply(.dismiss)
            eventHandler(.failed(message: L10n.text(
                "about.update_manual_only",
                defaultValue: "This update must be installed manually from the Releases page."
            )))
            return
        }
        guard appcastItem.versionString == expectedBuildVersion else {
            expectedBuildVersion = nil
            reply(.dismiss)
            eventHandler(.updateChanged(appcastItem))
            return
        }
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        checkCancellation = nil
        expectedBuildVersion = nil
        isPreparingInstallation = false
        defersWhenReady = false
        eventHandler(.failed(message: error.localizedDescription))
        acknowledgement()
    }

    func showUpdaterError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        checkCancellation = nil
        downloadCancellation = nil
        installReply = nil
        isPreparingInstallation = false
        defersWhenReady = false
        eventHandler(.failed(message: error.localizedDescription))
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        downloadCancellation = cancellation
        receivedContentLength = 0
        eventHandler(.downloading(received: 0, expected: expectedContentLength))
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        self.expectedContentLength = expectedContentLength > 0
            ? expectedContentLength
            : nil
        eventHandler(.downloading(
            received: receivedContentLength,
            expected: self.expectedContentLength
        ))
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedContentLength += length
        eventHandler(.downloading(
            received: receivedContentLength,
            expected: expectedContentLength
        ))
    }

    func showDownloadDidStartExtractingUpdate() {
        downloadCancellation = nil
        isPreparingInstallation = true
        eventHandler(.extracting(progress: 0))
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        eventHandler(.extracting(progress: min(max(progress, 0), 1)))
    }

    func showReady(
        toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        isPreparingInstallation = false
        if defersWhenReady {
            defersWhenReady = false
            reply(.skip)
            return
        }
        if installsWhenReady {
            installsWhenReady = false
            reply(.install)
            return
        }
        installReply = reply
        eventHandler(.readyToInstall)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        eventHandler(.installing)
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        checkCancellation = nil
        downloadCancellation = nil
        installReply = nil
        expectedBuildVersion = nil
        installsWhenReady = false
        isPreparingInstallation = false
        defersWhenReady = false
    }

    func showUpdateInFocus() {}
}
