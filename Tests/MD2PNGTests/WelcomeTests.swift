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
        XCTAssertTrue(english.trySampleHelp.contains("Examples"))
        XCTAssertEqual(chinese.windowTitle, "欢迎使用 md2png")
        XCTAssertEqual(chinese.shortcutUnavailable, "已占用")
        XCTAssertTrue(chinese.privacyNote.contains("绝不会"))
        XCTAssertTrue(chinese.reopenHint.contains("显示欢迎指南"))
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
            windowSize: NSSize(width: 560, height: 608),
            visibleFrame: NSRect(x: -1920, y: 25, width: 1920, height: 1055)
        )

        XCTAssertEqual(origin.x, -1240, accuracy: 0.001)
        XCTAssertEqual(origin.y, 248.5, accuracy: 0.001)
    }

    func testWelcomeAnimationProgressMovesThroughTheWholeWorkflow() {
        let copying = WelcomeAnimationProgress(phase: .copy)
        let rendering = WelcomeAnimationProgress(phase: .render)
        let pasting = WelcomeAnimationProgress(phase: .paste)

        XCTAssertEqual(copying.cardTravel, -1)
        XCTAssertEqual(copying.imageReveal, 0)
        XCTAssertEqual(copying.detailIndex, 0)
        XCTAssertEqual(rendering.cardTravel, 0)
        XCTAssertEqual(rendering.keyPress, 1)
        XCTAssertGreaterThan(rendering.imageReveal, 0.5)
        XCTAssertEqual(rendering.detailIndex, 1)
        XCTAssertEqual(pasting.cardTravel, 1)
        XCTAssertEqual(pasting.imageReveal, 1)
        XCTAssertEqual(pasting.pastePrompt, 1)
        XCTAssertEqual(pasting.detailIndex, 2)
        XCTAssertEqual(WelcomeAnimationProgress.reducedMotion.imageReveal, 1)
    }

    func testSampleGuideRevealsTheMenuHierarchyInOrder() {
        XCTAssertFalse(SampleGuidePhase.mainMenu.highlightsExamples)
        XCTAssertFalse(SampleGuidePhase.mainMenu.showsSubmenu)
        XCTAssertFalse(SampleGuidePhase.mainMenu.acceptsSubmenuInput)
        XCTAssertTrue(SampleGuidePhase.examplesFocused.highlightsExamples)
        XCTAssertFalse(SampleGuidePhase.examplesFocused.showsSubmenu)
        XCTAssertFalse(SampleGuidePhase.examplesFocused.acceptsSubmenuInput)
        XCTAssertTrue(SampleGuidePhase.submenu.showsSubmenu)
        XCTAssertTrue(SampleGuidePhase.submenu.acceptsSubmenuInput)
    }

    func testSampleGuideKeyboardNavigationMovesAndWrapsAcrossExamples() {
        XCTAssertEqual(
            SampleGuideFocusNavigation.targetID(from: nil, direction: .next),
            ExampleKind.short.rawValue
        )
        XCTAssertEqual(
            SampleGuideFocusNavigation.targetID(
                from: ExampleKind.short.rawValue,
                direction: .next
            ),
            ExampleKind.long.rawValue
        )
        XCTAssertEqual(
            SampleGuideFocusNavigation.targetID(
                from: ExampleKind.short.rawValue,
                direction: .previous
            ),
            ExampleKind.gantt.rawValue
        )
        XCTAssertEqual(
            SampleGuideFocusNavigation.targetID(
                from: ExampleKind.gantt.rawValue,
                direction: .next
            ),
            ExampleKind.short.rawValue
        )
        XCTAssertEqual(
            SampleGuideFocusNavigation.targetID(from: Int.max, direction: .previous),
            ExampleKind.gantt.rawValue
        )
    }

    func testSampleGuideKeyRoutingCoversMenuNavigationAndActivation() {
        XCTAssertEqual(
            SampleGuideKeyRouting.command(
                forKeyCode: SampleGuideKeyCode.tab,
                isShiftPressed: false
            ),
            .next
        )
        XCTAssertEqual(
            SampleGuideKeyRouting.command(
                forKeyCode: SampleGuideKeyCode.tab,
                isShiftPressed: true
            ),
            .previous
        )
        XCTAssertEqual(
            SampleGuideKeyRouting.command(
                forKeyCode: SampleGuideKeyCode.upArrow,
                isShiftPressed: false
            ),
            .previous
        )
        XCTAssertEqual(
            SampleGuideKeyRouting.command(
                forKeyCode: SampleGuideKeyCode.downArrow,
                isShiftPressed: false
            ),
            .next
        )
        for keyCode in [
            SampleGuideKeyCode.space,
            SampleGuideKeyCode.returnKey,
            SampleGuideKeyCode.keypadEnter
        ] {
            XCTAssertEqual(
                SampleGuideKeyRouting.command(
                    forKeyCode: keyCode,
                    isShiftPressed: false
                ),
                .activate
            )
        }
        XCTAssertEqual(
            SampleGuideKeyRouting.command(
                forKeyCode: SampleGuideKeyCode.escape,
                isShiftPressed: false
            ),
            .dismiss
        )
        XCTAssertNil(
            SampleGuideKeyRouting.command(forKeyCode: UInt16.max, isShiftPressed: false)
        )
    }

    @MainActor
    func testSampleGuideKeyboardStateWaitsForRevealBeforeMovingFocus() {
        let keyboardState = SampleGuideKeyboardState()

        keyboardState.move(.next)
        XCTAssertNil(keyboardState.focusedExampleID)
        XCTAssertFalse(keyboardState.isNavigationEnabled)

        keyboardState.enableAndFocusFirstExample()
        XCTAssertEqual(keyboardState.focusedExample, .short)

        keyboardState.move(.next)
        XCTAssertEqual(keyboardState.focusedExample, .long)
    }

    @MainActor
    func testSampleGuideClosesBeforeDeliveringOneSelection() {
        let popover = TestSampleGuidePopover()
        let statusButton = NSStatusBarButton(
            frame: NSRect(x: 0, y: 0, width: 22, height: 22)
        )
        var deliveredSelections: [ExampleKind] = []
        let controller = SampleGuideController(popover: popover) { kind in
            XCTAssertFalse(popover.isShown)
            deliveredSelections.append(kind)
        }
        controller.show(
            relativeTo: statusButton,
            menuState: SampleGuideMenuState(
                canRestoreLastMarkdown: true,
                canShowLastRender: false
            )
        )

        XCTAssertTrue(popover.isShown)
        XCTAssertNotNil(popover.contentViewController)
        XCTAssertEqual(popover.makeContentKeyCount, 1)
        XCTAssertEqual(statusButton.cell?.isHighlighted, true)

        controller.choose(.short)
        controller.choose(.table)

        XCTAssertEqual(popover.closeCount, 1)
        XCTAssertEqual(deliveredSelections, [.short])
        XCTAssertEqual(statusButton.cell?.isHighlighted, false)
    }

    @MainActor
    func testSampleGuideDismissalClearsPendingSelectionWithoutCallback() {
        let popover = TestSampleGuidePopover()
        let statusButton = NSStatusBarButton(
            frame: NSRect(x: 0, y: 0, width: 22, height: 22)
        )
        var deliveredSelections: [ExampleKind] = []
        let controller = SampleGuideController(popover: popover) {
            deliveredSelections.append($0)
        }
        controller.show(
            relativeTo: statusButton,
            menuState: SampleGuideMenuState(
                canRestoreLastMarkdown: false,
                canShowLastRender: false
            )
        )

        controller.dismiss()
        controller.choose(.short)

        XCTAssertEqual(popover.closeCount, 1)
        XCTAssertTrue(deliveredSelections.isEmpty)
        XCTAssertEqual(statusButton.cell?.isHighlighted, false)
    }

    @MainActor
    func testSampleGuideConsumesNavigationWithoutOwningTheKeyWindow() throws {
        _ = NSApplication.shared
        let popover = TestSampleGuidePopover()
        let statusButton = NSStatusBarButton(
            frame: NSRect(x: 0, y: 0, width: 22, height: 22)
        )
        let controller = SampleGuideController(popover: popover) { _ in }
        controller.show(
            relativeTo: statusButton,
            menuState: SampleGuideMenuState(
                canRestoreLastMarkdown: false,
                canShowLastRender: false
            )
        )
        XCTAssertNil(popover.contentViewController?.view.window)

        let downArrow = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{F701}",
            charactersIgnoringModifiers: "\u{F701}",
            isARepeat: false,
            keyCode: SampleGuideKeyCode.downArrow
        ))

        XCTAssertNil(controller.handleKeyDown(downArrow))
        controller.dismiss()
    }

    @MainActor
    func testWelcomeWindowCanTrySampleCompleteAndStayDismissed() throws {
        _ = NSApplication.shared
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preference = WelcomePreference(defaults: defaults)
        var sampleCount = 0
        var visibilityChanges: [Bool] = []
        let controller = WelcomeController(
            preference: preference,
            onVisibilityChange: { visibilityChanges.append($0) },
            onTrySample: { sampleCount += 1 }
        )
        let shortcuts = [WelcomeShortcutStatus(
            id: 1,
            title: "Render Clipboard as Image",
            shortcutGlyphs: "⌃⌘X",
            shortcutAccessibilityName: "Control-Command-X",
            isRegistered: false
        )]

        XCTAssertTrue(controller.showIfNeeded(shortcuts: shortcuts))
        XCTAssertEqual(controller.window?.title, "Welcome to md2png")
        XCTAssertEqual(controller.displayedContentSize, NSSize(width: 560, height: 580))
        XCTAssertEqual(controller.displayedShortcutStatuses, shortcuts)
        XCTAssertEqual(controller.window?.isVisible, true)
        XCTAssertEqual(controller.window?.level, .normal)
        XCTAssertEqual(
            controller.window?.collectionBehavior.contains(.moveToActiveSpace),
            true
        )
        XCTAssertEqual(visibilityChanges, [true])

        controller.trySampleForTesting()
        XCTAssertEqual(sampleCount, 1)

        controller.completeForTesting()
        XCTAssertFalse(preference.shouldShowOnLaunch)
        XCTAssertEqual(controller.window?.isVisible, false)
        XCTAssertEqual(visibilityChanges, [true, false])
        XCTAssertFalse(controller.showIfNeeded(shortcuts: shortcuts))
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "MD2PNGWelcomeTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}

@MainActor
private final class TestSampleGuidePopover: SampleGuidePopover {
    var behavior: NSPopover.Behavior = .applicationDefined
    var animates = false
    weak var delegate: (any NSPopoverDelegate)?
    var contentSize = NSSize.zero
    var contentViewController: NSViewController?
    var isShown = false
    private(set) var closeCount = 0
    private(set) var makeContentKeyCount = 0

    func show(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        preferredEdge: NSRectEdge
    ) {
        isShown = true
    }

    func makeContentKey() {
        makeContentKeyCount += 1
    }

    func close() {
        guard isShown else { return }
        closeCount += 1
        delegate?.popoverWillClose?(Notification(name: NSPopover.willCloseNotification))
        isShown = false
        delegate?.popoverDidClose?(Notification(name: NSPopover.didCloseNotification))
    }
}
