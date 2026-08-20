import Foundation
import XCTest
@testable import MD2PNG

final class UpdateControllerTests: XCTestCase {
    private let repository = UpdateTestFixtures.repository

    func testCheckingIsSeparateFromTheVisibleUpdatePhase() throws {
        let status = UpdateStatus(
            phase: .upToDate(version: try XCTUnwrap(SemanticVersion("0.2.0"))),
            isChecking: true,
            nextManualCheckAt: nil
        )

        XCTAssertTrue(status.isChecking)
        XCTAssertEqual(status.phase, .upToDate(version: SemanticVersion("0.2.0")!))
    }

    func testDebugReadyMockUsesOfflineSparkleMetadata() throws {
        let status = try XCTUnwrap(DebugUpdateMockState.readyToInstall.status(
            installedVersion: "0.1.0",
            repository: repository
        ))
        guard case let .sparkleReadyToInstall(update) = status.phase else {
            return XCTFail("The fixture should use the production Sparkle phase")
        }
        XCTAssertEqual(update.installedVersion, "0.1.0")
        XCTAssertEqual(update.displayVersion, "0.8.0")
        XCTAssertEqual(update.buildVersion, "8")
        XCTAssertEqual(update.fullReleaseNotesURL, repository.releasesURL)
    }

    @MainActor
    func testDisabledControllerAndFixtureKeepInteractiveUpdatesDisabled() async throws {
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let controller = UpdateController.disabled(
            installedVersion: { "0.1.0" },
            defaults: defaults
        )

        controller.checkAgain()
        await Task.yield()

        XCTAssertEqual(controller.status, UpdateStatus())
        XCTAssertFalse(controller.isUpdating)
        XCTAssertFalse(controller.allowsUpdatePresentation)

        let fixtureStatus = UpdateStatus(
            phase: .upToDate(version: try XCTUnwrap(SemanticVersion("0.1.0")))
        )
        controller.setStatusForTesting(fixtureStatus)
        controller.checkAgain()
        await Task.yield()

        XCTAssertEqual(controller.status, fixtureStatus)
        XCTAssertTrue(controller.allowsUpdatePresentation)
        XCTAssertFalse(controller.allowsInteractiveCheck)

        let update = UpdateTestFixtures.seamlessUpdate(installedVersion: "0.1.0")
        let availableStatus = UpdateStatus(phase: .sparkleUpdateAvailable(update))
        controller.setStatusForTesting(availableStatus)

        XCTAssertEqual(controller.status, availableStatus)
        XCTAssertFalse(controller.isUpdating)
        XCTAssertFalse(controller.allowsInteractiveCheck)
    }

    @MainActor
    func testDisabledUpdateDriverFailsClosed() {
        let driver = DisabledUpdateDriver()
        var result: UpdateProbeResult?

        driver.probe(installedVersion: "0.1.0") {
            result = $0
        }

        guard case let .failed(message) = result else {
            return XCTFail("A disabled driver must fail instead of starting an update")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(driver.installAndRelaunch())
        XCTAssertFalse(driver.deferInstallation(completion: nil))
    }

    func testCheckPolicyPersistsOnlyTheManualRequestWindow() {
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let policy = UpdateCheckPolicy(
            defaults: defaults,
            manualCheckCooldown: 60
        )
        let checkedAt = Date(timeIntervalSince1970: 1_000)

        policy.recordAttempt(at: checkedAt)
        XCTAssertFalse(policy.canMakeRequest(at: checkedAt.addingTimeInterval(59)))
        XCTAssertTrue(policy.canMakeRequest(at: checkedAt.addingTimeInterval(60)))
        XCTAssertEqual(
            UpdateCheckPolicy(defaults: defaults, manualCheckCooldown: 60)
                .nextAllowedRequestDate(),
            checkedAt.addingTimeInterval(60)
        )
        XCTAssertEqual(
            policy.localRetryDate(after: checkedAt),
            checkedAt.addingTimeInterval(60)
        )
    }

    @MainActor
    func testSparkleProbeAndDownloadRequireSeparateExplicitActions() throws {
        let driver = FakeUpdateDriver()
        let update = UpdateTestFixtures.seamlessUpdate(
            installedVersion: "0.6.0",
            version: "0.7.0",
            build: "7"
        )
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let controller = UpdateController(
            channel: { .stableGitHubReleases(repository: self.repository) },
            installedVersion: { "0.6.0" },
            defaults: defaults,
            updateDriver: driver
        )

        XCTAssertEqual(driver.probeCount, 0)
        XCTAssertEqual(controller.status.phase, .unknown)

        controller.checkAgain()
        XCTAssertEqual(driver.probeCount, 1)
        XCTAssertEqual(driver.probedInstalledVersions, ["0.6.0"])
        XCTAssertTrue(controller.status.isChecking)
        driver.complete(.updateAvailable(update))

        XCTAssertEqual(
            controller.status.phase,
            .sparkleUpdateAvailable(update)
        )
        XCTAssertFalse(controller.status.isChecking)
        XCTAssertEqual(driver.downloadRequests, [])

        controller.downloadAvailableUpdate()
        XCTAssertEqual(driver.downloadRequests, ["7"])
        XCTAssertEqual(
            controller.status.phase,
            .sparkleDownloading(update, progressPercent: 0)
        )

        driver.send(.downloading(received: 2, expected: 4))
        XCTAssertEqual(
            controller.status.phase,
            .sparkleDownloading(update, progressPercent: 50)
        )
        driver.send(.extracting(progress: 0.75))
        XCTAssertEqual(
            controller.status.phase,
            .sparkleExtracting(update, progressPercent: 75)
        )
        driver.send(.readyToInstall)
        XCTAssertEqual(controller.status.phase, .sparkleReadyToInstall(update))
    }

    @MainActor
    func testSparkleLatestResultStaysInlineWithoutOpeningStandardUI() throws {
        let driver = FakeUpdateDriver()
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let controller = UpdateController(
            channel: { .stableGitHubReleases(repository: self.repository) },
            installedVersion: { "0.6.0" },
            defaults: defaults,
            updateDriver: driver
        )

        controller.checkAgain()
        driver.complete(.noUpdate(reason: .onLatestVersion, latestDisplayVersion: "0.6.0"))

        XCTAssertEqual(controller.status.phase, .upToDate(version: SemanticVersion("0.6.0")!))
        XCTAssertEqual(driver.downloadRequests, [])
    }

    @MainActor
    func testSparkleManualCheckHonorsPersistedCooldown() throws {
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let currentDate = LockedBox(Date(timeIntervalSince1970: 1_000))
        let firstDriver = FakeUpdateDriver()
        let firstController = UpdateController(
            channel: { .stableGitHubReleases(repository: self.repository) },
            installedVersion: { "0.6.0" },
            defaults: defaults,
            now: { currentDate.value },
            updateDriver: firstDriver
        )

        firstController.checkAgain()
        firstDriver.complete(.noUpdate(
            reason: .onLatestVersion,
            latestDisplayVersion: "0.6.0"
        ))
        firstController.checkAgain()
        XCTAssertEqual(firstDriver.probeCount, 1)
        XCTAssertEqual(
            firstController.status.nextManualCheckAt,
            Date(timeIntervalSince1970: 1_060)
        )

        currentDate.set(Date(timeIntervalSince1970: 1_061))
        let secondDriver = FakeUpdateDriver()
        let secondController = UpdateController(
            channel: { .stableGitHubReleases(repository: self.repository) },
            installedVersion: { "0.6.0" },
            defaults: defaults,
            now: { currentDate.value },
            updateDriver: secondDriver
        )
        secondController.checkAgain()
        XCTAssertEqual(secondDriver.probeCount, 1)
    }

    @MainActor
    func testSparkleInstallRespectsGateAndMarksExpectedRelaunchVersion() throws {
        let driver = FakeUpdateDriver()
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let update = UpdateTestFixtures.seamlessUpdate()
        let allowsInstall = LockedBox(false)
        let acceptedCount = LockedBox(0)
        let endedCount = LockedBox(0)
        let controller = UpdateController(
            channel: { .stableGitHubReleases(repository: self.repository) },
            installedVersion: { "0.7.0" },
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1_000) },
            updateDriver: driver,
            beforeInstallAndRelaunch: { _ in allowsInstall.value },
            onInstallAccepted: {
                acceptedCount.set(acceptedCount.value + 1)
            },
            onInstallEndedWithoutRelaunch: {
                endedCount.set(endedCount.value + 1)
            }
        )

        controller.checkAgain()
        driver.complete(.updateAvailable(update))
        controller.downloadAvailableUpdate()
        driver.send(.readyToInstall)

        controller.installLater()
        XCTAssertEqual(driver.deferCount, 1)
        XCTAssertEqual(controller.status.phase, .sparkleReadyToInstall(update))

        controller.installAndRelaunch()
        XCTAssertEqual(driver.installCount, 0)
        XCTAssertNil(defaults.string(forKey: UpdateRelaunchMarker.expectedVersionKey))

        allowsInstall.set(true)
        controller.installAndRelaunch()
        XCTAssertEqual(driver.installCount, 1)
        XCTAssertEqual(acceptedCount.value, 1)
        XCTAssertEqual(
            defaults.string(forKey: UpdateRelaunchMarker.expectedVersionKey),
            "0.8.0"
        )
        driver.send(.installing)
        XCTAssertEqual(controller.status.phase, .sparkleInstalling(update))
        driver.send(.failed(message: "Authorization cancelled"))
        XCTAssertEqual(
            controller.status.phase,
            .sparkleFailed(message: "Authorization cancelled", update: update)
        )
        XCTAssertEqual(endedCount.value, 1)
        XCTAssertNil(defaults.string(forKey: UpdateRelaunchMarker.expectedVersionKey))
    }

    @MainActor
    func testTerminationWaitsForPreparedInstallerCancellation() {
        let driver = FakeUpdateDriver()
        driver.completesDeferralImmediately = false
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let update = UpdateTestFixtures.seamlessUpdate()
        let terminationCompletionCount = LockedBox(0)
        let controller = UpdateController(
            channel: { .stableGitHubReleases(repository: self.repository) },
            installedVersion: { "0.7.0" },
            defaults: defaults,
            updateDriver: driver
        )
        controller.setStatusForTesting(UpdateStatus(
            phase: .sparkleReadyToInstall(update)
        ))

        controller.installLater()
        let waitsForCancellation = controller
            .cancelPreparedInstallationForApplicationTermination {
                terminationCompletionCount.set(
                    terminationCompletionCount.value + 1
                )
            }

        XCTAssertTrue(waitsForCancellation)
        XCTAssertEqual(terminationCompletionCount.value, 0)
        driver.completeDeferral()
        XCTAssertEqual(terminationCompletionCount.value, 1)
    }

    @MainActor
    func testTerminationDuringExtractionWaitsForReadySkipAndCycleCompletion() {
        let driver = FakeUpdateDriver()
        driver.completesDeferralImmediately = false
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let update = UpdateTestFixtures.seamlessUpdate()
        let terminationCompletionCount = LockedBox(0)
        let controller = UpdateController(
            channel: { .stableGitHubReleases(repository: self.repository) },
            installedVersion: { "0.7.0" },
            defaults: defaults,
            updateDriver: driver
        )
        controller.checkAgain()
        driver.complete(.updateAvailable(update))
        controller.downloadAvailableUpdate()
        driver.send(.extracting(progress: 0.5))

        let waitsForCancellation = controller
            .cancelPreparedInstallationForApplicationTermination {
                terminationCompletionCount.set(
                    terminationCompletionCount.value + 1
                )
            }

        XCTAssertTrue(waitsForCancellation)
        XCTAssertEqual(terminationCompletionCount.value, 0)
        driver.send(.readyToInstall)
        XCTAssertEqual(driver.readySkipCount, 1)
        XCTAssertEqual(
            controller.status.phase,
            .sparkleExtracting(update, progressPercent: 50)
        )
        XCTAssertEqual(terminationCompletionCount.value, 0)
        driver.completeDeferral()
        XCTAssertEqual(terminationCompletionCount.value, 1)
    }

    @MainActor
    func testSparkleIncompatibleResultIsNotPresentedAsUpToDate() throws {
        let driver = FakeUpdateDriver()
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let controller = UpdateController(
            channel: { .stableGitHubReleases(repository: self.repository) },
            installedVersion: { "0.6.0" },
            defaults: defaults,
            updateDriver: driver
        )

        controller.checkAgain()
        driver.complete(.noUpdate(reason: .systemIsTooOld, latestDisplayVersion: "0.7.0"))

        guard case let .failed(message, releasesURL, _) = controller.status.phase else {
            return XCTFail("Expected an incompatible-update failure")
        }
        XCTAssertTrue(message.contains("newer version of macOS"))
        XCTAssertEqual(releasesURL, repository.releasesURL)
        XCTAssertEqual(driver.downloadRequests, [])
    }

}

@MainActor
private final class FakeUpdateDriver: UpdateDriving {
    private var completion: (@MainActor (UpdateProbeResult) -> Void)?
    private var eventHandler: (@MainActor (UpdateDriverEvent) -> Void)?
    private(set) var probeCount = 0
    private(set) var probedInstalledVersions: [String] = []
    private(set) var downloadRequests: [String] = []
    private(set) var cancelCount = 0
    private(set) var deferCount = 0
    private(set) var installCount = 0
    private(set) var readySkipCount = 0
    var completesDeferralImmediately = true
    private var deferCompletion: (@MainActor () -> Void)?
    private var isPreparingInstallation = false
    private var defersWhenReady = false

    func setEventHandler(_ handler: @escaping @MainActor (UpdateDriverEvent) -> Void) {
        eventHandler = handler
    }

    func probe(
        installedVersion: String,
        completion: @escaping @MainActor (UpdateProbeResult) -> Void
    ) {
        probeCount += 1
        probedInstalledVersions.append(installedVersion)
        self.completion = completion
    }

    func downloadUpdate(expectedBuildVersion: String) {
        downloadRequests.append(expectedBuildVersion)
    }

    func cancelDownload() {
        cancelCount += 1
    }

    func deferInstallation(
        completion: (@MainActor () -> Void)?
    ) -> Bool {
        deferCount += 1
        if isPreparingInstallation {
            defersWhenReady = true
        }
        if completesDeferralImmediately {
            completion?()
        } else {
            deferCompletion = completion
        }
        return true
    }

    func installAndRelaunch() -> Bool {
        installCount += 1
        return true
    }

    func complete(_ result: UpdateProbeResult) {
        let completion = completion
        self.completion = nil
        completion?(result)
    }

    func send(_ event: UpdateDriverEvent) {
        if case .extracting = event {
            isPreparingInstallation = true
        }
        if case .readyToInstall = event {
            isPreparingInstallation = false
            if defersWhenReady {
                defersWhenReady = false
                readySkipCount += 1
                return
            }
        }
        eventHandler?(event)
    }

    func completeDeferral() {
        let completion = deferCompletion
        deferCompletion = nil
        completion?()
    }
}
