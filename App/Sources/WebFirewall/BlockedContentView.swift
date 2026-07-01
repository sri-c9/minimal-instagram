import SwiftUI

struct BlockedContentView: View {
    let backToDMs: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("This Instagram route is blocked")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("Minimal Instagram keeps this WebView focused on DMs and media opened from DMs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: backToDMs) {
                Text("Back to DMs")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Returns to your last direct message route")
        }
        .padding(24)
        .frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
        .accessibilityElement(children: .contain)
    }
}
