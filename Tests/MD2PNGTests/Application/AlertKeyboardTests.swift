import AppKit
import XCTest
@testable import MD2PNG

@MainActor
final class AlertKeyboardTests: XCTestCase {
    func testDefaultAndCancelButtonsUseReturnAndEscape() {
        _ = NSApplication.shared
        let alert = NSAlert()
        let defaultButton = alert.addButton(withTitle: "Continue")
        let cancelButton = alert.addButton(withTitle: "Cancel")

        AlertKeyboard.configureDefaultAndCancel(
            in: alert,
            defaultButton: defaultButton,
            cancelButton: cancelButton
        )

        XCTAssertEqual(defaultButton.keyEquivalent, "\r")
        XCTAssertEqual(cancelButton.keyEquivalent, "\u{1b}")
        XCTAssertTrue(alert.window.defaultButtonCell === defaultButton.cell)
    }
}
