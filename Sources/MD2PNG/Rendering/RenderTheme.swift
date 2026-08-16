import Foundation

enum RenderTheme: String, CaseIterable {
    case cleanLight
    case warmPaper
    case dark

    var menuTitle: String {
        switch self {
        case .cleanLight:
            return L10n.text("render_theme.clean_light", defaultValue: "Clean Light")
        case .warmPaper:
            return L10n.text("render_theme.warm_paper", defaultValue: "Warm Paper")
        case .dark:
            return L10n.text("render_theme.dark", defaultValue: "Dark")
        }
    }
}

struct RenderThemePreference {
    static let defaultsKey = "Render.theme.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedTheme: RenderTheme {
        guard let rawValue = defaults.string(forKey: Self.defaultsKey) else {
            return .cleanLight
        }
        return RenderTheme(rawValue: rawValue) ?? .cleanLight
    }

    func select(_ theme: RenderTheme) {
        defaults.set(theme.rawValue, forKey: Self.defaultsKey)
    }
}
