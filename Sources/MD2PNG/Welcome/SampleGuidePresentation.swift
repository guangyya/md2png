import AppKit
import SwiftUI

enum SampleGuidePhase: Int, Equatable {
    case mainMenu
    case examplesFocused
    case submenu

    var highlightsExamples: Bool { self != .mainMenu }
    var showsSubmenu: Bool { self == .submenu }
    var acceptsSubmenuInput: Bool { self == .submenu }
}

struct SampleGuideInteractionPolicy: Equatable {
    let showsExamples: Bool
    let acceptsExampleInput: Bool
    let hidesExamplesFromAccessibility: Bool

    init(phase: SampleGuidePhase) {
        showsExamples = phase.showsSubmenu
        acceptsExampleInput = phase.acceptsSubmenuInput
        hidesExamplesFromAccessibility = !phase.acceptsSubmenuInput
    }
}

struct SampleGuideMenuState: Equatable {
    let canRestoreLastMarkdown: Bool
    let canShowLastRender: Bool
    let canRenderClipboard: Bool
    let canRerenderLastMarkdown: Bool

    init(
        canRestoreLastMarkdown: Bool,
        canShowLastRender: Bool,
        canRenderClipboard: Bool = true,
        canRerenderLastMarkdown: Bool = false
    ) {
        self.canRestoreLastMarkdown = canRestoreLastMarkdown
        self.canShowLastRender = canShowLastRender
        self.canRenderClipboard = canRenderClipboard
        self.canRerenderLastMarkdown = canRerenderLastMarkdown
    }

    init(statusMenuPresentation: StatusMenuPresentation) {
        canRestoreLastMarkdown = statusMenuPresentation[.restoreLastMarkdown].isEnabled
        canShowLastRender = statusMenuPresentation[.showLastRender].isEnabled
        canRenderClipboard = statusMenuPresentation[.renderClipboard].isEnabled
        canRerenderLastMarkdown = statusMenuPresentation[.rerenderLastMarkdown].isEnabled
    }
}

enum SampleGuideLayout {
    static let preferredContentSize = NSSize(width: 548, height: 382)
    static let screenInset: CGFloat = 12
    static let menuMinimumWidth: CGFloat = 252
    static let menuSections: [[StatusMenuCommand]] = [
        [.renderClipboard, .renderMarkdownFile, .showLastRender],
        [.theme, .outputWidth, .examples],
        [.about, .quit]
    ]

    static func contentSize(visibleFrame: NSRect?) -> NSSize {
        guard let visibleFrame else { return preferredContentSize }
        return NSSize(
            width: max(
                1,
                min(
                    preferredContentSize.width,
                    visibleFrame.width - screenInset * 2
                )
            ),
            height: max(
                1,
                min(
                    preferredContentSize.height,
                    visibleFrame.height - screenInset * 2
                )
            )
        )
    }
}

enum SampleGuideExamplesEdge: Equatable {
    case leading
    case trailing
}

struct SampleGuidePlacement: Equatable {
    let positioningRect: NSRect
    let examplesEdge: SampleGuideExamplesEdge

    static func resolve(
        buttonBounds: NSRect
    ) -> SampleGuidePlacement {
        SampleGuidePlacement(
            positioningRect: buttonBounds,
            examplesEdge: .trailing
        )
    }
}

enum SampleGuideFocusDirection: Equatable {
    case previous
    case next
}

enum SampleGuideKeyboardAction: Equatable {
    case move(SampleGuideFocusDirection)
    case activate
    case dismiss
    case ignore
}

struct SampleGuideKeyboardPolicy {
    static func action(
        for key: KeyEquivalent,
        modifiers: EventModifiers,
        acceptsExampleInput: Bool
    ) -> SampleGuideKeyboardAction {
        if key == .escape { return .dismiss }
        guard acceptsExampleInput else { return .ignore }
        if key == .upArrow || (key == .tab && modifiers.contains(.shift)) {
            return .move(.previous)
        }
        if key == .downArrow || key == .tab {
            return .move(.next)
        }
        if key == .return || key == .space {
            return .activate
        }
        return .ignore
    }
}

struct SampleGuideFocusOrder {
    static func movedFocus(
        from rawValue: Int?,
        direction: SampleGuideFocusDirection
    ) -> Int? {
        let values = ExampleKind.allCases.map(\.rawValue)
        guard !values.isEmpty else { return nil }
        guard let rawValue, let index = values.firstIndex(of: rawValue) else {
            return direction == .next ? values.first : values.last
        }
        switch direction {
        case .previous:
            return values[(index - 1 + values.count) % values.count]
        case .next:
            return values[(index + 1) % values.count]
        }
    }
}

struct SampleGuideCopy {
    let title: String
    let clipboard: String
    let render: String
    let renderMarkdownFile: String
    let rerenderLastMarkdown: String
    let restoreLastMarkdown: String
    let showLastRender: String
    let theme: String
    let outputWidth: String
    let examples: String
    let settings: String
    let showWelcome: String
    let about: String
    let quit: String
    private let localizationBundle: Bundle?

    init(localizationBundle: Bundle? = nil) {
        self.localizationBundle = localizationBundle
        title = L10n.text(
            "welcome.sample_guide.title",
            defaultValue: "Find Examples in the md2png menu",
            bundle: localizationBundle
        )
        clipboard = L10n.text(
            "menu.clipboard",
            defaultValue: "Clipboard",
            bundle: localizationBundle
        )
        render = StatusMenuPresentation.title(
            for: .renderClipboard,
            localizationBundle: localizationBundle
        )
        renderMarkdownFile = StatusMenuPresentation.title(
            for: .renderMarkdownFile,
            localizationBundle: localizationBundle
        )
        rerenderLastMarkdown = StatusMenuPresentation.title(
            for: .rerenderLastMarkdown,
            localizationBundle: localizationBundle
        )
        restoreLastMarkdown = StatusMenuPresentation.title(
            for: .restoreLastMarkdown,
            localizationBundle: localizationBundle
        )
        showLastRender = StatusMenuPresentation.title(
            for: .showLastRender,
            localizationBundle: localizationBundle
        )
        theme = StatusMenuPresentation.title(
            for: .theme,
            localizationBundle: localizationBundle
        )
        outputWidth = StatusMenuPresentation.title(
            for: .outputWidth,
            localizationBundle: localizationBundle
        )
        examples = StatusMenuPresentation.title(
            for: .examples,
            localizationBundle: localizationBundle
        )
        settings = StatusMenuPresentation.title(
            for: .settings,
            localizationBundle: localizationBundle
        )
        showWelcome = StatusMenuPresentation.title(
            for: .showWelcome,
            localizationBundle: localizationBundle
        )
        about = StatusMenuPresentation.title(
            for: .about,
            localizationBundle: localizationBundle
        )
        quit = StatusMenuPresentation.title(
            for: .quit,
            localizationBundle: localizationBundle
        )
    }

    func exampleTitle(_ kind: ExampleKind) -> String {
        kind.menuTitle(localizationBundle: localizationBundle)
    }
}

struct GuideMenuHighlightStyle: Equatable {
    let borderWidth: CGFloat
    let recommendedFillOpacity: Double

    init(contrast: ColorSchemeContrast) {
        if contrast == .increased {
            borderWidth = 2
            recommendedFillOpacity = 0.2
        } else {
            borderWidth = 0.5
            recommendedFillOpacity = 0.09
        }
    }
}
