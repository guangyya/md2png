import AppKit
import SwiftUI
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
        let englishGuide = SampleGuideCopy(localizationBundle: englishBundle)
        let chineseGuide = SampleGuideCopy(localizationBundle: chineseBundle)

        XCTAssertEqual(english.windowTitle, "Welcome to md2png")
        XCTAssertEqual(english.trySample, "Try an Example")
        XCTAssertTrue(english.trySampleHelp.contains("example"))
        XCTAssertEqual(english.replayDemo, "Replay workflow demo")
        XCTAssertEqual(english.copyStepCompletionDetail, "Copy in any app")
        XCTAssertEqual(english.renderStepCompletionDetail, "Render locally")
        XCTAssertEqual(english.pasteStepCompletionDetail, "Review, then send")
        XCTAssertEqual(english.shortcutDetected, "Detected")
        XCTAssertEqual(english.shortcutVerified, "Works")
        XCTAssertEqual(english.launchAtLoginTitle, "Launch at Login")
        XCTAssertEqual(english.launchAtLoginOptional, "Optional")
        XCTAssertEqual(english.launchAtLoginOn, "On")
        XCTAssertEqual(english.launchAtLoginOff, "Off")
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
        XCTAssertEqual(chinese.replayDemo, "重新播放操作演示")
        XCTAssertEqual(chinese.copyStepCompletionDetail, "在任意应用中复制")
        XCTAssertEqual(chinese.renderStepCompletionDetail, "在本机渲染")
        XCTAssertEqual(chinese.pasteStepCompletionDetail, "检查后再发送")
        XCTAssertEqual(englishGuide.title, "Find Examples in the md2png menu")
        XCTAssertEqual(chineseGuide.title, "在 md2png 菜单中找到“示例”")
        XCTAssertEqual(englishGuide.exampleTitle(.short), "Short Example")
        XCTAssertEqual(chineseGuide.exampleTitle(.short), "简短示例")
        XCTAssertEqual(chinese.shortcutDetected, "已检测")
        XCTAssertEqual(chinese.shortcutVerified, "已生效")
        XCTAssertEqual(chinese.shortcutUnavailable, "已占用")
        XCTAssertEqual(chinese.launchAtLoginTitle, "登录时启动")
        XCTAssertEqual(chinese.launchAtLoginOptional, "可选")
        XCTAssertEqual(chinese.launchAtLoginOn, "已开启")
        XCTAssertEqual(chinese.launchAtLoginOff, "已关闭")
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
        XCTAssertEqual(service.operations, [.register, .openSystemSettings])
        XCTAssertEqual(state.presentation.menuAction, .allowInSystemSettings)

        state.performPrimaryAction()
        XCTAssertEqual(
            service.operations,
            [.register, .openSystemSettings, .openSystemSettings]
        )

        service.status = .enabled
        service.statusAfterUnregister = .notRegistered
        state.refresh()
        XCTAssertEqual(state.presentation.menuAction, .disable)

        state.performPrimaryAction()
        XCTAssertEqual(
            service.operations,
            [.register, .openSystemSettings, .openSystemSettings, .unregister]
        )
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
    func testWelcomeOpensSettingsWithoutReevaluatingPrimaryActionAfterRegistration() {
        let service = SequencedWelcomeLaunchAtLoginServiceStub(statuses: [
            .notRegistered,
            .notRegistered,
            .requiresApproval,
            .enabled
        ])
        let state = WelcomeLaunchAtLoginState(
            controller: LaunchAtLoginController(service: service)
        )

        state.performPrimaryAction()

        XCTAssertEqual(service.operations, [.register, .openSystemSettings])
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

    func testWelcomeAndSampleGuideLayoutsStayInsideSmallVisibleFrames() {
        XCTAssertEqual(
            WelcomeLayout.contentSize(maximumContentSize: NSSize(width: 520, height: 430)),
            NSSize(width: 520, height: 430)
        )
        XCTAssertEqual(
            WelcomeLayout.contentSize(maximumContentSize: NSSize(width: 800, height: 900)),
            WelcomeLayout.preferredContentSize
        )
        XCTAssertEqual(
            SampleGuideLayout.contentSize(visibleFrame: NSRect(
                x: 1_440,
                y: 24,
                width: 400,
                height: 300
            )),
            NSSize(width: 376, height: 276)
        )
        XCTAssertGreaterThan(
            GuideMenuHighlightStyle(contrast: .increased).borderWidth,
            GuideMenuHighlightStyle(contrast: .standard).borderWidth
        )
        XCTAssertGreaterThan(
            GuideMenuHighlightStyle(contrast: .increased).recommendedFillOpacity,
            GuideMenuHighlightStyle(contrast: .standard).recommendedFillOpacity
        )

        let visibleFrame = NSRect(x: -500, y: 25, width: 500, height: 400)
        let oversizedOrigin = WelcomeWindowPlacement.centeredOrigin(
            windowSize: NSSize(width: 560, height: 470),
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(oversizedOrigin, visibleFrame.origin)
    }

    @MainActor
    func testLargeAccessibilityWelcomeStaysVisibleAndExposesReplaySeparately() throws {
        _ = NSApplication.shared
        let visibleFrame = NSRect(x: 100, y: 80, width: 590, height: 540)
        let bundles = [
            try XCTUnwrap(L10n.localizedBundle(for: "en")),
            try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))
        ]

        for bundle in bundles {
            let (defaults, suiteName) = try makeDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let copy = WelcomeCopy(localizationBundle: bundle)
            let controller = WelcomeController(
                preference: WelcomePreference(defaults: defaults),
                localizationBundle: bundle,
                visibleFrameProvider: { visibleFrame },
                dynamicTypeSize: .accessibility3,
                onTrySample: {}
            )
            controller.show(shortcuts: [WelcomeShortcutStatus(
                id: 1,
                title: copy.renderStepTitle,
                shortcutGlyphs: "⌃⌘X",
                shortcutAccessibilityName: "Control-Command-X",
                isRegistered: true
            )])
            defer { controller.close() }

            let window = try XCTUnwrap(controller.window)
            let contentView = try XCTUnwrap(window.contentView)
            contentView.layoutSubtreeIfNeeded()

            XCTAssertGreaterThanOrEqual(window.frame.minX, visibleFrame.minX)
            XCTAssertGreaterThanOrEqual(window.frame.minY, visibleFrame.minY)
            XCTAssertLessThanOrEqual(window.frame.maxX, visibleFrame.maxX)
            XCTAssertLessThanOrEqual(window.frame.maxY, visibleFrame.maxY)
            XCTAssertNotNil(firstSubview(ofType: NSScrollView.self, in: contentView))

            let replayButton = try XCTUnwrap(firstSubview(
                ofType: NSButton.self,
                in: contentView,
                where: { $0.identifier == WelcomeReplayButton.identifier }
            ))
            XCTAssertEqual(replayButton.accessibilityRole(), .button)
            XCTAssertEqual(replayButton.accessibilityLabel(), copy.replayDemo)
            XCTAssertEqual(replayButton.keyEquivalent, "r")
            XCTAssertEqual(replayButton.keyEquivalentModifierMask, [.command])
            XCTAssertTrue(contentView.bounds.contains(
                replayButton.convert(replayButton.bounds, to: contentView)
            ))
        }
    }

    @MainActor
    func testStandardWelcomeFooterKeepsNotesAndActionsOnOneRow() throws {
        _ = NSApplication.shared
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = WelcomeController(
            preference: WelcomePreference(defaults: defaults),
            visibleFrameProvider: { NSRect(x: 0, y: 0, width: 900, height: 800) },
            onTrySample: {}
        )
        controller.show(shortcuts: [])
        defer { controller.close() }

        let contentView = try XCTUnwrap(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let notes = try XCTUnwrap(firstSubview(
            ofType: NSView.self,
            in: contentView,
            where: { $0.identifier == WelcomeFooterLayoutMarker.notesIdentifier }
        ))
        let actions = try XCTUnwrap(firstSubview(
            ofType: NSView.self,
            in: contentView,
            where: { $0.identifier == WelcomeFooterLayoutMarker.actionsIdentifier }
        ))
        let notesFrame = notes.convert(notes.bounds, to: contentView)
        let actionFrame = actions.convert(actions.bounds, to: contentView)
        let verticalOverlap = min(notesFrame.maxY, actionFrame.maxY)
            - max(notesFrame.minY, actionFrame.minY)

        XCTAssertGreaterThan(verticalOverlap, 0, "notes=\(notesFrame), action=\(actionFrame)")
    }

    @MainActor
    func testSampleGuideRendersScrollableLocalizedAccessibilityLayouts() throws {
        _ = NSApplication.shared
        let contentSize = NSSize(width: 420, height: 300)
        let bundles = [
            try XCTUnwrap(L10n.localizedBundle(for: "en")),
            try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))
        ]

        for bundle in bundles {
            let hostingController = NSHostingController(rootView:
                SampleGuideView(
                    copy: SampleGuideCopy(localizationBundle: bundle),
                    contentSize: contentSize,
                    menuState: SampleGuideMenuState(
                        canRestoreLastMarkdown: true,
                        canShowLastRender: true
                    ),
                    onChoose: { _ in },
                    initialPhase: .submenu,
                    runsRevealSequence: false
                )
                .environment(\.dynamicTypeSize, .accessibility3)
            )
            let window = makeTestWindow(
                contentSize: contentSize,
                contentViewController: hostingController
            )
            let contentView = try XCTUnwrap(window.contentView)
            contentView.layoutSubtreeIfNeeded()

            XCTAssertEqual(contentView.bounds.size, contentSize)
            XCTAssertNotNil(firstSubview(ofType: NSScrollView.self, in: contentView))
            let image = try XCTUnwrap(contentView.bitmapImageRepForCachingDisplay(
                in: contentView.bounds
            ))
            contentView.cacheDisplay(in: contentView.bounds, to: image)
            XCTAssertEqual(
                image.pixelsWide,
                Int(contentSize.width * window.backingScaleFactor)
            )
            XCTAssertEqual(
                image.pixelsHigh,
                Int(contentSize.height * window.backingScaleFactor)
            )
        }
    }

    func testWelcomeAnimationProgressMovesThroughTheWholeWorkflow() {
        let copying = WelcomeAnimationProgress(phase: .copy)
        let rendering = WelcomeAnimationProgress(phase: .render)
        let pasting = WelcomeAnimationProgress(phase: .paste)

        XCTAssertEqual(copying.cardTravel, -1)
        XCTAssertEqual(copying.imageReveal, 0)
        XCTAssertEqual(copying.detailIndex, 0)
        XCTAssertFalse(copying.showsCompletedJourney)
        XCTAssertEqual(copying.shortcutOpacity(for: .copy), 1)
        XCTAssertEqual(copying.shortcutOpacity(for: .render), 0)
        XCTAssertEqual(rendering.cardTravel, 0)
        XCTAssertEqual(rendering.keyPress, 1)
        XCTAssertGreaterThan(rendering.imageReveal, 0.5)
        XCTAssertEqual(rendering.detailIndex, 1)
        XCTAssertEqual(rendering.shortcutOpacity(for: .render), 1)
        XCTAssertEqual(pasting.cardTravel, 1)
        XCTAssertEqual(pasting.imageReveal, 1)
        XCTAssertEqual(pasting.detailIndex, 2)
        XCTAssertFalse(pasting.showsCompletedJourney)
        XCTAssertEqual(pasting.shortcutOpacity(for: .paste), 1)
        XCTAssertEqual(WelcomeAnimationProgress.reducedMotion.imageReveal, 1)
        XCTAssertTrue(WelcomeAnimationProgress.reducedMotion.showsCompletedJourney)
        XCTAssertTrue(
            WelcomeCompletedJourneyStage.all.allSatisfy {
                WelcomeAnimationProgress.reducedMotion.shortcutOpacity(for: $0.phase) == 1
            }
        )
        XCTAssertEqual(
            WelcomeCompletedJourneyStage.all.map(\.phase),
            [.copy, .render, .paste]
        )
        XCTAssertEqual(
            WelcomeCompletedJourneyStage.all.map(\.cardOffset),
            [-154, 0, 154]
        )
        XCTAssertEqual(
            WelcomeCompletedJourneyStage.all.map(\.shortcutKeys),
            [["⌘", "C"], ["⌃", "⌘", "X"], ["⌘", "V"]]
        )

        let copyPulse = WelcomeCardMotion(
            progress: copying,
            copyEmphasis: 1,
            isSettled: false
        )
        XCTAssertGreaterThan(copyPulse.scale, 1)
        XCTAssertLessThan(copyPulse.verticalOffset, 0)
        XCTAssertGreaterThan(copyPulse.copyGlowOpacity, 0)

        let settledRender = WelcomeCardMotion(
            progress: rendering,
            copyEmphasis: 1,
            isSettled: true
        )
        XCTAssertEqual(settledRender.rotation, 0)
        XCTAssertEqual(settledRender.scale, 1)
        XCTAssertEqual(settledRender.verticalOffset, 0)
        XCTAssertEqual(settledRender.copyGlowOpacity, 0)
    }

    func testWelcomeReplayAndShortcutContrastStylesKeepControlsDistinct() {
        XCTAssertEqual(WelcomeWorkflowLayout.stageWidth, 128)
        XCTAssertEqual(WelcomeWorkflowLayout.stageOffset, 154)
        XCTAssertEqual(WelcomeWorkflowLayout.trackHeight, 70)
        XCTAssertLessThan(
            WelcomeWorkflowLayout.shortcutVerticalOffset + 13,
            WelcomeWorkflowLayout.trackHeight / 2
        )

        let standard = WelcomeShortcutContrastStyle(contrast: .standard)
        let increased = WelcomeShortcutContrastStyle(contrast: .increased)
        XCTAssertGreaterThanOrEqual(standard.containerBorderOpacity, 0.25)
        XCTAssertGreaterThanOrEqual(standard.keyBorderOpacity, 0.3)
        XCTAssertGreaterThan(increased.containerBorderWidth, standard.containerBorderWidth)
        XCTAssertGreaterThan(increased.keyBorderWidth, standard.keyBorderWidth)
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

        for hiddenPhase in [SampleGuidePhase.mainMenu, .examplesFocused] {
            let policy = SampleGuideInteractionPolicy(phase: hiddenPhase)
            XCTAssertFalse(policy.showsExamples)
            XCTAssertFalse(policy.acceptsExampleInput)
            XCTAssertTrue(policy.hidesExamplesFromAccessibility)
        }
        let visiblePolicy = SampleGuideInteractionPolicy(phase: .submenu)
        XCTAssertTrue(visiblePolicy.showsExamples)
        XCTAssertTrue(visiblePolicy.acceptsExampleInput)
        XCTAssertFalse(visiblePolicy.hidesExamplesFromAccessibility)
    }

    func testSampleGuideKeepsACompactDemoMenu() {
        XCTAssertEqual(SampleGuideLayout.menuSections, [
            [.renderClipboard, .showLastRender],
            [.theme, .outputWidth, .examples],
            [.about, .quit]
        ])
        XCTAssertEqual(SampleGuideLayout.menuSections.flatMap { $0 }.count, 7)
    }

    func testSampleGuidePlacementKeepsTheMainMenuNearestTheStatusItem() {
        let visibleFrame = NSRect(x: 0, y: 24, width: 1_440, height: 876)
        let buttonBounds = NSRect(x: 0, y: 0, width: 22, height: 22)
        let leftPlacement = SampleGuidePlacement.resolve(
            buttonBounds: buttonBounds,
            buttonFrameInScreen: NSRect(x: 8, y: 878, width: 22, height: 22),
            visibleFrame: visibleFrame
        )
        let rightPlacement = SampleGuidePlacement.resolve(
            buttonBounds: buttonBounds,
            buttonFrameInScreen: NSRect(x: 1_410, y: 878, width: 22, height: 22),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(leftPlacement.examplesEdge, .trailing)
        XCTAssertEqual(leftPlacement.positioningRect, buttonBounds)
        XCTAssertEqual(rightPlacement.examplesEdge, .leading)
        XCTAssertEqual(rightPlacement.positioningRect, buttonBounds)

        let fallback = SampleGuidePlacement.resolve(
            buttonBounds: buttonBounds,
            buttonFrameInScreen: nil,
            visibleFrame: nil
        )
        XCTAssertEqual(fallback.examplesEdge, .trailing)
        XCTAssertEqual(fallback.positioningRect, buttonBounds)
    }

    func testSampleGuideKeyboardPolicyTraversesActivatesAndDismisses() {
        let values = ExampleKind.allCases.map(\.rawValue)
        XCTAssertEqual(
            SampleGuideFocusOrder.movedFocus(from: nil, direction: .next),
            values.first
        )
        XCTAssertEqual(
            SampleGuideFocusOrder.movedFocus(from: values.first, direction: .previous),
            values.last
        )
        XCTAssertEqual(
            SampleGuideFocusOrder.movedFocus(from: values.last, direction: .next),
            values.first
        )
        XCTAssertEqual(
            SampleGuideKeyboardPolicy.action(
                for: .tab,
                modifiers: [],
                acceptsExampleInput: true
            ),
            .move(.next)
        )
        XCTAssertEqual(
            SampleGuideKeyboardPolicy.action(
                for: .tab,
                modifiers: [.shift],
                acceptsExampleInput: true
            ),
            .move(.previous)
        )
        XCTAssertEqual(
            SampleGuideKeyboardPolicy.action(
                for: .space,
                modifiers: [],
                acceptsExampleInput: true
            ),
            .activate
        )
        XCTAssertEqual(
            SampleGuideKeyboardPolicy.action(
                for: .escape,
                modifiers: [],
                acceptsExampleInput: false
            ),
            .dismiss
        )
        XCTAssertEqual(
            SampleGuideKeyboardPolicy.action(
                for: .downArrow,
                modifiers: [],
                acceptsExampleInput: false
            ),
            .ignore
        )
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
    func testSampleGuideRestoresPopoverSizeAfterInstallingHostingController() {
        let popover = TestSampleGuidePopover()
        popover.resetsContentSizeWhenInstallingController = true
        let controller = SampleGuideController(popover: popover) { _ in }

        controller.show(
            relativeTo: NSStatusBarButton(
                frame: NSRect(x: 0, y: 0, width: 22, height: 22)
            ),
            menuState: SampleGuideMenuState(
                canRestoreLastMarkdown: false,
                canShowLastRender: false
            )
        )

        XCTAssertEqual(popover.contentSize, SampleGuideLayout.preferredContentSize)
        XCTAssertEqual(
            popover.contentViewController?.preferredContentSize,
            SampleGuideLayout.preferredContentSize
        )
        XCTAssertEqual(
            popover.contentViewController?.view.frame.size,
            SampleGuideLayout.preferredContentSize
        )
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

    func testSampleGuideMenuStateUsesPresentationSnapshot() {
        let statusPresentation = StatusMenuPresentation(state: StatusMenuState(
            clipboardContainsMarkdown: false,
            hasLastSource: true,
            hasLastRender: true,
            isRendering: false,
            isUpdateInstallPending: false
        ))
        let launchPresentation = LaunchAtLoginPresentation(status: .requiresApproval)

        let state = SampleGuideMenuState(
            statusMenuPresentation: statusPresentation,
            launchAtLoginPresentation: launchPresentation
        )

        XCTAssertFalse(state.canRenderClipboard)
        XCTAssertTrue(state.canRerenderLastMarkdown)
        XCTAssertTrue(state.canRestoreLastMarkdown)
        XCTAssertTrue(state.canShowLastRender)
        XCTAssertEqual(state.launchAtLoginAction, .allowInSystemSettings)
        XCTAssertTrue(state.canUseLaunchAtLogin)
    }

    @MainActor
    private func makeTestWindow(
        contentSize: NSSize,
        contentViewController: NSViewController
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = contentViewController
        window.setContentSize(contentSize)
        return window
    }

    @MainActor
    private func firstSubview<ViewType: NSView>(
        ofType type: ViewType.Type,
        in view: NSView?,
        where predicate: (ViewType) -> Bool = { _ in true }
    ) -> ViewType? {
        allSubviews(ofType: type, in: view).first(where: predicate)
    }

    @MainActor
    private func allSubviews<ViewType: NSView>(
        ofType type: ViewType.Type,
        in view: NSView?
    ) -> [ViewType] {
        guard let view else { return [] }
        var matches: [ViewType] = []
        var pending = [view]
        var visited: Set<ObjectIdentifier> = []
        while let candidate = pending.popLast() {
            guard visited.insert(ObjectIdentifier(candidate)).inserted else { continue }
            if let match = candidate as? ViewType {
                matches.append(match)
            }
            pending.append(contentsOf: candidate.subviews)
        }
        return matches
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
private final class SequencedWelcomeLaunchAtLoginServiceStub: LaunchAtLoginServicing {
    private var statuses: [LaunchAtLoginStatus]
    private var lastStatus: LaunchAtLoginStatus
    private(set) var operations: [WelcomeLaunchAtLoginServiceStub.Operation] = []

    init(statuses: [LaunchAtLoginStatus]) {
        precondition(!statuses.isEmpty)
        self.statuses = statuses
        lastStatus = statuses[0]
    }

    var status: LaunchAtLoginStatus {
        guard !statuses.isEmpty else { return lastStatus }
        lastStatus = statuses.removeFirst()
        return lastStatus
    }

    func register() throws {
        operations.append(.register)
    }

    func unregister() throws {
        operations.append(.unregister)
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
    var contentViewController: NSViewController? {
        didSet {
            if resetsContentSizeWhenInstallingController {
                contentSize = NSSize(width: 135, height: 19)
            }
        }
    }
    var isShown = false
    var showsWhenRequested = true
    var completesCloseImmediately = true
    var resetsContentSizeWhenInstallingController = false
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
