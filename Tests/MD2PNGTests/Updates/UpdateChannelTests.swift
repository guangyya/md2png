import Foundation
import XCTest
@testable import MD2PNG

final class UpdateChannelTests: XCTestCase {
    private let projectURL = URL(string: "https://github.com/guangyya/md2png")!

    func testMissingChannelDisablesUpdatesEvenWithAProductionRepository() {
        let channel = UpdateChannel.resolve(
            configuredValue: nil,
            projectURL: projectURL
        )

        XCTAssertEqual(channel, .disabled)
        XCTAssertNil(channel.repository)
        XCTAssertFalse(channel.allowsUpdateChecks)
    }

    func testExplicitStableChannelUsesGitHubReleases() throws {
        let channel = UpdateChannel.resolve(
            configuredValue: "stable",
            projectURL: projectURL
        )
        let repository = try XCTUnwrap(channel.repository)

        XCTAssertEqual(
            channel,
            .stableGitHubReleases(repository: repository)
        )
        XCTAssertEqual(repository.owner, "guangyya")
        XCTAssertEqual(repository.name, "md2png")
        XCTAssertEqual(repository.releasesURL.host, "github.com")
        XCTAssertEqual(repository.appcastURL.lastPathComponent, "appcast.xml")
        XCTAssertTrue(channel.allowsUpdateChecks)
    }

    func testStableChannelDisablesUpdatesWithoutAValidGitHubRepository() {
        XCTAssertEqual(
            UpdateChannel.resolve(
                configuredValue: "stable",
                projectURL: URL(string: "https://example.com/guangyya/md2png")
            ),
            .disabled
        )
        XCTAssertEqual(
            UpdateChannel.resolve(configuredValue: "stable", projectURL: nil),
            .disabled
        )
    }

    func testUnknownAndNightlyChannelsFailClosed() {
        for configuredValue in ["nightly", "unknown", "STABLE", " stable "] {
            XCTAssertEqual(
                UpdateChannel.resolve(
                    configuredValue: configuredValue,
                    projectURL: projectURL
                ),
                .disabled,
                "Unexpected stable channel for \(configuredValue)"
            )
        }
    }
}
