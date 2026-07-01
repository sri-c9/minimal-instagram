import SwiftUI

struct SettingsView: View {
    let logout: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Button(role: .destructive) {
                        dismiss()
                        logout()
                    } label: {
                        Label("Log Out of Instagram in This App", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("About") {
                    Text("Minimal Instagram loads Instagram web DMs and blocks distracting routes locally.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
