import Foundation
import XCTest
@testable import MD2PNG

final class UpdateChannelTests: XCTestCase {
    private let projectURL = URL(string: "https://github.com/guangyya/md2png")!

    func testDebugBuildDisablesUpdatesEvenWithAProductionRepository() {
        let channel = UpdateChannel.resolve(
            buildConfiguration: .debug,
            projectURL: projectURL
        )

        XCTAssertEqual(channel, .disabled)
        XCTAssertNil(channel.repository)
        XCTAssertFalse(channel.allowsUpdateChecks)
    }

    func testReleaseBuildUsesTheStableGitHubReleasesChannel() throws {
        let channel = UpdateChannel.resolve(
            buildConfiguration: .release,
            projectURL: projectURL
        )
        let repository = try XCTUnwrap(channel.repository)

        XCTAssertEqual(
            channel,
            .stableGitHubReleases(repository: repository)
        )
        XCTAssertEqual(repository.owner, "guangyya")
        XCTAssertEqual(repository.name, "md2png")
        XCTAssertEqual(repository.latestReleaseAPIURL.host, "api.github.com")
        XCTAssertEqual(
            repository.latestReleaseAPIURL.path,
            "/repos/guangyya/md2png/releases/latest"
        )
        XCTAssertTrue(channel.allowsUpdateChecks)
    }

    func testReleaseBuildDisablesUpdatesWithoutAValidGitHubRepository() {
        XCTAssertEqual(
            UpdateChannel.resolve(
                buildConfiguration: .release,
                projectURL: URL(string: "https://example.com/guangyya/md2png")
            ),
            .disabled
        )
        XCTAssertEqual(
            UpdateChannel.resolve(buildConfiguration: .release, projectURL: nil),
            .disabled
        )
    }

    func testOnlyStableChannelAllowsItsExactReleaseArtifact() throws {
        let repository = try XCTUnwrap(GitHubRepository(projectURL: projectURL))
        let update = UpdateTestFixtures.availableUpdate()
        let stableChannel = UpdateChannel.stableGitHubReleases(repository: repository)

        XCTAssertFalse(UpdateChannel.disabled.allowsDownload(update))
        XCTAssertTrue(stableChannel.allowsDownload(update))

        let wrongRepository = try XCTUnwrap(GitHubRepository(
            projectURL: URL(string: "https://github.com/guangyya/another-app")!
        ))
        XCTAssertFalse(
            UpdateChannel.stableGitHubReleases(repository: wrongRepository)
                .allowsDownload(update)
        )

        let wrongArtifact = AvailableUpdate(
            version: update.version,
            tagName: update.tagName,
            assetName: "nightly.dmg",
            downloadURL: update.downloadURL,
            size: update.size,
            sha256: update.sha256
        )
        XCTAssertFalse(stableChannel.allowsDownload(wrongArtifact))
    }
}
