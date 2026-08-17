import Foundation
import XCTest
@testable import MD2PNG

final class SeamlessUpdateTests: XCTestCase {
    func testMetadataBuilderShowsSkippedVersionsNewestFirst() throws {
        let entries = [
            entry(version: "0.8.0", build: "8", notes: "### Added\n- Current"),
            entry(version: "0.7.0", build: "7", notes: "### Fixed\n- Bridge"),
            entry(version: "0.6.0", build: "6", notes: "### Changed\n- Old")
        ]

        let update = try XCTUnwrap(SeamlessUpdateMetadataBuilder.make(
            installedVersion: "0.6.0",
            selectedBuildVersion: "8",
            entries: entries
        ))

        XCTAssertEqual(update.releaseNotes.map(\.version), ["0.8.0", "0.7.0"])
        XCTAssertEqual(update.releaseNotes[0].text, "Added\n- Current")
        XCTAssertFalse(update.historyIsTruncated)
    }

    func testMetadataBuilderMarksHistoryOutsideBoundAsTruncated() throws {
        let entries = [
            entry(version: "0.8.0", build: "8", notes: "Current"),
            entry(version: "0.7.0", build: "7", notes: "Bridge"),
            entry(version: "0.6.0", build: "6", notes: "Oldest retained")
        ]

        let update = try XCTUnwrap(SeamlessUpdateMetadataBuilder.make(
            installedVersion: "0.5.0",
            selectedBuildVersion: "8",
            entries: entries
        ))

        XCTAssertTrue(update.historyIsTruncated)
        XCTAssertEqual(update.releaseNotes.count, 3)
    }

    func testMetadataBuilderRejectsInvalidOrNonNewerSelection() {
        XCTAssertNil(SeamlessUpdateMetadataBuilder.make(
            installedVersion: "0.8.0",
            selectedBuildVersion: "8",
            entries: [entry(version: "0.8.0", build: "8", notes: "Notes")]
        ))
        XCTAssertNil(SeamlessUpdateMetadataBuilder.make(
            installedVersion: "0.7.0",
            selectedBuildVersion: "missing",
            entries: [entry(version: "0.8.0", build: "8", notes: "Notes")]
        ))
    }

    func testReleaseNotesBecomeBoundedNonInteractivePlainText() throws {
        let source = """
        ### Added
        - [Details](javascript:alert(1))
        - ![tracking](https://example.invalid/pixel.png)
        <script>fetch('https://example.invalid')</script>
        `inline code`
        """

        let notes = try XCTUnwrap(SeamlessReleaseNotesSanitizer.sanitize(source))

        XCTAssertTrue(notes.contains("Added"))
        XCTAssertTrue(notes.contains("Details"))
        XCTAssertTrue(notes.contains("tracking"))
        XCTAssertFalse(notes.contains("javascript:"))
        XCTAssertFalse(notes.contains("pixel.png"))
        XCTAssertFalse(notes.contains("<script>"))
        XCTAssertFalse(notes.contains("`"))

        let oversized = String(repeating: "x", count: 30_000)
        let bounded = try XCTUnwrap(SeamlessReleaseNotesSanitizer.sanitize(oversized))
        XCTAssertLessThanOrEqual(bounded.count, SeamlessReleaseNotesSanitizer.maximumLineCharacters)
    }

    func testFullReleaseNotesLinkMustStayOnTheConfiguredRepository() {
        let feed = URL(
            string: "https://github.com/guangyya/md2png/releases/latest/download/appcast.xml"
        )!
        let valid = URL(string: "https://github.com/guangyya/md2png/releases")!

        XCTAssertEqual(
            SeamlessUpdateLinkPolicy.trustedReleaseNotesURL(valid, feedURL: feed),
            valid
        )
        for invalid in [
            "http://github.com/guangyya/md2png/releases",
            "https://github.com/other/md2png/releases",
            "https://example.com/guangyya/md2png/releases",
            "https://github.com/guangyya/md2png/releases?clipboard=secret"
        ] {
            XCTAssertNil(SeamlessUpdateLinkPolicy.trustedReleaseNotesURL(
                URL(string: invalid),
                feedURL: feed
            ))
        }
    }

    private func entry(
        version: String,
        build: String,
        notes: String
    ) -> SeamlessUpdateAppcastEntry {
        SeamlessUpdateAppcastEntry(
            displayVersion: version,
            buildVersion: build,
            publishedAt: nil,
            contentLength: 4_200_000,
            releaseNotes: notes,
            fullReleaseNotesURL: URL(
                string: "https://github.com/guangyya/md2png/releases"
            )
        )
    }
}

@MainActor
final class UpdateRelaunchMarkerTests: XCTestCase {
    func testMatchingVersionProducesOneTimeSuccess() {
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let marker = UpdateRelaunchMarker(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_000)

        marker.mark(expectedVersion: "0.8.0", at: now)

        XCTAssertEqual(
            marker.reconcile(runningVersion: "0.8.0", at: now),
            .updated(version: "0.8.0")
        )
        XCTAssertNil(marker.reconcile(runningVersion: "0.8.0", at: now))
    }

    func testDifferentVersionReportsRealRunningStateAndClearsMarker() {
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let marker = UpdateRelaunchMarker(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_000)

        marker.mark(expectedVersion: "0.8.0", at: now)

        XCTAssertEqual(
            marker.reconcile(runningVersion: "0.7.0", at: now),
            .notUpdated(expectedVersion: "0.8.0", runningVersion: "0.7.0")
        )
        XCTAssertNil(marker.reconcile(runningVersion: "0.7.0", at: now))
    }

    func testStaleMarkerIsClearedWithoutAFalseResult() {
        let defaults = UpdateTestFixtures.makeDefaults()
        defer { UpdateTestFixtures.removeDefaults(defaults) }
        let marker = UpdateRelaunchMarker(defaults: defaults)
        let createdAt = Date(timeIntervalSince1970: 1_000)

        marker.mark(expectedVersion: "0.8.0", at: createdAt)

        XCTAssertNil(marker.reconcile(
            runningVersion: "0.7.0",
            at: createdAt.addingTimeInterval(UpdateRelaunchMarker.maximumAge + 1)
        ))
        XCTAssertNil(defaults.string(forKey: UpdateRelaunchMarker.expectedVersionKey))
    }
}
