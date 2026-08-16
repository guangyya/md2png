import Foundation
import XCTest
@testable import MD2PNG

final class SuggestedPNGFilenameTests: XCTestCase {
    func testPrefersTheFirstHeadingAndCleansInlineMarkdown() {
        let markdown = """
        Intro paragraph that should not win.

        # **Release Plan**: [August](https://example.com) #
        """

        XCTAssertEqual(
            SuggestedPNGFilename.make(from: markdown),
            "Release Plan August.png"
        )
    }

    func testRecognizesSetextHeadingsAndPreservesUnicode() {
        let markdown = "版本发布计划 / 八月\r\n==================\r\n\r\nDetails"

        XCTAssertEqual(
            SuggestedPNGFilename.make(from: markdown),
            "版本发布计划 八月.png"
        )
    }

    func testIgnoresHeadingsInsideFencedCodeBlocks() {
        let markdown = """
        ```markdown
        # Not the document title
        ```

        ## Actual Title
        """

        XCTAssertEqual(
            SuggestedPNGFilename.make(from: markdown),
            "Actual Title.png"
        )
    }

    func testIgnoresYAMLFrontMatterAndCleansDecodedReservedCharacters() {
        let markdown = """
        ---
        title: Internal Metadata
        ---

        # Shipping &lt;Plan&gt;
        """

        XCTAssertEqual(
            SuggestedPNGFilename.make(from: markdown),
            "Shipping Plan.png"
        )
    }

    func testFallsBackToTheFirstMeaningfulBodyLine() {
        let markdown = """
        ---

        - [Project update](https://example.com): shipped today.
        """

        XCTAssertEqual(
            SuggestedPNGFilename.make(from: markdown),
            "Project update shipped today.png"
        )
    }

    func testFallsBackToATimestampWhenNoTextCanBeExtracted() {
        XCTAssertEqual(
            SuggestedPNGFilename.make(
                from: "```\n# code only\n```",
                now: Date(timeIntervalSince1970: 0),
                timeZone: TimeZone(secondsFromGMT: 0)!
            ),
            "md2png-19700101-000000.png"
        )
    }

    func testLimitsTheStemWithoutSplittingExtendedCharacters() {
        let title = String(repeating: "文", count: 100)
        let filename = SuggestedPNGFilename.make(from: "# \(title)")

        XCTAssertEqual(filename.dropLast(4).count, 72)
        XCTAssertLessThanOrEqual(filename.utf8.count, 244)
        XCTAssertTrue(filename.hasSuffix(".png"))
    }

    func testLimitsLongMultibyteGraphemesToAValidFilenameByteCount() {
        let filename = SuggestedPNGFilename.make(
            from: "# \(String(repeating: "👨‍👩‍👧‍👦", count: 100))"
        )

        XCTAssertLessThanOrEqual(filename.utf8.count, 244)
        XCTAssertTrue(filename.hasSuffix(".png"))
    }
}
