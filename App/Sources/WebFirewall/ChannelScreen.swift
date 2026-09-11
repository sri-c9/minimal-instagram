import SidedoorCore
import SwiftUI

struct ChannelScreen: View {
    @ObservedObject var model: FirewallViewModel
    let logout: (ChannelID) -> Void
    @State private var showingSettings = false

    private var isBlocked: Bool {
        if case .blocked = model.screen { true } else { false }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Divider()
                webContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if case .blocked = model.screen {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()

                BlockedContentView(displayName: model.displayName) {
                    model.backToDMs()
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(logout: logout)
        }
        // While blocked the screen offers exactly one action, Back to DMs; the
        // tab bar would be a second. No-op when there is no tab bar.
        .toolbarVisibility(isBlocked ? .hidden : .automatic, for: .tabBar)
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
                .accessibilityHint("Returns to the last direct message route")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.headline)

                Text(model.screen.statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Current mode: \(model.screen.statusTitle)")
            }

            Spacer()

            if model.offersUnreadFilter, case .web = model.screen {
                Button {
                    model.setUnreadFilter(!model.isUnreadFilterOn)
                } label: {
                    Label("Unread", systemImage: model.isUnreadFilterOn ? "envelope.badge.fill" : "envelope.badge")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .tint(model.isUnreadFilterOn ? Color.accentColor : Color.secondary)
                .accessibilityLabel("Show unread only")
                .accessibilityValue(model.isUnreadFilterOn ? "On" : "Off")
                .accessibilityAddTraits(.isToggle)
            }

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
            FirewallWebView(model: model)
                .id(model.reloadToken)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.isLoading {
                ProgressView()
                    .accessibilityLabel("Loading \(model.displayName)")
                    .padding(18)
                    .background(.regularMaterial, in: Capsule())
            }

            if case .error(let message) = model.screen {
                errorView(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .top) {
            if case .media = model.screen {
                MediaModeBanner {
                    model.backToDMs()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.screen)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Couldn't load \(model.displayName)")
                .font(.headline)

            VStack(spacing: 6) {
                Text("Check your connection, then reload \(model.displayName) DMs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button("Back to DMs") {
                    model.backToDMs()
                }
                .buttonStyle(.bordered)

                Button("Reload") {
                    model.reloadHome()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding()
    }
}

private struct MediaModeBanner: View {
    let backToDMs: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Viewing media shared from DMs")
                .font(.footnote.weight(.semibold))
                .lineLimit(2)

            Spacer(minLength: 8)

            Button("Back") {
                backToDMs()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("Back to DMs")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ChannelScreen(model: FirewallViewModel(channel: .instagram), logout: { _ in })
}
