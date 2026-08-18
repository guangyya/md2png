import SwiftUI
import XCTest
@testable import MD2PNG

final class AppThemeTests: XCTestCase {
    func testSharedSurfaceMetricsPreserveTheReviewedVisualStyle() {
        XCTAssertEqual(AppTheme.Metrics.cardCornerRadius, 10)
        XCTAssertEqual(AppTheme.Metrics.shortcutCornerRadius, 7)
        XCTAssertEqual(AppTheme.Metrics.cardBorderWidth, 0.5)
        XCTAssertEqual(AppTheme.Spacing.windowHorizontal, 22)
        XCTAssertEqual(AppTheme.Spacing.contentGroups, 12)
        XCTAssertEqual(AppTheme.Spacing.footerVertical, 11)
        XCTAssertEqual(AppTheme.Opacity.prominentCardHover, 0.12)
    }

    func testShortcutControlStyleRespondsToIncreasedContrast() {
        let standard = AppTheme.ShortcutControlStyle(contrast: .standard)
        let increased = AppTheme.ShortcutControlStyle(contrast: .increased)

        XCTAssertGreaterThan(increased.fillOpacity, standard.fillOpacity)
        XCTAssertGreaterThan(increased.borderOpacity, standard.borderOpacity)
        XCTAssertGreaterThan(increased.borderWidth, standard.borderWidth)
    }
}
