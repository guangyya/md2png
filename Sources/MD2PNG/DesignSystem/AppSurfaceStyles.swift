import AppKit
import SwiftUI

struct AppWindowBackdrop: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(
                    color: Color.cyan.opacity(AppTheme.Opacity.backdropCyan),
                    location: 0
                ),
                .init(
                    color: Color(nsColor: .windowBackgroundColor),
                    location: 0.42
                ),
                .init(
                    color: Color.purple.opacity(AppTheme.Opacity.backdropPurple),
                    location: 1
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct AppInlineStatusLabel: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct AppSectionHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sectionHeading) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AppCardStyle: ViewModifier {
    let isHighlighted: Bool
    let highlightStyle: AppTheme.CardHighlightStyle

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    LinearGradient(
                        colors: [
                            leadingColor,
                            Color.accentColor.opacity(AppTheme.Opacity.cardAccent)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    if isHighlighted && highlightStyle == .overlay {
                        Color.accentColor.opacity(AppTheme.Opacity.cardHover)
                    }
                }
                .clipShape(AppTheme.Shape.card)
            }
            .overlay {
                AppTheme.Shape.card.stroke(
                    Color.accentColor.opacity(AppTheme.Opacity.cardBorder),
                    lineWidth: AppTheme.Metrics.cardBorderWidth
                )
            }
    }

    private var leadingColor: Color {
        if isHighlighted && highlightStyle == .leadingGradient {
            return Color.accentColor.opacity(AppTheme.Opacity.prominentCardHover)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(
            AppTheme.Opacity.cardControlBackground
        )
    }
}

private struct AppShortcutControlModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let isActive: Bool

    private var style: AppTheme.ShortcutControlStyle {
        AppTheme.ShortcutControlStyle(contrast: colorSchemeContrast)
    }

    func body(content: Content) -> some View {
        content
            .background(
                Color.accentColor.opacity(
                    isActive ? AppTheme.Opacity.activeShortcutFill : style.fillOpacity
                ),
                in: AppTheme.Shape.shortcut
            )
            .overlay {
                AppTheme.Shape.shortcut.stroke(
                    Color.accentColor.opacity(style.borderOpacity),
                    lineWidth: style.borderWidth
                )
            }
    }
}

extension View {
    func appCardStyle(
        isHighlighted: Bool = false,
        highlightStyle: AppTheme.CardHighlightStyle = .overlay
    ) -> some View {
        modifier(
            AppCardStyle(
                isHighlighted: isHighlighted,
                highlightStyle: highlightStyle
            )
        )
    }

    func appShortcutControlStyle(isActive: Bool = false) -> some View {
        modifier(AppShortcutControlModifier(isActive: isActive))
    }

    func appWindowFooterStyle() -> some View {
        background(.regularMaterial)
    }
}
