import AppKit
import Carbon
import XCTest
@testable import MD2PNG

final class ShortcutSettingsControllerTests: XCTestCase {
    func testSettingsCopyIsLocalizedAndDescribesMenuFallback() throws {
        let english = ShortcutSettingsCopy(
            localizationBundle: try XCTUnwrap(L10n.localizedBundle(for: "en"))
        )
        let chinese = ShortcutSettingsCopy(
            localizationBundle: try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))
        )

        XCTAssertEqual(english.windowTitle, "Settings")
        XCTAssertEqual(english.title, "Keyboard Shortcuts")
        XCTAssertEqual(english.restoreDefaults, "Restore Defaults")
        XCTAssertEqual(
            english.feedbackText(.registrationUnavailable([.render])),
            "Render couldn’t be registered. Its menu command still works."
        )
        XCTAssertEqual(chinese.windowTitle, "设置")
        XCTAssertEqual(chinese.recording, "请按快捷键…")
        XCTAssertEqual(
            chinese.feedbackText(.duplicate),
            "请为每个命令选择不同的快捷键。"
        )
    }

    @MainActor
    func testSettingsWindowUsesStableNativeHostingLayoutAndVisibility() throws {
        _ = NSApplication.shared
        var visibility: [Bool] = []
        let controller = ShortcutSettingsController(
            onApply: { _ in [] },
            onVisibilityChange: { visibility.append($0) }
        )

        controller.show(
            configuration: .default,
            failedRegistrationIDs: [GlobalShortcutCommand.render.rawValue]
        )

        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertTrue(controller.usesSwiftUIHostingBoundary)
        XCTAssertEqual(controller.displayedContentSize, ShortcutSettingsLayout.windowSize)
        XCTAssertEqual(
            controller.displayedFeedback,
            .registrationUnavailable([.render])
        )
        XCTAssertEqual(ShortcutSettingsLayout.rowHeight, 56)
        XCTAssertEqual(ShortcutSettingsLayout.feedbackHeight, 44)
        XCTAssertEqual(visibility, [true])

        controller.close()

        XCTAssertEqual(visibility, [true, false])
    }

    @MainActor
    func testSettingsCapturePersistsAndAppliesImmediately() throws {
        _ = NSApplication.shared
        let (preference, defaults, suiteName) = try makePreference()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var applied: [GlobalShortcutConfiguration] = []
        let controller = ShortcutSettingsController(
            preference: preference,
            onApply: {
                applied.append($0)
                return []
            }
        )
        controller.show(configuration: .default, failedRegistrationIDs: [])
        defer { controller.close() }
        let event = try makeEvent(
            keyCode: UInt16(kVK_ANSI_K),
            characters: "k",
            modifiers: [.option, .command]
        )

        XCTAssertTrue(controller.captureForTesting(event, command: .render))

        let expected = try XCTUnwrap(applied.last)
        XCTAssertEqual(controller.displayedConfiguration, expected)
        XCTAssertEqual(preference.configuration, expected)
        XCTAssertEqual(expected.render.key.keyCode, UInt32(kVK_ANSI_K))
        XCTAssertEqual(expected.render.modifiers, [.option, .command])
    }

    @MainActor
    func testSettingsRestoreDefaultsRemovesPreferenceAndReappliesDefaults() throws {
        _ = NSApplication.shared
        let (preference, defaults, suiteName) = try makePreference()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var custom = GlobalShortcutConfiguration.default
        custom.render = try XCTUnwrap(GlobalShortcut(
            key: .x,
            modifiers: [.option, .command]
        ))
        XCTAssertTrue(preference.save(custom))
        var applied: [GlobalShortcutConfiguration] = []
        let controller = ShortcutSettingsController(
            preference: preference,
            onApply: {
                applied.append($0)
                return []
            }
        )
        controller.show(configuration: custom, failedRegistrationIDs: [])
        defer { controller.close() }

        controller.restoreDefaultsForTesting()

        XCTAssertEqual(controller.displayedConfiguration, .default)
        XCTAssertEqual(controller.displayedFeedback, .restoredDefaults)
        XCTAssertEqual(applied, [.default])
        XCTAssertNil(defaults.object(forKey: GlobalShortcutPreference.defaultsKey))
    }

    @MainActor
    func testRecorderCancelsWithEscapeAndCapturesCommandEquivalent() throws {
        _ = NSApplication.shared
        let recorder = ShortcutRecorderControl()
        var cancelCount = 0
        var capturedEvents: [NSEvent] = []
        recorder.configure(
            shortcut: .defaultRender,
            isRecording: true,
            recordingTitle: "Type shortcut…",
            accessibilityLabel: "Render shortcut",
            accessibilityHelp: "Press a shortcut",
            onBegin: {},
            onCancel: { cancelCount += 1 },
            onCapture: { capturedEvents.append($0) }
        )
        let escape = try makeEvent(
            keyCode: UInt16(kVK_Escape),
            characters: "\u{1b}",
            modifiers: []
        )
        let commandK = try makeEvent(
            keyCode: UInt16(kVK_ANSI_K),
            characters: "k",
            modifiers: [.command]
        )

        recorder.keyDown(with: escape)
        XCTAssertEqual(cancelCount, 1)
        XCTAssertTrue(capturedEvents.isEmpty)

        recorder.configure(
            shortcut: .defaultRender,
            isRecording: true,
            recordingTitle: "Type shortcut…",
            accessibilityLabel: "Render shortcut",
            accessibilityHelp: "Press a shortcut",
            onBegin: {},
            onCancel: { cancelCount += 1 },
            onCapture: { capturedEvents.append($0) }
        )
        XCTAssertTrue(recorder.performKeyEquivalent(with: commandK))
        XCTAssertEqual(capturedEvents, [commandK])
    }

    private func makeEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags
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
            keyCode: keyCode
        ))
    }

    private func makePreference() throws -> (GlobalShortcutPreference, UserDefaults, String) {
        let suiteName = "MD2PNGShortcutSettingsControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (GlobalShortcutPreference(defaults: defaults), defaults, suiteName)
    }
}
