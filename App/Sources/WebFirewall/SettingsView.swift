import Foundation
import SwiftUI

struct SettingsView: View {
    let logout: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingLogout = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Button(role: .destructive) {
                        confirmingLogout = true
                    } label: {
                        Label("Log Out of Instagram in This App", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityHint("Clears Instagram website data stored by this app")
                }

                Section("Privacy") {
                    Text(
                        "Instagram handles login and DMs inside its web page. "
                            + "Minimal Instagram blocks routes locally and does not read messages, "
                            + "extract cookies, or store Instagram content."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("About") {
                    Text("Minimal Instagram loads Instagram web DMs and blocks distracting routes locally.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    LabeledContent("Version", value: versionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Log out of Instagram in this app?",
                                isPresented: $confirmingLogout,
                                titleVisibility: .visible) {
                Button("Log Out", role: .destructive) {
                    dismiss()
                    logout()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears this app's Instagram WebKit cookies and website data, then returns to login.")
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
