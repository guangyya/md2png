import AppKit
import XCTest
@testable import MD2PNG

final class WelcomeTests: XCTestCase {
    func testWelcomePreferenceShowsOnceAndStoresOnlyCompletion() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preference = WelcomePreference(defaults: defaults)

        XCTAssertTrue(preference.shouldShowOnLaunch)

        preference.markCompleted()

        XCTAssertFalse(preference.shouldShowOnLaunch)
        let storedValues = try XCTUnwrap(defaults.persistentDomain(forName: suiteName))
        XCTAssertEqual(storedValues.count, 1)
        XCTAssertEqual(storedValues[WelcomePreference.defaultsKey] as? Bool, true)
    }

    @MainActor
    func testShortcutStatusesPreserveCurrentKeysAndFailures() {
        let registrations: [GlobalHotKey.Registration] = [
            .render {},
            .showLastRender {}
        ]
        let statuses = registrations.map {
            WelcomeShortcutStatus(
                registration: $0,
                failedRegistrationIDs: [registrations[1].id]
            )
        }

        XCTAssertEqual(statuses.map(\.shortcutGlyphs), ["⌃⌘X", "⌃⌘Z"])
        XCTAssertTrue(statuses[0].isRegistered)
        XCTAssertFalse(statuses[1].isRegistered)
        XCTAssertEqual(
            statuses[0].title,
            L10n.text("menu.render", defaultValue: "Render Clipboard as Image")
        )
    }

    func testWelcomeCopyIsLocalizedInEnglishAndSimplifiedChinese() throws {
        let englishBundle = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let chineseBundle = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))
        let english = WelcomeCopy(localizationBundle: englishBundle)
        let chinese = WelcomeCopy(localizationBundle: chineseBundle)

        XCTAssertEqual(english.windowTitle, "Welcome to md2png")
        XCTAssertEqual(english.trySample, "Try a Short Sample")
        XCTAssertEqual(chinese.windowTitle, "欢迎使用 md2png")
        XCTAssertEqual(chinese.shortcutUnavailable, "已占用")
        XCTAssertTrue(chinese.privacyNote.contains("绝不会"))
        XCTAssertEqual(
            L10n.text("menu.show_welcome", defaultValue: "", bundle: englishBundle),
            "Show Welcome"
        )
        XCTAssertEqual(
            L10n.text("menu.show_welcome", defaultValue: "", bundle: chineseBundle),
            "显示欢迎指南"
        )
    }

    func testWelcomeWindowPlacementCentersInsideTheActiveVisibleFrame() {
        let origin = WelcomeWindowPlacement.centeredOrigin(
            windowSize: NSSize(width: 620, height: 648),
            visibleFrame: NSRect(x: -1920, y: 25, width: 1920, height: 1055)
        )

        XCTAssertEqual(origin.x, -1270, accuracy: 0.001)
        XCTAssertEqual(origin.y, 228.5, accuracy: 0.001)
    }

    @MainActor
    func testWelcomeWindowCanTrySampleCompleteAndStayDismissed() throws {
        _ = NSApplication.shared
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preference = WelcomePreference(defaults: defaults)
        var sampleCount = 0
        let controller = WelcomeController(preference: preference) {
            sampleCount += 1
        }
        let shortcuts = [WelcomeShortcutStatus(
            id: 1,
            title: "Render Clipboard as Image",
            shortcutGlyphs: "⌃⌘X",
            shortcutAccessibilityName: "Control-Command-X",
            isRegistered: false
        )]

        XCTAssertTrue(controller.showIfNeeded(shortcuts: shortcuts))
        XCTAssertEqual(controller.window?.title, "Welcome to md2png")
        XCTAssertEqual(controller.displayedContentSize, NSSize(width: 620, height: 620))
        XCTAssertEqual(controller.displayedShortcutStatuses, shortcuts)
        XCTAssertEqual(controller.window?.isVisible, true)
        XCTAssertEqual(controller.window?.level, .normal)

        controller.trySampleForTesting()
        XCTAssertEqual(sampleCount, 1)

        controller.completeForTesting()
        XCTAssertFalse(preference.shouldShowOnLaunch)
        XCTAssertEqual(controller.window?.isVisible, false)
        XCTAssertFalse(controller.showIfNeeded(shortcuts: shortcuts))
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "MD2PNGWelcomeTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
