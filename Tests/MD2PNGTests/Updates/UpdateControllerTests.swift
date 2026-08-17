import Foundation
import XCTest
@testable import MD2PNG

final class UpdateControllerTests: XCTestCase {
    private let repository = UpdateTestFixtures.repository

    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testCheckingIsSeparateFromTheVisibleUpdatePhase() throws {
        let status = UpdateStatus(
            phase: .upToDate(version: try XCTUnwrap(SemanticVersion("0.2.0"))),
            isChecking: true,
            nextManualCheckAt: nil
        )

        XCTAssertTrue(status.isChecking)
        XCTAssertEqual(status.phase, .upToDate(version: SemanticVersion("0.2.0")!))
    }

    func testDebugReadyMockUsesOfflineFixtureMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MD2PNGDebugUpdateMockTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let status = try XCTUnwrap(DebugUpdateMockState.readyToInstall.status(
            installedVersion: "0.1.0",
            repository: repository,
            updatesDirectory: directory
        ))
        guard case let .failed(message, _, _, availableUpdate) = status.phase else {
            return XCTFail("A missing cached DMG should offer a recoverable download")
        }
        let update = try XCTUnwrap(availableUpdate)
        XCTAssertEqual(message, UpdateError.revealFailed.localizedDescription)
        XCTAssertEqual(update.version, SemanticVersion("0.1.0")!)
        XCTAssertEqual(update.tagName, "debug-fixture")
        XCTAssertEqual(update.assetName, "md2png-debug-update-fixture.dmg")
        XCTAssertEqual(update.downloadURL.host, "updates.invalid")
        XCTAssertEqual(update.size, 3)
        XCTAssertEqual(
            update.sha256,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @MainActor
    func testDisabledChannelAndFixtureNeverContactTheUpdateService() async throws {
        let requestCount = LockedBox(0)
        URLProtocolStub.handler = { _ in
            requestCount.set(requestCount.value + 1)
            throw URLError(.badServerResponse)
        }
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let controller = UpdateController(
            service: UpdateService(session: UpdateTestFixtures.stubbedSession()),
            channel: { .disabled },
            installedVersion: { "0.1.0" },
            defaults: defaults
        )

        controller.refreshIfNeeded()
        controller.checkAgain()
        await Task.yield()

        XCTAssertEqual(requestCount.value, 0)
        XCTAssertEqual(controller.status, UpdateStatus())
        XCTAssertFalse(controller.isUpdating)
        XCTAssertFalse(controller.allowsUpdatePresentation)

        let fixtureStatus = UpdateStatus(
            phase: .upToDate(version: try XCTUnwrap(SemanticVersion("0.1.0")))
        )
        controller.setStatusForTesting(fixtureStatus)
        controller.refreshIfNeeded()
        controller.checkAgain()
        await Task.yield()

        XCTAssertEqual(requestCount.value, 0)
        XCTAssertEqual(controller.status, fixtureStatus)
        XCTAssertTrue(controller.allowsUpdatePresentation)
        XCTAssertFalse(controller.allowsInteractiveCheck)

        let availableUpdate = UpdateTestFixtures.availableUpdate()
        let availableStatus = UpdateStatus(phase: .updateAvailable(availableUpdate))
        controller.setStatusForTesting(availableStatus)
        controller.downloadAvailableUpdate()
        await Task.yield()

        XCTAssertEqual(requestCount.value, 0)
        XCTAssertEqual(controller.status, availableStatus)
        XCTAssertFalse(controller.canDownload(availableUpdate))

        let failedStatus = UpdateStatus(phase: .failed(
            message: UpdateError.downloadFailed.localizedDescription,
            releasesURL: repository.releasesURL,
            retryAt: nil,
            availableUpdate: availableUpdate
        ))
        controller.setStatusForTesting(failedStatus)
        controller.downloadAvailableUpdate()
        await Task.yield()

        XCTAssertEqual(requestCount.value, 0)
        XCTAssertEqual(controller.status, failedStatus)
        XCTAssertFalse(controller.isUpdating)
    }

    func testCheckPolicyPersistsReleaseAndAppliesFreshnessAndRequestWindows() throws {
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let policy = UpdateCheckPolicy(
            defaults: defaults,
            automaticCheckInterval: 24 * 60 * 60,
            manualCheckCooldown: 60
        )
        let checkedAt = Date(timeIntervalSince1970: 1_000)
        let release = UpdateTestFixtures.release(version: "0.2.0")

        policy.cache(release: release, repository: repository, checkedAt: checkedAt)
        let persistedData = try XCTUnwrap(defaults.data(forKey: "Update.cachedRelease.v1"))
        let legacyReadableRecord = try PropertyListDecoder().decode(
            LegacyCachedReleaseRecord.self,
            from: persistedData
        )
        XCTAssertEqual(legacyReadableRecord.release.tagName, release.tagName)
        XCTAssertEqual(
            legacyReadableRecord.release.assets[0].browserDownloadURL,
            release.assets[0].downloadURL
        )
        let cached = try XCTUnwrap(policy.cachedRelease(for: repository))
        XCTAssertEqual(cached.release, release)
        XCTAssertTrue(policy.isFresh(cached, at: checkedAt.addingTimeInterval(86_399)))
        XCTAssertFalse(policy.isFresh(cached, at: checkedAt.addingTimeInterval(86_400)))

        policy.recordAttempt(at: checkedAt)
        XCTAssertFalse(policy.canMakeRequest(at: checkedAt.addingTimeInterval(59)))
        XCTAssertTrue(policy.canMakeRequest(at: checkedAt.addingTimeInterval(60)))
        policy.recordServerRetry(at: checkedAt.addingTimeInterval(120))
        XCTAssertEqual(
            policy.nextAllowedRequestDate(at: checkedAt.addingTimeInterval(60)),
            checkedAt.addingTimeInterval(120)
        )
        XCTAssertEqual(
            policy.localRetryDate(after: checkedAt),
            checkedAt.addingTimeInterval(60)
        )
    }

    func testCheckPolicyReadsTheExistingGitHubShapedCacheRecord() throws {
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let release = UpdateTestFixtures.release(version: "0.2.0")
        let asset = release.assets[0]
        let legacyRecord = LegacyCachedReleaseRecord(
            repositoryOwner: repository.owner,
            repositoryName: repository.name,
            checkedAt: Date(timeIntervalSince1970: 1_000),
            release: LegacyRelease(
                tagName: release.tagName,
                draft: release.draft,
                prerelease: release.prerelease,
                assets: [LegacyAsset(
                    name: asset.name,
                    contentType: asset.contentType,
                    size: asset.size,
                    digest: asset.digest,
                    browserDownloadURL: asset.downloadURL
                )]
            )
        )
        defaults.set(
            try PropertyListEncoder().encode(legacyRecord),
            forKey: "Update.cachedRelease.v1"
        )
        let policy = UpdateCheckPolicy(
            defaults: defaults,
            automaticCheckInterval: 24 * 60 * 60,
            manualCheckCooldown: 60
        )

        XCTAssertEqual(policy.cachedRelease(for: repository)?.release, release)
    }

    @MainActor
    func testControllerChecksSilentlyAndUsesThe24HourCache() async throws {
        let responseData = Data(UpdateTestFixtures.releaseJSON(version: "0.1.0").utf8)
        let requestCount = LockedBox(0)
        URLProtocolStub.handler = { request in
            requestCount.set(requestCount.value + 1)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                responseData
            )
        }
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let controller = makeController(defaults: defaults)
        let completed = expectation(description: "update check completed")
        var observedStatuses: [UpdateStatus] = []
        var fulfilled = false
        _ = controller.observeStatus { status in
            observedStatuses.append(status)
            if !fulfilled, case .upToDate = status.phase, !status.isChecking {
                fulfilled = true
                completed.fulfill()
            }
        }

        controller.refreshIfNeeded()
        await fulfillment(of: [completed], timeout: 1)
        controller.refreshIfNeeded()

        XCTAssertEqual(requestCount.value, 1)
        XCTAssertTrue(observedStatuses.contains(where: { $0.isChecking }))
        XCTAssertFalse(observedStatuses.contains { $0.manualCheckFeedback != .none })
        XCTAssertEqual(controller.status.phase, .upToDate(version: SemanticVersion("0.1.0")!))

        let secondController = makeController(defaults: defaults)
        secondController.refreshIfNeeded()
        XCTAssertEqual(
            secondController.status.phase,
            .upToDate(version: SemanticVersion("0.1.0")!)
        )
        XCTAssertEqual(requestCount.value, 1)
    }

    @MainActor
    func testManualCheckBypassesCacheButHonors60SecondCooldown() async throws {
        let responseData = Data(UpdateTestFixtures.releaseJSON(version: "0.1.0").utf8)
        let requestCount = LockedBox(0)
        URLProtocolStub.handler = { request in
            requestCount.set(requestCount.value + 1)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                responseData
            )
        }
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let currentDate = LockedBox(Date(timeIntervalSince1970: 1_000))
        let controller = makeController(defaults: defaults, now: { currentDate.value })
        let firstCheck = expectation(description: "first check")
        var firstFulfilled = false
        _ = controller.observeStatus { status in
            if !firstFulfilled, case .upToDate = status.phase, !status.isChecking {
                firstFulfilled = true
                firstCheck.fulfill()
            }
        }

        controller.refreshIfNeeded()
        await fulfillment(of: [firstCheck], timeout: 1)
        controller.checkAgain()
        XCTAssertEqual(requestCount.value, 1)
        XCTAssertNotNil(controller.status.nextManualCheckAt)

        currentDate.set(Date(timeIntervalSince1970: 1_061))
        let secondCheck = expectation(description: "manual check")
        var sawSecondRequest = false
        var sawManualChecking = false
        _ = controller.observeStatus { status in
            if status.manualCheckFeedback == .checking {
                sawManualChecking = true
            }
            if requestCount.value == 2, !status.isChecking, !sawSecondRequest {
                sawSecondRequest = true
                secondCheck.fulfill()
            }
        }
        controller.checkAgain()
        await fulfillment(of: [secondCheck], timeout: 1)
        XCTAssertEqual(requestCount.value, 2)
        XCTAssertTrue(sawManualChecking)
        XCTAssertEqual(controller.status.manualCheckFeedback, .completed)
    }

    @MainActor
    func testServerRetryAfterPersistsAcrossControllers() async throws {
        let requestCount = LockedBox(0)
        URLProtocolStub.handler = { request in
            requestCount.set(requestCount.value + 1)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "120"]
                )!,
                Data()
            )
        }
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let currentDate = Date(timeIntervalSince1970: 1_000)
        let controller = makeController(defaults: defaults, now: { currentDate })
        let limited = expectation(description: "rate limited")
        var fulfilled = false
        _ = controller.observeStatus { status in
            if !fulfilled, case .failed = status.phase, !status.isChecking {
                fulfilled = true
                limited.fulfill()
            }
        }

        controller.refreshIfNeeded()
        await fulfillment(of: [limited], timeout: 1)
        XCTAssertEqual(requestCount.value, 1)
        XCTAssertEqual(controller.status.nextManualCheckAt, currentDate.addingTimeInterval(120))

        let secondController = makeController(defaults: defaults, now: { currentDate })
        secondController.refreshIfNeeded()
        XCTAssertEqual(requestCount.value, 1)
        guard case let .failed(_, _, retryAt, _) = secondController.status.phase else {
            return XCTFail("Expected a persisted rate-limit failure")
        }
        XCTAssertEqual(retryAt, currentDate.addingTimeInterval(120))
    }

    @MainActor
    func testControllerWaitsForUserBeforeDownloading() async throws {
        let releaseData = Data(UpdateTestFixtures.releaseJSON(version: "0.2.0").utf8)
        let dmgData = Data("abc".utf8)
        URLProtocolStub.handler = { request in
            if request.url?.host == "api.github.com" {
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    releaseData
                )
            }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "application/x-apple-diskimage",
                        "Content-Length": "\(dmgData.count)"
                    ]
                )!,
                dmgData
            )
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MD2PNGControllerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let openedURLs = LockedBox<[URL]>([])
        let revealedURLs = LockedBox<[URL]>([])
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let controller = UpdateController(
            service: UpdateService(
                session: UpdateTestFixtures.stubbedSession(),
                cacheDirectory: directory
            ),
            channel: { .stableGitHubReleases(repository: self.repository) },
            installedVersion: { "0.1.0" },
            openFile: {
                openedURLs.set(openedURLs.value + [$0])
                return true
            },
            revealFile: {
                revealedURLs.set(revealedURLs.value + [$0])
            },
            defaults: defaults
        )
        let updateFound = expectation(description: "update found")
        let completed = expectation(description: "DMG opened")
        var observedStatuses: [UpdateStatus] = []
        var foundFulfilled = false
        var completedFulfilled = false
        _ = controller.observeStatus { status in
            observedStatuses.append(status)
            if !foundFulfilled, case .updateAvailable = status.phase {
                foundFulfilled = true
                updateFound.fulfill()
            }
            if !completedFulfilled, case .readyToInstall = status.phase {
                completedFulfilled = true
                completed.fulfill()
            }
        }

        controller.refreshIfNeeded()
        await fulfillment(of: [updateFound], timeout: 1)
        XCTAssertTrue(openedURLs.value.isEmpty)

        controller.downloadAvailableUpdate()
        await fulfillment(of: [completed], timeout: 1)

        XCTAssertTrue(observedStatuses.contains {
            if case .downloading = $0.phase { return true }
            return false
        })
        XCTAssertTrue(observedStatuses.contains {
            if case .verifying = $0.phase { return true }
            return false
        })
        XCTAssertTrue(observedStatuses.contains {
            if case .opening = $0.phase { return true }
            return false
        })
        guard case let .readyToInstall(update, fileURL) = controller.status.phase else {
            return XCTFail("Expected the downloaded DMG to remain available")
        }
        XCTAssertEqual(update.version, SemanticVersion("0.2.0")!)
        XCTAssertEqual(fileURL.lastPathComponent, update.assetName)
        XCTAssertEqual(openedURLs.value.map(\.lastPathComponent), [fileURL.lastPathComponent])

        controller.refreshIfNeeded()
        XCTAssertEqual(controller.status.phase, .readyToInstall(update: update, fileURL: fileURL))

        controller.revealDownloadedUpdate()
        XCTAssertEqual(revealedURLs.value, [fileURL])

        controller.openDownloadedUpdate()
        XCTAssertEqual(
            openedURLs.value.map(\.lastPathComponent),
            [fileURL.lastPathComponent, fileURL.lastPathComponent]
        )

        try FileManager.default.removeItem(at: fileURL)
        controller.openDownloadedUpdate()
        guard case let .failed(message, _, _, availableUpdate) = controller.status.phase else {
            return XCTFail("Expected a missing cached DMG to become retryable")
        }
        XCTAssertEqual(message, UpdateError.openFailed.localizedDescription)
        XCTAssertEqual(availableUpdate, update)
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

        controller.refreshIfNeeded()
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

        guard case let .failed(message, releasesURL, _, _) = controller.status.phase else {
            return XCTFail("Expected an incompatible-update failure")
        }
        XCTAssertTrue(message.contains("newer version of macOS"))
        XCTAssertEqual(releasesURL, repository.releasesURL)
        XCTAssertEqual(driver.downloadRequests, [])
    }

    @MainActor
    private func makeController(
        defaults: UserDefaults,
        now: @escaping () -> Date = Date.init
    ) -> UpdateController {
        UpdateController(
            service: UpdateService(session: UpdateTestFixtures.stubbedSession()),
            channel: { .stableGitHubReleases(repository: self.repository) },
            installedVersion: { "0.1.0" },
            defaults: defaults,
            now: now
        )
    }

    private struct LegacyCachedReleaseRecord: Codable {
        let repositoryOwner: String
        let repositoryName: String
        let checkedAt: Date
        let release: LegacyRelease
    }

    private struct LegacyRelease: Codable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [LegacyAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft
            case prerelease
            case assets
        }
    }

    private struct LegacyAsset: Codable {
        let name: String
        let contentType: String
        let size: Int64
        let digest: String?
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case contentType = "content_type"
            case size
            case digest
            case browserDownloadURL = "browser_download_url"
        }
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
    var completesDeferralImmediately = true
    private var deferCompletion: (@MainActor () -> Void)?

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
        eventHandler?(event)
    }

    func completeDeferral() {
        let completion = deferCompletion
        deferCompletion = nil
        completion?()
    }
}
