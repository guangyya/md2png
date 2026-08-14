import Foundation

enum RenderWidthPreset: String, CaseIterable {
    case compact
    case standard
    case wide

    var cardMaximumWidth: Int {
        switch self {
        case .compact:
            return 720
        case .standard:
            return 1_120
        case .wide:
            return 1_520
        }
    }

    var menuTitle: String {
        switch self {
        case .compact:
            return L10n.text("render_width.compact", defaultValue: "Compact")
        case .standard:
            return L10n.text("render_width.standard", defaultValue: "Standard")
        case .wide:
            return L10n.text("render_width.wide", defaultValue: "Wide")
        }
    }
}

struct RenderWidthPreference {
    static let defaultsKey = "Render.widthPreset.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedPreset: RenderWidthPreset {
        guard let rawValue = defaults.string(forKey: Self.defaultsKey) else {
            return .standard
        }
        return RenderWidthPreset(rawValue: rawValue) ?? .standard
    }

    func select(_ preset: RenderWidthPreset) {
        defaults.set(preset.rawValue, forKey: Self.defaultsKey)
    }
}
