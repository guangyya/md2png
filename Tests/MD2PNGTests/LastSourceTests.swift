import Foundation
import XCTest
@testable import MD2PNG

final class LastSourceTests: XCTestCase {
    func testSourceBecomesAvailableOnlyAfterSuccessfulRender() {
        var state = LastSourceState()

        XCTAssertFalse(state.isAvailable)
        XCTAssertNil(state.markdown)
        XCTAssertFalse(state.requiresConfirmation(currentClipboardChangeCount: 10))

        state.recordSuccessfulRender(
            markdown: "# First render",
            clipboardChangeCount: 10
        )

        XCTAssertTrue(state.isAvailable)
        XCTAssertEqual(state.markdown, "# First render")
        XCTAssertFalse(state.requiresConfirmation(currentClipboardChangeCount: 10))
    }

    func testFailedRenderDoesNotReplaceLastSuccessfulSource() {
        var state = LastSourceState()
        state.recordSuccessfulRender(
            markdown: "# Successful render",
            clipboardChangeCount: 20
        )

        // A failed render never calls recordSuccessfulRender.
        XCTAssertEqual(state.markdown, "# Successful render")
        XCTAssertEqual(state.ownedClipboardChangeCount, 20)
    }

    func testSuccessfulExampleReplacesThePreviousSource() {
        var state = LastSourceState()
        state.recordSuccessfulRender(markdown: "User Markdown", clipboardChangeCount: 30)
        state.recordSuccessfulRender(markdown: "Example Markdown", clipboardChangeCount: 31)

        XCTAssertEqual(state.markdown, "Example Markdown")
        XCTAssertEqual(state.ownedClipboardChangeCount, 31)
    }

    func testExternalClipboardChangeRequiresConfirmation() {
        var state = LastSourceState()
        state.recordSuccessfulRender(markdown: "# Source", clipboardChangeCount: 40)

        XCTAssertFalse(state.requiresConfirmation(currentClipboardChangeCount: 40))
        XCTAssertTrue(state.requiresConfirmation(currentClipboardChangeCount: 41))
    }

    func testRepeatedOwnedWritesDoNotRequireConfirmation() {
        var state = LastSourceState()
        state.recordSuccessfulRender(markdown: "# Source", clipboardChangeCount: 50)

        state.recordOwnedClipboardWrite(changeCount: 51)
        XCTAssertFalse(state.requiresConfirmation(currentClipboardChangeCount: 51))
        XCTAssertEqual(state.markdown, "# Source")

        state.recordOwnedClipboardWrite(changeCount: 52)
        XCTAssertFalse(state.requiresConfirmation(currentClipboardChangeCount: 52))
        XCTAssertEqual(state.markdown, "# Source")
    }

    func testNewStateDoesNotRetainPreviousSource() {
        var previousProcessState = LastSourceState()
        previousProcessState.recordSuccessfulRender(
            markdown: "Private source",
            clipboardChangeCount: 60
        )

        let relaunchedProcessState = LastSourceState()

        XCTAssertTrue(previousProcessState.isAvailable)
        XCTAssertFalse(relaunchedProcessState.isAvailable)
        XCTAssertNil(relaunchedProcessState.markdown)
        XCTAssertNil(relaunchedProcessState.ownedClipboardChangeCount)
    }

    func testConfirmationMessagesAreLocalizedForEachAction() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))

        XCTAssertEqual(
            LastSourceOverwriteAction.rerender.confirmationMessage(bundle: english),
            "Another app changed the clipboard. Replace it with a newly rendered image from the last Markdown?"
        )
        XCTAssertEqual(
            LastSourceOverwriteAction.restore.confirmationMessage(bundle: chinese),
            "其他应用已更改剪贴板。是否用上次的 Markdown 替换当前内容？"
        )
    }
}
