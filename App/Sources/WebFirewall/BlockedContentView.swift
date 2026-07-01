import SwiftUI

struct BlockedContentView: View {
    let backToDMs: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("This part of Instagram is blocked")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("Minimal Instagram only opens DMs and media shared in DMs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: backToDMs) {
                Text("Back to DMs")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
    }
}
