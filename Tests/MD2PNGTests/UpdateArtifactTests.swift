import Foundation
import XCTest
@testable import MD2PNG

final class UpdateArtifactTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testVerifierChecksSizeAndSHA256() throws {
        let directory = temporaryDirectory(named: "MD2PNGVerifierTests")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("test.dmg")
        try Data("abc".utf8).write(to: fileURL)

        let verifier = UpdateArtifactVerifier()
        let update = UpdateTestFixtures.availableUpdate()
        XCTAssertNoThrow(try verifier.verifyFile(at: fileURL, update: update))

        let wrongSize = AvailableUpdate(
            version: update.version,
            tagName: update.tagName,
            assetName: update.assetName,
            downloadURL: update.downloadURL,
            size: 4,
            sha256: update.sha256
        )
        XCTAssertThrowsError(try verifier.verifyFile(at: fileURL, update: wrongSize)) {
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
        XCTAssertThrowsError(try verifier.verifyFile(at: fileURL, update: wrongDigest)) {
            XCTAssertEqual($0 as? UpdateError, .digestMismatch)
        }
    }

    func testCachePreparesDirectoryAndRemovesOnlyPartialArtifacts() throws {
        let directory = temporaryDirectory(named: "MD2PNGCacheTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = UpdateArtifactCache(directory: directory)
        let update = UpdateTestFixtures.availableUpdate()

        let destination = try cache.destination(for: update)
        let partial = directory.appendingPathComponent(".md2png-update-stale.download")
        let unrelated = directory.appendingPathComponent("keep.txt")
        try Data("cached".utf8).write(to: destination)
        try Data("partial".utf8).write(to: partial)
        try Data("keep".utf8).write(to: unrelated)

        XCTAssertEqual(try cache.prepareForDownload(), directory)
        XCTAssertTrue(cache.contains(destination))
        XCTAssertFalse(cache.contains(partial))
        XCTAssertTrue(cache.contains(unrelated))
    }

    func testDownloaderVerifiesAndReusesCachedDMG() async throws {
        let data = Data("abc".utf8)
        let requestCount = LockedBox(0)
        let capturedRequest = LockedBox<URLRequest?>(nil)
        URLProtocolStub.handler = { request in
            requestCount.set(requestCount.value + 1)
            capturedRequest.set(request)
            return (
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
        let directory = temporaryDirectory(named: "MD2PNGDownloadTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloader = UpdateArtifactDownloader(
            session: UpdateTestFixtures.stubbedSession(),
            cache: UpdateArtifactCache(directory: directory)
        )
        let sawCompleteProgress = LockedBox(false)
        let sawVerification = LockedBox(false)
        let update = UpdateTestFixtures.availableUpdate()

        let result = try await downloader.download(update) { event in
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
        XCTAssertEqual(requestCount.value, 1)
        XCTAssertEqual(
            capturedRequest.value?.value(forHTTPHeaderField: "User-Agent"),
            "md2png-update-download/0.2.0"
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains(where: { $0.hasPrefix(".md2png-update-") })
        )

        let cachedResult = try await downloader.download(update) { _ in }
        XCTAssertEqual(cachedResult, result)
        XCTAssertEqual(requestCount.value, 1)
    }

    private func temporaryDirectory(named prefix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
