import SidedoorCore
import SwiftUI

struct ChannelScreen: View {
    @ObservedObject var model: FirewallViewModel
    let logout: (ChannelID) -> Void
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            webContent
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showingSettings) {
            SettingsView(logout: logout)
        }
        // While blocked the screen offers exactly one action, Back to DMs; the
        // tab bar would be a second. No-op when there is no tab bar.
        .toolbarVisibility(model.screen.coversWebContent ? .hidden : .automatic, for: .tabBar)
        .sensoryFeedback(trigger: model.screen) { old, new in
            switch FirewallScreenState.feedbackCue(from: old, to: new) {
            case .blocked:
                .warning
            case .returnedToDMs:
                .impact(weight: .light)
            case nil:
                nil
            }
        }
    }

    /// One row. The page carries its own header, so the bar holds only what the
    /// page cannot: where Back to DMs goes, the unread filter, and settings.
    private var topBar: some View {
        HStack(spacing: 10) {
            if model.showsBackToDMs {
                Button {
                    model.backToDMs()
                } label: {
                    Label("Back to DMs", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityHint("Returns to the last direct message route")
            } else {
                Text(model.displayName)
                    .font(.headline)
            }

            if let caption = model.screen.caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            if model.offersUnreadFilter, case .web = model.screen {
                Button {
                    model.setUnreadFilter(!model.isUnreadFilterOn)
                } label: {
                    Label("Unread", systemImage: model.isUnreadFilterOn ? "envelope.badge.fill" : "envelope.badge")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
            .controlSize(.small)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(.background)
    }

    private var webContent: some View {
        ZStack {
            FirewallWebView(model: model)
                .id(model.reloadToken)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if case .error(let message) = model.screen {
                errorView(message)
            }

            if model.screen.coversWebContent {
                BlockedContentView(displayName: model.displayName) {
                    model.backToDMs()
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .top) {
            if model.isLoading {
                LoadProgressBar(progress: model.loadProgress)
                    .accessibilityLabel("Loading \(model.displayName)")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.screen)
        .animation(.easeInOut(duration: 0.2), value: model.isLoading)
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

/// Two points of tint along the top edge of the page. Never empty while shown:
/// the floor keeps a fresh navigation visible before WebKit reports progress.
private struct LoadProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.tint)
                .frame(width: proxy.size.width * max(progress, 0.06))
                .animation(.linear(duration: 0.2), value: progress)
        }
        .frame(height: 2)
        .accessibilityElement()
    }
}

#Preview {
    ChannelScreen(model: FirewallViewModel(channel: .instagram), logout: { _ in })
}
