import AppKit
import Carbon
import XCTest
@testable import MD2PNG

final class GlobalShortcutCaptureTests: XCTestCase {
    func testCaptureBuildsAConfiguredLetterShortcut() throws {
        let event = try makeEvent(
            keyCode: UInt16(kVK_ANSI_K),
            characters: "k",
            modifiers: [.control, .option, .shift]
        )

        let shortcut = try XCTUnwrap(try? GlobalShortcutCapture.shortcut(from: event).get())

        XCTAssertEqual(shortcut.key.keyCode, UInt32(kVK_ANSI_K))
        XCTAssertEqual(shortcut.key.keyEquivalent, "k")
        XCTAssertEqual(shortcut.key.displayName, "K")
        XCTAssertEqual(shortcut.modifiers, [.control, .option, .shift])
        XCTAssertEqual(shortcut.glyphs, "⌃⌥⇧K")
    }

    func testCaptureMapsSpecialKeysForMenusAndAccessibility() throws {
        let arrow = try XCTUnwrap(GlobalShortcutCapture.key(
            keyCode: UInt16(kVK_LeftArrow),
            charactersIgnoringModifiers: nil
        ))
        let function = try XCTUnwrap(GlobalShortcutCapture.key(
            keyCode: UInt16(kVK_F12),
            charactersIgnoringModifiers: nil
        ))

        XCTAssertEqual(arrow.keyEquivalent, "\u{F702}")
        XCTAssertEqual(arrow.displayName, "←")
        XCTAssertEqual(arrow.accessibilityName, "Left Arrow")
        XCTAssertEqual(function.keyEquivalent, "\u{F70F}")
        XCTAssertEqual(function.displayName, "F12")
    }

    func testCaptureRequiresAPrimaryModifier() throws {
        let none = try makeEvent(keyCode: UInt16(kVK_ANSI_X), characters: "x")
        let shift = try makeEvent(
            keyCode: UInt16(kVK_ANSI_X),
            characters: "x",
            modifiers: [.shift]
        )

        XCTAssertEqual(
            GlobalShortcutCapture.shortcut(from: none),
            .failure(.missingPrimaryModifier)
        )
        XCTAssertEqual(
            GlobalShortcutCapture.shortcut(from: shift),
            .failure(.missingPrimaryModifier)
        )
    }

    func testCaptureRejectsUnsupportedCharacterSequences() throws {
        let event = try makeEvent(
            keyCode: UInt16(kVK_ANSI_X),
            characters: "xx",
            modifiers: [.command]
        )

        XCTAssertEqual(
            GlobalShortcutCapture.shortcut(from: event),
            .failure(.unsupportedKey)
        )
    }

    @MainActor
    func testSettingsModelRejectsDuplicatesWithoutSavingOrApplying() throws {
        let (preference, defaults, suiteName) = try makePreference()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var applied: [GlobalShortcutConfiguration] = []
        var recordingLifecycle: [String] = []
        let model = ShortcutSettingsModel(
            preference: preference,
            onRecordingBegan: { recordingLifecycle.append("began") },
            onRecordingCancelled: { recordingLifecycle.append("cancelled") }
        ) {
            applied.append($0)
            return []
        }

        model.beginRecording(.showLastRender)

        XCTAssertFalse(model.setShortcut(.defaultRender, for: .showLastRender))

        XCTAssertEqual(model.configuration, .default)
        XCTAssertEqual(model.recordingCommand, .showLastRender)
        XCTAssertEqual(model.feedback, .duplicate)
        XCTAssertEqual(recordingLifecycle, ["began"])
        XCTAssertTrue(applied.isEmpty)
        XCTAssertNil(defaults.object(forKey: GlobalShortcutPreference.defaultsKey))

        model.cancelRecording()

        XCTAssertEqual(recordingLifecycle, ["began", "cancelled"])
    }

    @MainActor
    func testSettingsModelAcceptsTheCurrentShortcutWithoutCancellingItsAction() {
        var applied: [GlobalShortcutConfiguration] = []
        var recordingLifecycle: [String] = []
        let model = ShortcutSettingsModel(
            onRecordingBegan: { recordingLifecycle.append("began") },
            onRecordingCancelled: { recordingLifecycle.append("cancelled") }
        ) {
            applied.append($0)
            return []
        }

        model.beginRecording(.render)

        XCTAssertTrue(model.setShortcut(.defaultRender, for: .render))
        XCTAssertNil(model.recordingCommand)
        XCTAssertEqual(applied, [.default])
        XCTAssertEqual(recordingLifecycle, ["began"])
    }

    @MainActor
    func testSettingsModelPersistsBeforeApplyingAndReportsRegistrationFailure() throws {
        let (preference, defaults, suiteName) = try makePreference()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let custom = try XCTUnwrap(GlobalShortcut(key: .x, modifiers: [.option, .command]))
        var applied: [GlobalShortcutConfiguration] = []
        let model = ShortcutSettingsModel(preference: preference) { configuration in
            XCTAssertEqual(preference.configuration, configuration)
            applied.append(configuration)
            return [GlobalShortcutCommand.render.rawValue]
        }

        model.beginRecording(.render)
        XCTAssertTrue(model.setShortcut(custom, for: .render))

        XCTAssertEqual(model.configuration.render, custom)
        XCTAssertNil(model.recordingCommand)
        XCTAssertEqual(applied, [model.configuration])
        XCTAssertEqual(
            model.feedback,
            .registrationUnavailable([.render])
        )
    }

    @MainActor
    func testSettingsModelKeepsRecordingAfterInvalidCapture() throws {
        let event = try makeEvent(
            keyCode: UInt16(kVK_ANSI_X),
            characters: "x",
            modifiers: [.shift]
        )
        let model = ShortcutSettingsModel { _ in [] }
        model.beginRecording(.render)

        XCTAssertFalse(model.capture(event, for: .render))
        XCTAssertEqual(model.recordingCommand, .render)
        XCTAssertEqual(model.feedback, .missingPrimaryModifier)
    }

    @MainActor
    func testSettingsModelRestoresDefaultsAndClearsStoredConfiguration() throws {
        let (preference, defaults, suiteName) = try makePreference()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var custom = GlobalShortcutConfiguration.default
        custom.render = try XCTUnwrap(GlobalShortcut(
            key: .x,
            modifiers: [.option, .command]
        ))
        XCTAssertTrue(preference.save(custom))
        var applied: [GlobalShortcutConfiguration] = []
        let model = ShortcutSettingsModel(preference: preference) {
            applied.append($0)
            return []
        }

        model.restoreDefaults()

        XCTAssertEqual(model.configuration, .default)
        XCTAssertEqual(model.feedback, .restoredDefaults)
        XCTAssertEqual(applied, [.default])
        XCTAssertNil(defaults.object(forKey: GlobalShortcutPreference.defaultsKey))
    }

    private func makeEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = []
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
        let suiteName = "MD2PNGShortcutSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (GlobalShortcutPreference(defaults: defaults), defaults, suiteName)
    }
}
