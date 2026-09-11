import Foundation
import SidedoorCore
import SwiftUI

struct SettingsView: View {
    let logout: (ChannelID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var channelToLogOut: ChannelID?

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    ForEach(ChannelID.allCases, id: \.self) { channel in
                        Button(role: .destructive) {
                            channelToLogOut = channel
                        } label: {
                            Label("Log Out of \(channel.channel.displayName)",
                                  systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .accessibilityHint("Clears \(channel.channel.displayName) website data stored by this app")
                    }
                }

                Section("Privacy") {
                    Text(
                        "Each network handles login and DMs inside its own web page. "
                            + "Sidedoor blocks routes locally and does not read messages, "
                            + "extract cookies, or store content."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("About") {
                    Text("Sidedoor loads a network's web DMs and blocks distracting routes locally.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    LabeledContent("Version", value: versionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Log out of \(channelToLogOut?.channel.displayName ?? "") in this app?",
                isPresented: Binding(
                    get: { channelToLogOut != nil },
                    set: { if !$0 { channelToLogOut = nil } }
                ),
                titleVisibility: .visible,
                presenting: channelToLogOut
            ) { channel in
                Button("Log Out", role: .destructive) {
                    dismiss()
                    logout(channel)
                }

                Button("Cancel", role: .cancel) {}
            } message: { channel in
                Text("This clears this app's \(channel.channel.displayName) cookies and website data, "
                     + "then returns that channel to login. Other channels are untouched.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}
