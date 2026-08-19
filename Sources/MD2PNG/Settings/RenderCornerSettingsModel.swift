import Foundation

@MainActor
final class RenderCornerSettingsModel: ObservableObject {
    @Published private(set) var style: RenderCornerStyle

    private let preference: RenderCornerPreference

    init(preference: RenderCornerPreference = RenderCornerPreference()) {
        self.preference = preference
        style = preference.selectedStyle
    }

    var isEnabled: Bool {
        style == .rounded
    }

    func refresh() {
        style = preference.selectedStyle
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func setEnabled(_ isEnabled: Bool) {
        let newStyle: RenderCornerStyle = isEnabled ? .rounded : .square
        guard newStyle != style else { return }
        preference.select(newStyle)
        style = newStyle
    }
}
