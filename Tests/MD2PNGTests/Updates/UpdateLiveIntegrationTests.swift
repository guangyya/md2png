import Foundation
import XCTest
@testable import MD2PNG

final class UpdateLiveIntegrationTests: XCTestCase {
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
            repository: UpdateTestFixtures.repository,
            installedVersion: "0.0.0"
        )
        guard case let .updateAvailable(update) = result.result else {
            return XCTFail("Expected the published release to be newer than 0.0.0")
        }

        let fileURL = try await service.download(update) { _ in }
        XCTAssertEqual(fileURL.lastPathComponent, update.assetName)
        XCTAssertNoThrow(try UpdateArtifactVerifier().verifyFile(at: fileURL, update: update))
    }
}
