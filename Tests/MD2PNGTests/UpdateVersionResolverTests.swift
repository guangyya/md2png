import Foundation
import XCTest
@testable import MD2PNG

final class UpdateVersionResolverTests: XCTestCase {
    private let repository = UpdateTestFixtures.repository

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

    func testReleaseDomainResolvesExpectedVersionedDMGWithoutTransport() throws {
        let result = try resolve(UpdateTestFixtures.release(version: "0.2.0"))

        guard case let .updateAvailable(update) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(update.version.description, "0.2.0")
        XCTAssertEqual(update.assetName, "md2png-0.2.0-macOS-arm64-developer-id.dmg")
        XCTAssertEqual(update.size, 3)
        XCTAssertEqual(update.sha256, UpdateTestFixtures.sha256)
    }

    func testEqualAndOlderLatestVersionsAreUpToDate() throws {
        for latest in ["0.1.0", "0.0.9"] {
            guard case .upToDate = try resolve(UpdateTestFixtures.release(version: latest)) else {
                return XCTFail("Expected \(latest) to be up to date")
            }
        }
    }

    func testReleaseResolverRejectsUnsupportedReleaseStatesAndTags() throws {
        XCTAssertThrowsError(try resolve(UpdateTestFixtures.release(
            version: "0.2.0",
            draft: true
        ))) { XCTAssertEqual($0 as? UpdateError, .invalidRelease) }

        XCTAssertThrowsError(try resolve(UpdateTestFixtures.release(
            version: "0.2.0",
            prerelease: true
        ))) { XCTAssertEqual($0 as? UpdateError, .invalidRelease) }

        XCTAssertThrowsError(try resolve(UpdateTestFixtures.release(version: "nightly"))) {
            XCTAssertEqual($0 as? UpdateError, .invalidReleaseVersion)
        }
    }

    func testReleaseResolverRejectsMissingDuplicateAndInvalidAssets() throws {
        let missing = UpdateRelease(
            tagName: "v0.2.0",
            draft: false,
            prerelease: false,
            assets: []
        )
        XCTAssertThrowsError(try resolve(missing)) {
            XCTAssertEqual($0 as? UpdateError, .missingAsset)
        }

        let valid = UpdateTestFixtures.release(version: "0.2.0")
        let duplicate = UpdateRelease(
            tagName: valid.tagName,
            draft: false,
            prerelease: false,
            assets: [valid.assets[0], valid.assets[0]]
        )
        XCTAssertThrowsError(try resolve(duplicate)) {
            XCTAssertEqual($0 as? UpdateError, .duplicateAsset)
        }

        let invalidMetadata = replacingAsset(
            in: valid,
            contentType: "application/octet-stream"
        )
        XCTAssertThrowsError(try resolve(invalidMetadata)) {
            XCTAssertEqual($0 as? UpdateError, .invalidAssetMetadata)
        }

        let insecure = replacingAsset(
            in: valid,
            downloadURL: URL(string: valid.assets[0].downloadURL.absoluteString.replacingOccurrences(
                of: "https://",
                with: "http://"
            ))!
        )
        XCTAssertThrowsError(try resolve(insecure)) {
            XCTAssertEqual($0 as? UpdateError, .insecureDownloadURL)
        }
    }

    private func resolve(_ release: UpdateRelease) throws -> UpdateCheckResult {
        try UpdateReleaseResolver.resolve(
            release: release,
            repository: repository,
            installedVersionString: "0.1.0"
        )
    }

    private func replacingAsset(
        in release: UpdateRelease,
        contentType: String? = nil,
        downloadURL: URL? = nil
    ) -> UpdateRelease {
        let asset = release.assets[0]
        return UpdateRelease(
            tagName: release.tagName,
            draft: release.draft,
            prerelease: release.prerelease,
            assets: [UpdateReleaseAsset(
                name: asset.name,
                contentType: contentType ?? asset.contentType,
                size: asset.size,
                digest: asset.digest,
                downloadURL: downloadURL ?? asset.downloadURL
            )]
        )
    }
}
