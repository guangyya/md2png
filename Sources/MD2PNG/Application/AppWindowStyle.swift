import AppKit
import SwiftUI

struct AppWindowBackdrop: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.cyan.opacity(0.055), location: 0),
                .init(color: Color(nsColor: .windowBackgroundColor), location: 0.42),
                .init(color: Color.purple.opacity(0.05), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct AppWindowCardBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .controlBackgroundColor).opacity(0.72),
                Color.accentColor.opacity(0.045)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct AppWindowCardBorder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.accentColor.opacity(0.1), lineWidth: 0.5)
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

struct AppShortcutControlContrastStyle: Equatable {
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
