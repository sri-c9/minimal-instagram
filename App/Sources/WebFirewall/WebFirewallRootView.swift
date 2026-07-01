import SwiftUI

struct WebFirewallRootView: View {
    @StateObject private var model = FirewallViewModel()
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Divider()
                webContent
            }

            if case .blocked = model.screen {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()

                BlockedContentView {
                    model.backToDMs()
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView {
                model.logout()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            if model.showsBackToDMs {
                Button {
                    model.backToDMs()
                } label: {
                    Label("Back to DMs", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
            }

            Text("Minimal Instagram")
                .font(.headline)

            Spacer()

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .imageScale(.medium)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background)
    }

    private var webContent: some View {
        ZStack {
            FirewallWebView(model: model, reloadToken: model.reloadToken)

            if model.isLoading {
                ProgressView()
                    .padding(18)
                    .background(.regularMaterial, in: Capsule())
            }

            if case .error(let message) = model.screen {
                errorView(message)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Couldn't load Instagram")
                .font(.headline)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Back to DMs") {
                model.backToDMs()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding()
    }
}

#Preview {
    WebFirewallRootView()
}
