import SwiftUI
import XCTest
@testable import MD2PNG

final class AppThemeTests: XCTestCase {
    func testSharedSurfaceMetricsPreserveTheCompactLayout() {
        XCTAssertEqual(AppTheme.Metrics.cardCornerRadius, 10)
        XCTAssertEqual(AppTheme.Metrics.shortcutCornerRadius, 7)
        XCTAssertEqual(AppTheme.Spacing.windowHorizontal, 22)
        XCTAssertEqual(AppTheme.Spacing.contentGroups, 12)
        XCTAssertEqual(AppTheme.Spacing.footerVertical, 11)
    }

    func testCardSurfaceStyleUsesClearerBoundariesForIncreasedContrast() {
        let standard = AppTheme.CardSurfaceStyle(contrast: .standard)
        let increased = AppTheme.CardSurfaceStyle(contrast: .increased)

        XCTAssertGreaterThan(increased.borderOpacity, standard.borderOpacity)
        XCTAssertGreaterThan(increased.borderWidth, standard.borderWidth)
        XCTAssertGreaterThan(
            increased.highlightFillOpacity,
            standard.highlightFillOpacity
        )
        XCTAssertGreaterThan(
            increased.highlightBorderOpacity,
            standard.highlightBorderOpacity
        )
    }

    func testShortcutControlStyleRespondsToIncreasedContrast() {
        let standard = AppTheme.ShortcutControlStyle(contrast: .standard)
        let increased = AppTheme.ShortcutControlStyle(contrast: .increased)

        XCTAssertGreaterThan(increased.fillOpacity, standard.fillOpacity)
        XCTAssertGreaterThan(increased.borderOpacity, standard.borderOpacity)
        XCTAssertGreaterThan(increased.borderWidth, standard.borderWidth)
    }

}
