import Foundation
import XCTest
@testable import MD2PNG

final class UpdateDomainTests: XCTestCase {
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

    func testGitHubRepositoryBuildsReleaseAndAppcastURLs() throws {
        let repository = try XCTUnwrap(GitHubRepository(
            projectURL: URL(string: "https://github.com/guangyya/md2png/")!
        ))

        XCTAssertEqual(repository.owner, "guangyya")
        XCTAssertEqual(repository.name, "md2png")
        XCTAssertEqual(
            repository.releasesURL.absoluteString,
            "https://github.com/guangyya/md2png/releases"
        )
        XCTAssertEqual(
            repository.appcastURL.absoluteString,
            "https://github.com/guangyya/md2png/releases/latest/download/appcast.xml"
        )
    }

    func testGitHubRepositoryRejectsNonGitHubOrAmbiguousURLs() {
        XCTAssertNil(GitHubRepository(projectURL: URL(string: "https://example.com/a/b")!))
        XCTAssertNil(GitHubRepository(projectURL: URL(string: "http://github.com/a/b")!))
        XCTAssertNil(GitHubRepository(projectURL: URL(string: "https://github.com/a/b/issues")!))
        XCTAssertNil(GitHubRepository(projectURL: URL(string: "https://github.com/a/b?q=1")!))
        XCTAssertNil(GitHubRepository(projectURL: URL(string: "https://github.com/a/b%2Fc")!))
    }
}
