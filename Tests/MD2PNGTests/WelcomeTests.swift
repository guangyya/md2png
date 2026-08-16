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
        XCTAssertEqual(statuses.map(\.isVerified), [false, false])
        XCTAssertEqual(statuses.map(\.verificationCount), [0, 0])
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
        XCTAssertEqual(english.shortcutDetected, "Detected")
        XCTAssertEqual(english.shortcutVerified, "Works")
        XCTAssertEqual(english.launchAtLoginTitle, "Launch at Login")
        XCTAssertEqual(english.launchAtLoginOptional, "Optional")
        XCTAssertEqual(english.launchAtLoginOpenSettings, "Open Settings…")
        XCTAssertTrue(english.shortcutVerificationHelp.contains("without running"))
        XCTAssertEqual(
            String(
                format: english.shortcutVerifiedAnnouncementFormat,
                "Render Clipboard as Image"
            ),
            "Render Clipboard as Image shortcut works."
        )
        XCTAssertEqual(chinese.windowTitle, "欢迎使用 md2png")
        XCTAssertEqual(chinese.shortcutDetected, "已检测")
        XCTAssertEqual(chinese.shortcutVerified, "已生效")
        XCTAssertEqual(chinese.shortcutUnavailable, "已占用")
        XCTAssertEqual(chinese.launchAtLoginTitle, "登录时启动")
        XCTAssertEqual(chinese.launchAtLoginOptional, "可选")
        XCTAssertEqual(chinese.launchAtLoginOpenSettings, "打开设置…")
        XCTAssertTrue(chinese.shortcutVerificationHelp.contains("不会执行"))
        XCTAssertEqual(
            String(
                format: chinese.shortcutVerifiedAnnouncementFormat,
                "将剪贴板渲染为图片"
            ),
            "“将剪贴板渲染为图片”快捷键已生效。"
        )
        XCTAssertTrue(chinese.privacyNote.contains("本机处理"))
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

    @MainActor
    func testWelcomeLaunchAtLoginStateHandlesEveryActionInline() {
        let service = WelcomeLaunchAtLoginServiceStub(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let state = WelcomeLaunchAtLoginState(
            controller: LaunchAtLoginController(service: service)
        )

        XCTAssertEqual(state.presentation.menuAction, .enable)

        state.performPrimaryAction()
        XCTAssertEqual(service.operations, [.register])
        XCTAssertEqual(state.presentation.menuAction, .allowInSystemSettings)

        state.performPrimaryAction()
        XCTAssertEqual(service.operations, [.register, .openSystemSettings])

        service.status = .enabled
        service.statusAfterUnregister = .notRegistered
        state.refresh()
        XCTAssertEqual(state.presentation.menuAction, .disable)

        state.performPrimaryAction()
        XCTAssertEqual(service.operations, [.register, .openSystemSettings, .unregister])
        XCTAssertEqual(state.presentation.menuAction, .enable)
    }

    @MainActor
    func testWelcomeLaunchAtLoginStateReportsUnavailableErrorsInline() {
        let service = WelcomeLaunchAtLoginServiceStub(status: .unknown)
        var errors: [Error] = []
        let state = WelcomeLaunchAtLoginState(
            controller: LaunchAtLoginController(service: service),
            onError: { errors.append($0) }
        )

        state.performPrimaryAction()

        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(service.operations.isEmpty)
        XCTAssertEqual(state.presentation.menuAction, .unavailable)
    }

    @MainActor
    func testWelcomeShortcutVerificationSuppressesActionsAndResetsEveryOpening() throws {
        _ = NSApplication.shared
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = WelcomeController(
            preference: WelcomePreference(defaults: defaults),
            onTrySample: {}
        )
        let registrations: [GlobalHotKey.Registration] = [
            .render {},
            .showLastRender {}
        ]
        let registeredShortcuts = registrations.map {
            WelcomeShortcutStatus(registration: $0, failedRegistrationIDs: [])
        }
        var performedCommands: [GlobalShortcutCommand] = []
        let router = GlobalShortcutRouter(
            verify: { controller.verifyShortcut($0) },
            perform: { performedCommands.append($0) }
        )

        router.handle(.render)
        router.handle(.showLastRender)
        XCTAssertEqual(performedCommands, [.render, .showLastRender])

        controller.show(shortcuts: registeredShortcuts)
        router.handle(.render)
        router.handle(.render)

        XCTAssertEqual(performedCommands, [.render, .showLastRender])
        XCTAssertEqual(
            controller.displayedShortcutStatuses.map(\.isVerified),
            [true, false]
        )
        XCTAssertEqual(
            controller.displayedShortcutStatuses.map(\.verificationCount),
            [2, 0]
        )

        router.handle(.showLastRender)

        XCTAssertEqual(performedCommands, [.render, .showLastRender])
        XCTAssertEqual(
            controller.displayedShortcutStatuses.map(\.isVerified),
            [true, true]
        )
        XCTAssertEqual(
            controller.displayedShortcutStatuses.map(\.verificationCount),
            [2, 1]
        )

        controller.close()
        router.handle(.render)
        router.handle(.showLastRender)
        XCTAssertEqual(
            performedCommands,
            [.render, .showLastRender, .render, .showLastRender]
        )

        controller.show(shortcuts: registeredShortcuts)
        XCTAssertEqual(
            controller.displayedShortcutStatuses.map(\.isVerified),
            [false, false]
        )
        XCTAssertEqual(
            controller.displayedShortcutStatuses.map(\.verificationCount),
            [0, 0]
        )

        controller.window?.orderOut(nil)
        router.handle(.render)
        XCTAssertEqual(
            performedCommands,
            [.render, .showLastRender, .render, .showLastRender, .render]
        )
        controller.close()
    }

    @MainActor
    func testWelcomeKeepsConflictedShortcutUnavailableAndSuppressesItsAction() throws {
        _ = NSApplication.shared
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = WelcomeController(
            preference: WelcomePreference(defaults: defaults),
            onTrySample: {}
        )
        let registrations: [GlobalHotKey.Registration] = [
            .render {},
            .showLastRender {}
        ]
        let shortcuts = registrations.map {
            WelcomeShortcutStatus(
                registration: $0,
                failedRegistrationIDs: [registrations[1].id]
            )
        }
        var performedCommands: [GlobalShortcutCommand] = []
        let router = GlobalShortcutRouter(
            verify: { controller.verifyShortcut($0) },
            perform: { performedCommands.append($0) }
        )
        controller.show(shortcuts: shortcuts)
        defer { controller.close() }

        router.handle(.showLastRender)

        XCTAssertTrue(performedCommands.isEmpty)
        XCTAssertFalse(controller.displayedShortcutStatuses[1].isRegistered)
        XCTAssertFalse(controller.displayedShortcutStatuses[1].isVerified)
        XCTAssertEqual(controller.displayedShortcutStatuses[1].verificationCount, 0)
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
    func testSampleGuideDismissDuringAnimatedClosePreservesCommittedSelection() {
        let popover = TestSampleGuidePopover()
        popover.completesCloseImmediately = false
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
                canRestoreLastMarkdown: true,
                canShowLastRender: true
            )
        )

        controller.choose(.short)
        controller.dismiss()

        XCTAssertEqual(popover.closeCount, 1)
        XCTAssertTrue(deliveredSelections.isEmpty)

        popover.completeClose()

        XCTAssertEqual(deliveredSelections, [.short])
        XCTAssertEqual(statusButton.cell?.isHighlighted, false)
    }

    @MainActor
    func testSampleGuideRecoversWhenPopoverCannotRemainShown() {
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
        popover.hideWithoutDelegate()

        controller.choose(.table)
        controller.choose(.short)

        XCTAssertEqual(deliveredSelections, [.table])
        XCTAssertEqual(statusButton.cell?.isHighlighted, false)
    }

    @MainActor
    func testSampleGuideShowFailureDoesNotLeaveAnInteractiveHalfOpenState() {
        let popover = TestSampleGuidePopover()
        popover.showsWhenRequested = false
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
        controller.choose(.short)

        XCTAssertFalse(popover.isShown)
        XCTAssertNil(popover.contentViewController)
        XCTAssertTrue(deliveredSelections.isEmpty)
        XCTAssertEqual(statusButton.cell?.isHighlighted, false)
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
        XCTAssertEqual(controller.displayedContentSize, NSSize(width: 560, height: 570))
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
private final class WelcomeLaunchAtLoginServiceStub: LaunchAtLoginServicing {
    enum Operation: Equatable {
        case register
        case unregister
        case openSystemSettings
    }

    var status: LaunchAtLoginStatus
    var statusAfterRegister: LaunchAtLoginStatus?
    var statusAfterUnregister: LaunchAtLoginStatus?
    private(set) var operations: [Operation] = []

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        operations.append(.register)
        if let statusAfterRegister {
            status = statusAfterRegister
        }
    }

    func unregister() throws {
        operations.append(.unregister)
        if let statusAfterUnregister {
            status = statusAfterUnregister
        }
    }

    func openSystemSettings() {
        operations.append(.openSystemSettings)
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
    var showsWhenRequested = true
    var completesCloseImmediately = true
    private(set) var closeCount = 0
    private var isClosing = false

    func show(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        preferredEdge: NSRectEdge
    ) {
        guard showsWhenRequested else { return }
        isShown = true
        isClosing = false
    }

    func close() {
        guard isShown, !isClosing else { return }
        closeCount += 1
        isClosing = true
        delegate?.popoverWillClose?(Notification(name: NSPopover.willCloseNotification))
        if completesCloseImmediately {
            completeClose()
        }
    }

    func completeClose() {
        guard isClosing else { return }
        isShown = false
        isClosing = false
        delegate?.popoverDidClose?(Notification(name: NSPopover.didCloseNotification))
    }

    func hideWithoutDelegate() {
        isShown = false
        isClosing = false
    }
}
