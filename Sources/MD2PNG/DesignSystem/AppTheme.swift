import SwiftUI

enum AppTheme {
    enum Metrics {
        static let cardCornerRadius: CGFloat = 10
        static let shortcutCornerRadius: CGFloat = 7
        static let cardBorderWidth: CGFloat = 0.5
    }

    enum Opacity {
        static let backdropCyan = 0.055
        static let backdropPurple = 0.05
        static let cardControlBackground = 0.72
        static let cardAccent = 0.045
        static let cardBorder = 0.1
        static let cardHover = 0.06
        static let prominentCardHover = 0.12
        static let activeShortcutFill = 0.18
    }

    enum CardHighlightStyle {
        case overlay
        case leadingGradient
    }

    enum Spacing {
        static let windowHorizontal: CGFloat = 22
        static let windowTop: CGFloat = 18
        static let windowBottom: CGFloat = 14
        static let contentGroups: CGFloat = 12
        static let section: CGFloat = 7
        static let sectionHeading: CGFloat = 4
        static let footerHorizontal: CGFloat = 22
        static let footerVertical: CGFloat = 11
    }

    enum Shape {
        static var card: RoundedRectangle {
            RoundedRectangle(
                cornerRadius: Metrics.cardCornerRadius,
                style: .continuous
            )
        }

        static var shortcut: RoundedRectangle {
            RoundedRectangle(cornerRadius: Metrics.shortcutCornerRadius)
        }
    }

    struct ShortcutControlStyle: Equatable {
        let fillOpacity: Double
        let borderOpacity: Double
        let borderWidth: CGFloat

        init(contrast: ColorSchemeContrast) {
            if contrast == .increased {
                fillOpacity = 0.14
                borderOpacity = 0.62
                borderWidth = 1.2
            } else {
                fillOpacity = 0.08
                borderOpacity = 0.24
                borderWidth = 0.6
            }
        }
    }
}
