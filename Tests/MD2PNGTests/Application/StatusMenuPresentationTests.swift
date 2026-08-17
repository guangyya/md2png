import Foundation
import XCTest
@testable import MD2PNG

final class StatusMenuPresentationTests: XCTestCase {
    func testMenuLayoutKeepsFrequentCommandsFirstAndEveryCommandStable() {
        XCTAssertEqual(StatusMenuLayout.sections, [
            [.renderClipboard, .showLastRender],
            [.rerenderLastMarkdown, .restoreLastMarkdown],
            [.theme, .outputWidth, .examples],
            [.launchAtLogin, .showWelcome, .about],
            [.quit]
        ])

        let flattenedCommands = StatusMenuLayout.sections.flatMap { $0 }
        XCTAssertEqual(flattenedCommands.count, StatusMenuCommand.allCases.count)
        XCTAssertEqual(Set(flattenedCommands), Set(StatusMenuCommand.allCases))
    }

    func testEmptyAndImageClipboardStatesDisableOnlyClipboardRender() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let empty = makePresentation(
            clipboardContainsMarkdown: false,
            localizationBundle: english
        )

        XCTAssertEqual(empty[.renderClipboard].title, "Render Clipboard as Image")
        XCTAssertFalse(empty[.renderClipboard].isEnabled)
        XCTAssertFalse(empty[.showLastRender].isEnabled)
        XCTAssertFalse(empty[.rerenderLastMarkdown].isEnabled)
        XCTAssertFalse(empty[.restoreLastMarkdown].isEnabled)
        XCTAssertTrue(empty[.theme].isEnabled)
        XCTAssertTrue(empty[.outputWidth].isEnabled)
        XCTAssertTrue(empty[.examples].isEnabled)
        XCTAssertTrue(empty[.showWelcome].isEnabled)
        XCTAssertTrue(empty[.about].isEnabled)
        XCTAssertTrue(empty[.quit].isEnabled)
    }

    func testTextAndSuccessfulRenderEnableExpectedCommands() throws {
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))
        let presentation = makePresentation(
            clipboardContainsMarkdown: true,
            hasLastSource: true,
            hasLastRender: true,
            localizationBundle: chinese
        )

        XCTAssertTrue(presentation[.renderClipboard].isEnabled)
        XCTAssertTrue(presentation[.showLastRender].isEnabled)
        XCTAssertTrue(presentation[.rerenderLastMarkdown].isEnabled)
        XCTAssertTrue(presentation[.restoreLastMarkdown].isEnabled)
        XCTAssertEqual(presentation[.rerenderLastMarkdown].title, "重新渲染上次的 Markdown")
        XCTAssertEqual(presentation[.theme].title, "主题")
        XCTAssertEqual(presentation[.outputWidth].title, "输出宽度")
    }

    func testRenderingAndUpdateInstallationKeepPreviewAndAppCommandsAvailable() {
        for state in [
            StatusMenuState(
                clipboardContainsMarkdown: true,
                hasLastSource: true,
                hasLastRender: true,
                isRendering: true,
                isUpdateInstallPending: false
            ),
            StatusMenuState(
                clipboardContainsMarkdown: true,
                hasLastSource: true,
                hasLastRender: true,
                isRendering: false,
                isUpdateInstallPending: true
            )
        ] {
            let presentation = StatusMenuPresentation(state: state)
            XCTAssertFalse(presentation[.renderClipboard].isEnabled)
            XCTAssertTrue(presentation[.showLastRender].isEnabled)
            XCTAssertFalse(presentation[.rerenderLastMarkdown].isEnabled)
            XCTAssertFalse(presentation[.restoreLastMarkdown].isEnabled)
            XCTAssertFalse(presentation[.theme].isEnabled)
            XCTAssertFalse(presentation[.outputWidth].isEnabled)
            XCTAssertFalse(presentation[.examples].isEnabled)
            XCTAssertTrue(presentation[.showWelcome].isEnabled)
            XCTAssertTrue(presentation[.about].isEnabled)
            XCTAssertTrue(presentation[.quit].isEnabled)
        }
    }

    func testSampleGuideUsesCurrentLocalizedMenuCopy() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))
        let englishCopy = SampleGuideCopy(localizationBundle: english)
        let chineseCopy = SampleGuideCopy(localizationBundle: chinese)

        XCTAssertEqual(englishCopy.rerenderLastMarkdown, "Re-render Last Markdown")
        XCTAssertEqual(englishCopy.theme, "Theme")
        XCTAssertEqual(
            englishCopy.launchAtLoginTitle(for: .allowInSystemSettings),
            "Allow Launch at Login…"
        )
        XCTAssertEqual(chineseCopy.rerenderLastMarkdown, "重新渲染上次的 Markdown")
        XCTAssertEqual(chineseCopy.theme, "主题")
        XCTAssertEqual(
            chineseCopy.launchAtLoginTitle(for: .unavailable),
            "登录时启动不可用"
        )
    }

    @MainActor
    func testShortcutConflictKeepsEquivalentMenuCommandsAndAccessibleNames() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))
        let presentation = makePresentation(
            clipboardContainsMarkdown: true,
            hasLastSource: true,
            hasLastRender: true
        )
        let render = GlobalHotKey.Registration.render {}
        let showLastRender = GlobalHotKey.Registration.showLastRender {}

        XCTAssertEqual(render.commandTitle, presentation[.renderClipboard].title)
        XCTAssertEqual(showLastRender.commandTitle, presentation[.showLastRender].title)
        XCTAssertEqual(render.shortcutAccessibilityName, "Control-Command-X")
        XCTAssertEqual(showLastRender.shortcutAccessibilityName, "Control-Command-Z")
        XCTAssertTrue(presentation[.renderClipboard].isEnabled)
        XCTAssertTrue(presentation[.showLastRender].isEnabled)
        XCTAssertEqual(
            L10n.text("hud.shortcut_conflict", defaultValue: "", bundle: english),
            "Global shortcut unavailable — use the same command from the md2png menu"
        )
        XCTAssertEqual(
            L10n.text("hud.shortcut_conflict", defaultValue: "", bundle: chinese),
            "全局快捷键不可用——请从 md2png 菜单执行同一命令"
        )
    }

    private func makePresentation(
        clipboardContainsMarkdown: Bool,
        hasLastSource: Bool = false,
        hasLastRender: Bool = false,
        localizationBundle: Bundle? = nil
    ) -> StatusMenuPresentation {
        StatusMenuPresentation(
            state: StatusMenuState(
                clipboardContainsMarkdown: clipboardContainsMarkdown,
                hasLastSource: hasLastSource,
                hasLastRender: hasLastRender,
                isRendering: false,
                isUpdateInstallPending: false
            ),
            localizationBundle: localizationBundle
        )
    }
}
