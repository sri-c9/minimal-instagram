import SwiftUI

/// Covers the page edge to edge: the route behind it is the thing being kept out
/// of view, so none of it shows through.
struct BlockedContentView: View {
    let displayName: String
    let backToDMs: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "door.left.hand.closed")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Not part of your DMs")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Sidedoor opens \(displayName) messages and the media shared in them, and leaves the rest closed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 320)

            Spacer()

            Button(action: backToDMs) {
                Text("Back to DMs")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: 360)
            .accessibilityHint("Returns to your last direct message route")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    BlockedContentView(displayName: "Instagram") {}
}
