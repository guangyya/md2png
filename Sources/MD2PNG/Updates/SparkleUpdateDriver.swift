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
    case updateAvailable(displayVersion: String)
    case noUpdate(reason: UpdateProbeNoUpdateReason, latestDisplayVersion: String?)
    case failed(message: String)
}

@MainActor
protocol UpdateDriving: AnyObject {
    func probe(completion: @escaping @MainActor (UpdateProbeResult) -> Void)
    func showStandardUpdateUI()
}

@MainActor
final class SparkleUpdateDriver: NSObject, UpdateDriving, SPUUpdaterDelegate {
    private let feedURL: () -> URL?
    private var probeCompletion: (@MainActor (UpdateProbeResult) -> Void)?
    private var pendingProbeResult: UpdateProbeResult?

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    init(feedURL: @escaping () -> URL?) {
        self.feedURL = feedURL
        super.init()
    }

    func probe(completion: @escaping @MainActor (UpdateProbeResult) -> Void) {
        guard probeCompletion == nil else { return }
        let updater = controller.updater
        guard updater.canCheckForUpdates, !updater.sessionInProgress else {
            completion(.failed(message: L10n.text(
                "about.update_busy",
                defaultValue: "Another update check is already in progress."
            )))
            return
        }

        pendingProbeResult = nil
        probeCompletion = completion
        updater.checkForUpdateInformation()
    }

    func showStandardUpdateUI() {
        controller.checkForUpdates(nil)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feedURL()?.absoluteString
    }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        []
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard probeCompletion != nil else { return }
        pendingProbeResult = .updateAvailable(displayVersion: item.displayVersionString)
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
        guard let completion = probeCompletion else { return }
        let result = pendingProbeResult
            ?? error.map { .failed(message: $0.localizedDescription) }
            ?? .failed(message: L10n.text(
                "about.update_unknown_result",
                defaultValue: "The update check finished without a result."
            ))
        pendingProbeResult = nil
        probeCompletion = nil
        completion(result)
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
