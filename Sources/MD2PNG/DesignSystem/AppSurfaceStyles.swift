import AppKit
import SwiftUI

struct AppWindowBackdrop: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
    }
}

struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let isHighlighted: Bool

    private var style: AppTheme.CardSurfaceStyle {
        AppTheme.CardSurfaceStyle(contrast: colorSchemeContrast)
    }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Color(nsColor: .controlBackgroundColor)
                    if isHighlighted {
                        Color.accentColor.opacity(style.highlightFillOpacity)
                    }
                }
                .clipShape(AppTheme.Shape.card)
                .allowsHitTesting(false)
            }
            .overlay {
                AppTheme.Shape.card.stroke(
                    isHighlighted
                        ? Color.accentColor.opacity(style.highlightBorderOpacity)
                        : Color.primary.opacity(style.borderOpacity),
                    lineWidth: style.borderWidth
                )
                .allowsHitTesting(false)
            }
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
    func appCardStyle(isHighlighted: Bool = false) -> some View {
        modifier(AppCardStyle(isHighlighted: isHighlighted))
    }

    func appShortcutControlStyle(isActive: Bool = false) -> some View {
        modifier(AppShortcutControlModifier(isActive: isActive))
    }

    func appWindowFooterStyle() -> some View {
        background(Color(nsColor: .windowBackgroundColor))
    }
}
