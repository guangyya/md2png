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
