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

    func testDebugReadyMockUsesRecoverablePublishedAssetMetadata() throws {
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
        XCTAssertEqual(update.size, 3_312_367)
        XCTAssertEqual(
            update.sha256,
            "40fc785583a7cfaf1e476ae8649d2eb4e8461b49680e9a0fddfc35075b79bed7"
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
