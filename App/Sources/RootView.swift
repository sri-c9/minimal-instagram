import SwiftUI
import IGCore

/// Placeholder root screen. Proves the app target links the IGCore package and
/// renders SwiftUI. Replaced by the real Inbox → Thread → Reel navigation during
/// implementation.
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Minimal Instagram")
                .font(.title2.weight(.medium))
            Text("Setup OK · IGCore \(IGCore.version)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("You're all caught up")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
