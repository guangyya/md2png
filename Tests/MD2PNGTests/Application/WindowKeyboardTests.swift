import AppKit
import XCTest
@testable import MD2PNG

@MainActor
final class WindowKeyboardTests: XCTestCase {
    func testAppWindowRoutesOnlyStandardWindowCommands() throws {
        let commandW = try keyEvent("w")
        let commandComma = try keyEvent(",")
        let commandC = try keyEvent("c")
        let optionCommandW = try keyEvent("w", modifiers: [.command, .option])
        let escape = try keyEvent("\u{1b}", modifiers: [])

        XCTAssertEqual(AppWindow.appCommand(for: commandW), .close)
        XCTAssertEqual(AppWindow.appCommand(for: commandComma), .showSettings)
        XCTAssertNil(AppWindow.appCommand(for: commandC))
        XCTAssertNil(AppWindow.appCommand(for: optionCommandW))
        XCTAssertNil(AppWindow.appCommand(for: escape))
    }

    func testAppWindowPerformsCloseAndInjectedSettingsAction() throws {
        _ = NSApplication.shared
        var settingsInvocationCount = 0
        let window = AppWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.showSettingsHandler = { settingsInvocationCount += 1 }
        window.orderFront(nil)

        window.sendEvent(try keyEvent(","))
        XCTAssertEqual(settingsInvocationCount, 1)
        XCTAssertTrue(window.isVisible)

        window.sendEvent(try keyEvent("w"))
        XCTAssertFalse(window.isVisible)
    }

    func testNonPreviewWindowsDoNotClaimPreviewImageShortcuts() throws {
        _ = NSApplication.shared
        let about = AboutController(onShowSettings: {})
        let suiteName = "WindowKeyboardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = ShortcutSettingsController(
            preference: GlobalShortcutPreference(defaults: defaults),
            onApply: { _ in [] }
        )
        let welcome = WelcomeController(
            preference: WelcomePreference(defaults: defaults),
            onTrySample: {}
        )
        welcome.show(shortcuts: [])
        defer { welcome.close() }

        for window in [about.window, settings.window, welcome.window] {
            XCTAssertTrue(window is AppWindow)
            XCTAssertFalse(window is PreviewWindow)
        }
    }

    func testWindowControllersRouteCommandCommaToSettings() throws {
        _ = NSApplication.shared
        var invocations: [String] = []
        let preview = PreviewController(onShowSettings: { invocations.append("preview") })
        let about = AboutController(onShowSettings: { invocations.append("about") })
        let suiteName = "WindowSettingsRouteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let welcome = WelcomeController(
            preference: WelcomePreference(defaults: defaults),
            onShowSettings: { invocations.append("welcome") },
            onTrySample: {}
        )
        welcome.show(shortcuts: [])
        defer {
            preview.close()
            about.close()
            welcome.close()
        }

        preview.window?.sendEvent(try keyEvent(","))
        about.window?.sendEvent(try keyEvent(","))
        welcome.window?.sendEvent(try keyEvent(","))

        XCTAssertEqual(invocations, ["preview", "about", "welcome"])
    }

    private func keyEvent(
        _ characters: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        ))
    }
}
