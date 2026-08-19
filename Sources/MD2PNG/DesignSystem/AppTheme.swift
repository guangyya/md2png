import SwiftUI

enum AppTheme {
    enum Metrics {
        static let cardCornerRadius: CGFloat = 10
        static let shortcutCornerRadius: CGFloat = 7
    }

    enum Opacity {
        static let activeShortcutFill = 0.18
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

    struct CardSurfaceStyle: Equatable {
        let borderOpacity: Double
        let borderWidth: CGFloat
        let highlightFillOpacity: Double
        let highlightBorderOpacity: Double

        init(contrast: ColorSchemeContrast) {
            if contrast == .increased {
                borderOpacity = 0.48
                borderWidth = 1.25
                highlightFillOpacity = 0.16
                highlightBorderOpacity = 0.72
            } else {
                borderOpacity = 0.14
                borderWidth = 0.75
                highlightFillOpacity = 0.08
                highlightBorderOpacity = 0.34
            }
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
