import Foundation
import XCTest
@testable import MD2PNG

final class UpdateTests: XCTestCase {
    private let repository = GitHubRepository(
        projectURL: URL(string: "https://github.com/guangyya/md2png")!
    )!

    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testSemanticVersionsCompareNumericComponents() throws {
        let oneNine = try XCTUnwrap(SemanticVersion("1.9.0"))
        let oneTen = try XCTUnwrap(SemanticVersion("v1.10.0"))

        XCTAssertLessThan(oneNine, oneTen)
        XCTAssertEqual(SemanticVersion(" 2.0.3 ")?.description, "2.0.3")
        XCTAssertNil(SemanticVersion("1.2"))
        XCTAssertNil(SemanticVersion("1.2.3-beta.1"))
        XCTAssertNil(SemanticVersion("1.02.3"))
        XCTAssertNil(SemanticVersion("V1.2.3"))
        XCTAssertNil(SemanticVersion("١.٢.٣"))
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

    func testGitHubRepositoryBuildsLatestReleaseEndpoint() throws {
        let repository = try XCTUnwrap(GitHubRepository(
            projectURL: URL(string: "https://github.com/guangyya/md2png/")!
        ))

        XCTAssertEqual(repository.owner, "guangyya")
        XCTAssertEqual(repository.name, "md2png")
        XCTAssertEqual(
            repository.latestReleaseAPIURL.absoluteString,
            "https://api.github.com/repos/guangyya/md2png/releases/latest"
        )
        XCTAssertEqual(
            repository.releasesURL.absoluteString,
            "https://github.com/guangyya/md2png/releases"
        )
    }

    func testGitHubRepositoryRejectsNonGitHubOrAmbiguousURLs() {
        XCTAssertNil(GitHubRepository(projectURL: URL(string: "https://example.com/a/b")!))
        XCTAssertNil(GitHubRepository(projectURL: URL(string: "http://github.com/a/b")!))
        XCTAssertNil(GitHubRepository(projectURL: URL(string: "https://github.com/a/b/issues")!))
        XCTAssertNil(GitHubRepository(projectURL: URL(string: "https://github.com/a/b?q=1")!))
        XCTAssertNil(GitHubRepository(projectURL: URL(string: "https://github.com/a/b%2Fc")!))
    }

    func testReleaseJSONResolvesExpectedVersionedDMG() throws {
        let release = try decodeRelease(version: "0.2.0")
        let result = try UpdateReleaseResolver.resolve(
            release: release,
            repository: repository,
            installedVersionString: "0.1.0"
        )

        guard case let .updateAvailable(update) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(update.version.description, "0.2.0")
        XCTAssertEqual(update.assetName, "md2png-0.2.0-macOS-arm64-developer-id.dmg")
        XCTAssertEqual(update.size, 3)
        XCTAssertEqual(
            update.sha256,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testEqualAndOlderLatestVersionsAreUpToDate() throws {
        for latest in ["0.1.0", "0.0.9"] {
            let result = try UpdateReleaseResolver.resolve(
                release: decodeRelease(version: latest),
                repository: repository,
                installedVersionString: "0.1.0"
            )
            guard case .upToDate = result else {
                return XCTFail("Expected \(latest) to be up to date")
            }
        }
    }

    func testReleaseResolverRejectsUnsupportedReleaseStatesAndTags() throws {
        XCTAssertThrowsError(try UpdateReleaseResolver.resolve(
            release: decodeRelease(version: "0.2.0", draft: true),
            repository: repository,
            installedVersionString: "0.1.0"
        )) { XCTAssertEqual($0 as? UpdateError, .invalidRelease) }

        XCTAssertThrowsError(try UpdateReleaseResolver.resolve(
            release: decodeRelease(version: "0.2.0", prerelease: true),
            repository: repository,
            installedVersionString: "0.1.0"
        )) { XCTAssertEqual($0 as? UpdateError, .invalidRelease) }

        XCTAssertThrowsError(try UpdateReleaseResolver.resolve(
            release: decodeRelease(version: "nightly"),
            repository: repository,
            installedVersionString: "0.1.0"
        )) { XCTAssertEqual($0 as? UpdateError, .invalidReleaseVersion) }
    }

    func testReleaseResolverRejectsMissingDuplicateAndInvalidAssets() throws {
        let missing = GitHubRelease(
            tagName: "v0.2.0",
            draft: false,
            prerelease: false,
            assets: []
        )
        XCTAssertThrowsError(try resolve(missing)) {
            XCTAssertEqual($0 as? UpdateError, .missingAsset)
        }

        let valid = try decodeRelease(version: "0.2.0")
        let duplicate = GitHubRelease(
            tagName: valid.tagName,
            draft: false,
            prerelease: false,
            assets: [valid.assets[0], valid.assets[0]]
        )
        XCTAssertThrowsError(try resolve(duplicate)) {
            XCTAssertEqual($0 as? UpdateError, .duplicateAsset)
        }

        var json = releaseJSON(version: "0.2.0")
        json = json.replacingOccurrences(
            of: "application/x-apple-diskimage",
            with: "application/octet-stream"
        )
        XCTAssertThrowsError(try resolve(decodeRelease(json))) {
            XCTAssertEqual($0 as? UpdateError, .invalidAssetMetadata)
        }

        json = releaseJSON(version: "0.2.0").replacingOccurrences(
            of: "https://github.com/",
            with: "http://github.com/"
        )
        XCTAssertThrowsError(try resolve(decodeRelease(json))) {
            XCTAssertEqual($0 as? UpdateError, .insecureDownloadURL)
        }
    }

    func testFileVerificationChecksSizeAndSHA256() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MD2PNGUpdateTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("test.dmg")
        try Data("abc".utf8).write(to: fileURL)

        let update = AvailableUpdate(
            version: SemanticVersion("0.2.0")!,
            tagName: "v0.2.0",
            assetName: "test.dmg",
            downloadURL: URL(string: "https://github.com/a/b/releases/download/v0.2.0/test.dmg")!,
            size: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertNoThrow(try UpdateService.verifyFile(at: fileURL, update: update))

        let wrongSize = AvailableUpdate(
            version: update.version,
            tagName: update.tagName,
            assetName: update.assetName,
            downloadURL: update.downloadURL,
            size: 4,
            sha256: update.sha256
        )
        XCTAssertThrowsError(try UpdateService.verifyFile(at: fileURL, update: wrongSize)) {
            XCTAssertEqual($0 as? UpdateError, .fileSizeMismatch)
        }

        let wrongDigest = AvailableUpdate(
            version: update.version,
            tagName: update.tagName,
            assetName: update.assetName,
            downloadURL: update.downloadURL,
            size: update.size,
            sha256: String(repeating: "0", count: 64)
        )
        XCTAssertThrowsError(try UpdateService.verifyFile(at: fileURL, update: wrongDigest)) {
            XCTAssertEqual($0 as? UpdateError, .digestMismatch)
        }
    }

    func testUpdateServiceChecksPublicReleaseJSONWithExpectedHeaders() async throws {
        let capturedRequest = LockedBox<URLRequest?>(nil)
        let responseData = Data(releaseJSON(version: "0.2.0").utf8)
        URLProtocolStub.handler = { request in
            capturedRequest.set(request)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "application/json",
                        "X-RateLimit-Remaining": "42",
                        "X-RateLimit-Reset": "2000"
                    ]
                )!,
                responseData
            )
        }
        let service = UpdateService(session: stubbedSession())

        let result = try await service.checkForUpdate(
            repository: repository,
            installedVersion: "0.1.0"
        )

        guard case .updateAvailable = result.result else {
            return XCTFail("Expected an update")
        }
        let request = try XCTUnwrap(capturedRequest.value)
        XCTAssertEqual(request.url, repository.latestReleaseAPIURL)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "md2png-update-check/0.1.0")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(result.rateLimit.remaining, 42)
        XCTAssertEqual(result.rateLimit.resetAt, Date(timeIntervalSince1970: 2_000))
    }

    @MainActor
    func testUpdateControllerChecksSilentlyAndUsesThe24HourCache() async throws {
        let responseData = Data(releaseJSON(version: "0.1.0").utf8)
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
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let controller = UpdateController(
            service: UpdateService(session: stubbedSession()),
            installedVersion: { "0.1.0" },
            repository: { self.repository },
            defaults: defaults
        )
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
        XCTAssertFalse(observedStatuses.contains {
            $0.manualCheckFeedback != .none
        })
        XCTAssertEqual(controller.status.phase, .upToDate(version: SemanticVersion("0.1.0")!))

        let secondController = UpdateController(
            service: UpdateService(session: stubbedSession()),
            installedVersion: { "0.1.0" },
            repository: { self.repository },
            defaults: defaults
        )
        secondController.refreshIfNeeded()
        XCTAssertEqual(secondController.status.phase, .upToDate(version: SemanticVersion("0.1.0")!))
        XCTAssertEqual(requestCount.value, 1)
    }

    @MainActor
    func testManualCheckBypassesCacheButHonors60SecondCooldown() async throws {
        let responseData = Data(releaseJSON(version: "0.1.0").utf8)
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
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let currentDate = LockedBox(Date(timeIntervalSince1970: 1_000))
        let controller = UpdateController(
            service: UpdateService(session: stubbedSession()),
            installedVersion: { "0.1.0" },
            repository: { self.repository },
            defaults: defaults,
            now: { currentDate.value }
        )
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
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let currentDate = Date(timeIntervalSince1970: 1_000)
        let controller = UpdateController(
            service: UpdateService(session: stubbedSession()),
            installedVersion: { "0.1.0" },
            repository: { self.repository },
            defaults: defaults,
            now: { currentDate }
        )
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
        XCTAssertEqual(
            controller.status.nextManualCheckAt,
            currentDate.addingTimeInterval(120)
        )

        let secondController = UpdateController(
            service: UpdateService(session: stubbedSession()),
            installedVersion: { "0.1.0" },
            repository: { self.repository },
            defaults: defaults,
            now: { currentDate }
        )
        secondController.refreshIfNeeded()
        XCTAssertEqual(requestCount.value, 1)
        guard case let .failed(_, _, retryAt, _) = secondController.status.phase else {
            return XCTFail("Expected a persisted rate-limit failure")
        }
        XCTAssertEqual(retryAt, currentDate.addingTimeInterval(120))
    }

    @MainActor
    func testUpdateControllerWaitsForUserBeforeDownloading() async throws {
        let releaseData = Data(releaseJSON(version: "0.2.0").utf8)
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
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let controller = UpdateController(
            service: UpdateService(
                session: stubbedSession(),
                cacheDirectory: directory
            ),
            installedVersion: { "0.1.0" },
            repository: { self.repository },
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
        XCTAssertEqual(fileURL.lastPathComponent, "md2png-0.2.0-macOS-arm64-developer-id.dmg")
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

    func testUpdateServiceReportsHTTPAndMalformedJSONFailures() async throws {
        URLProtocolStub.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        let service = UpdateService(session: stubbedSession())
        let currentDate = Date(timeIntervalSince1970: 1_000)
        do {
            _ = try await service.checkForUpdate(
                repository: repository,
                installedVersion: "0.1.0",
                now: currentDate
            )
            XCTFail("Expected HTTP failure")
        } catch {
            XCTAssertEqual(
                error as? UpdateError,
                .rateLimited(retryAt: currentDate.addingTimeInterval(60))
            )
        }

        URLProtocolStub.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("not-json".utf8)
            )
        }
        do {
            _ = try await service.checkForUpdate(
                repository: repository,
                installedVersion: "0.1.0"
            )
            XCTFail("Expected malformed JSON failure")
        } catch {
            XCTAssertEqual(error as? UpdateError, .invalidServerResponse)
        }
    }

    func testUpdateServiceDownloadsVerifiesAndCachesDMG() async throws {
        let data = Data("abc".utf8)
        URLProtocolStub.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "application/x-apple-diskimage",
                        "Content-Length": "\(data.count)"
                    ]
                )!,
                data
            )
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MD2PNGDownloadTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = UpdateService(session: stubbedSession(), cacheDirectory: directory)
        let sawCompleteProgress = LockedBox(false)
        let sawVerification = LockedBox(false)
        let update = AvailableUpdate(
            version: SemanticVersion("0.2.0")!,
            tagName: "v0.2.0",
            assetName: "md2png-0.2.0-macOS-arm64-developer-id.dmg",
            downloadURL: URL(
                string: "https://github.com/guangyya/md2png/releases/download/v0.2.0/md2png-0.2.0-macOS-arm64-developer-id.dmg"
            )!,
            size: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )

        let result = try await service.download(update) { event in
            switch event {
            case let .progress(received, expected):
                if received == 3, expected == 3 { sawCompleteProgress.set(true) }
            case .verifying:
                sawVerification.set(true)
            }
        }

        XCTAssertEqual(result.lastPathComponent, update.assetName)
        XCTAssertEqual(try Data(contentsOf: result), data)
        XCTAssertTrue(sawCompleteProgress.value)
        XCTAssertTrue(sawVerification.value)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains(where: { $0.hasPrefix(".md2png-update-") })
        )
    }

    func testLivePublicReleaseCanBeResolvedAndDownloaded() async throws {
        guard ProcessInfo.processInfo.environment["MD2PNG_LIVE_UPDATE_TEST"] == "1" else {
            throw XCTSkip("Set MD2PNG_LIVE_UPDATE_TEST=1 to exercise the public GitHub release")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MD2PNGLiveUpdateTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = UpdateService(cacheDirectory: directory)

        let result = try await service.checkForUpdate(
            repository: repository,
            installedVersion: "0.0.0"
        )
        guard case let .updateAvailable(update) = result.result else {
            return XCTFail("Expected the published release to be newer than 0.0.0")
        }

        let fileURL = try await service.download(update) { _ in }
        XCTAssertEqual(fileURL.lastPathComponent, update.assetName)
        XCTAssertNoThrow(try UpdateService.verifyFile(at: fileURL, update: update))
    }

    private func resolve(_ release: GitHubRelease) throws -> UpdateCheckResult {
        try UpdateReleaseResolver.resolve(
            release: release,
            repository: repository,
            installedVersionString: "0.1.0"
        )
    }

    private func decodeRelease(
        version: String,
        draft: Bool = false,
        prerelease: Bool = false
    ) throws -> GitHubRelease {
        try decodeRelease(releaseJSON(version: version, draft: draft, prerelease: prerelease))
    }

    private func decodeRelease(_ json: String) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
    }

    private func releaseJSON(
        version: String,
        draft: Bool = false,
        prerelease: Bool = false
    ) -> String {
        let normalizedVersion = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let tag = version.hasPrefix("v") ? version : "v\(version)"
        let assetName = "md2png-\(normalizedVersion)-macOS-arm64-developer-id.dmg"
        return """
        {
          "tag_name": "\(tag)",
          "draft": \(draft),
          "prerelease": \(prerelease),
          "assets": [{
            "name": "\(assetName)",
            "content_type": "application/x-apple-diskimage",
            "size": 3,
            "digest": "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "browser_download_url": "https://github.com/guangyya/md2png/releases/download/\(tag)/\(assetName)"
          }]
        }
        """
    }

    private func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "MD2PNGUpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(suiteName, forKey: "TestSuiteName")
        return defaults
    }

    private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
        defaults.string(forKey: "TestSuiteName")!
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
