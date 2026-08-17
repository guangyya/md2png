import AppKit
import Carbon
import XCTest
@testable import MD2PNG

final class GlobalShortcutTests: XCTestCase {
    func testDefaultConfigurationPreservesExistingShortcuts() {
        let configuration = GlobalShortcutConfiguration.default

        XCTAssertEqual(configuration.render.key.keyCode, UInt32(kVK_ANSI_X))
        XCTAssertEqual(configuration.showLastRender.key.keyCode, UInt32(kVK_ANSI_Z))
        XCTAssertEqual(configuration.render.glyphs, "⌃⌘X")
        XCTAssertEqual(configuration.showLastRender.glyphs, "⌃⌘Z")
        XCTAssertEqual(configuration.render.accessibilityName, "Control-Command-X")
        XCTAssertEqual(
            configuration.showLastRender.accessibilityName,
            "Control-Command-Z"
        )
        XCTAssertEqual(configuration.render.key.keyEquivalent, "x")
        XCTAssertEqual(
            configuration.render.menuModifierMask,
            [.control, .command]
        )
        XCTAssertTrue(configuration.isValid)
        XCTAssertTrue(configuration.conflictingCommands.isEmpty)
    }

    func testShortcutRequiresPrimaryModifierAndRejectsUnsupportedModifiers() {
        XCTAssertNil(GlobalShortcut(key: .x, modifiers: []))
        XCTAssertNil(GlobalShortcut(key: .x, modifiers: [.shift]))
        XCTAssertNil(GlobalShortcut(
            key: .x,
            modifiers: GlobalShortcut.Modifiers(rawValue: 1 << 8)
        ))
        XCTAssertNotNil(GlobalShortcut(key: .x, modifiers: [.option]))
        XCTAssertNotNil(GlobalShortcut(key: .x, modifiers: [.control, .shift]))
    }

    func testKeyRequiresOneMenuEquivalentCharacter() {
        XCTAssertNil(GlobalShortcutKey(
            keyCode: UInt32(kVK_ANSI_X),
            keyEquivalent: "",
            displayName: "X",
            accessibilityName: "X"
        ))
        XCTAssertNil(GlobalShortcutKey(
            keyCode: UInt32(kVK_ANSI_X),
            keyEquivalent: "xx",
            displayName: "X",
            accessibilityName: "X"
        ))
        XCTAssertNotNil(GlobalShortcutKey(
            keyCode: UInt32(kVK_ANSI_X),
            keyEquivalent: "x",
            displayName: "X",
            accessibilityName: "X"
        ))
    }

    func testConfigurationDetectsDuplicatePhysicalRegistration() throws {
        let duplicateKey = try XCTUnwrap(GlobalShortcutKey(
            keyCode: UInt32(kVK_ANSI_X),
            keyEquivalent: "χ",
            displayName: "Χ",
            accessibilityName: "Chi"
        ))
        let duplicate = try XCTUnwrap(GlobalShortcut(
            key: duplicateKey,
            modifiers: [.control, .command]
        ))
        let configuration = GlobalShortcutConfiguration(
            render: .defaultRender,
            showLastRender: duplicate
        )

        XCTAssertFalse(configuration.isValid)
        XCTAssertEqual(
            configuration.conflictingCommands,
            [.render, .showLastRender]
        )
    }

    func testPreferenceDefaultsWithoutWritingAndRestoresDefaults() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preference = GlobalShortcutPreference(defaults: defaults)

        XCTAssertEqual(preference.configuration, .default)
        XCTAssertNil(defaults.object(forKey: GlobalShortcutPreference.defaultsKey))

        var custom = GlobalShortcutConfiguration.default
        custom[.render] = try XCTUnwrap(GlobalShortcut(
            key: .z,
            modifiers: [.option, .command]
        ))
        XCTAssertTrue(preference.save(custom))
        XCTAssertEqual(
            GlobalShortcutPreference(defaults: defaults).configuration,
            custom
        )

        preference.restoreDefaults()
        XCTAssertNil(defaults.object(forKey: GlobalShortcutPreference.defaultsKey))
        XCTAssertEqual(preference.configuration, .default)
    }

    func testPreferenceRejectsDuplicateAndCorruptConfigurations() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preference = GlobalShortcutPreference(defaults: defaults)
        let duplicate = GlobalShortcutConfiguration(
            render: .defaultRender,
            showLastRender: .defaultRender
        )

        XCTAssertFalse(preference.save(duplicate))
        XCTAssertNil(defaults.object(forKey: GlobalShortcutPreference.defaultsKey))

        defaults.set(Data("not-json".utf8), forKey: GlobalShortcutPreference.defaultsKey)
        XCTAssertEqual(preference.configuration, .default)
    }

    @MainActor
    func testRegistrationUsesConfiguredShortcutPresentation() throws {
        let shortcut = try XCTUnwrap(GlobalShortcut(
            key: .z,
            modifiers: [.option, .shift, .command]
        ))

        let registration = GlobalHotKey.Registration.render(shortcut: shortcut) {}

        XCTAssertEqual(registration.keyCode, UInt32(kVK_ANSI_Z))
        XCTAssertEqual(
            registration.modifiers,
            UInt32(optionKey | shiftKey | cmdKey)
        )
        XCTAssertEqual(registration.shortcutGlyphs, "⌥⇧⌘Z")
        XCTAssertEqual(
            registration.shortcutAccessibilityName,
            "Option-Shift-Command-Z"
        )
        XCTAssertEqual(
            registration.displayName,
            "Render (Option-Shift-Command-Z)"
        )
    }

    @MainActor
    func testRegistrationFormatsDynamicShortcutInChinese() throws {
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))
        let shortcut = try XCTUnwrap(GlobalShortcut(
            key: .z,
            modifiers: [.option, .command]
        ))

        let registration = GlobalHotKey.Registration.render(
            shortcut: shortcut,
            localizationBundle: chinese
        ) {}

        XCTAssertEqual(registration.commandTitle, "将剪贴板渲染为图片")
        XCTAssertEqual(registration.displayName, "渲染（Option-Command-Z）")
    }

    @MainActor
    func testRegistrarInvalidatesPreviousSessionBeforeReplacingIt() {
        var sessions: [FakeGlobalHotKeySession] = []
        let registrar = GlobalHotKeyRegistrar { registrations in
            let session = FakeGlobalHotKeySession(
                failedRegistrationIDs: registrations.count == 1 ? [73] : []
            )
            sessions.append(session)
            return session
        }

        let firstFailures = registrar.replace(registrations: [.render {}])
        let secondFailures = registrar.replace(registrations: [
            .render {},
            .showLastRender {}
        ])

        XCTAssertEqual(firstFailures, [73])
        XCTAssertTrue(secondFailures.isEmpty)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].invalidationCount, 1)
        XCTAssertEqual(sessions[1].invalidationCount, 0)

        registrar.invalidate()
        registrar.invalidate()

        XCTAssertEqual(sessions[0].invalidationCount, 1)
        XCTAssertEqual(sessions[1].invalidationCount, 1)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "MD2PNGGlobalShortcutTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}

@MainActor
private final class FakeGlobalHotKeySession: GlobalHotKeySession {
    let failedRegistrationIDs: Set<UInt32>
    private(set) var invalidationCount = 0

    init(failedRegistrationIDs: Set<UInt32>) {
        self.failedRegistrationIDs = failedRegistrationIDs
    }

    func invalidate() {
        invalidationCount += 1
    }
}
