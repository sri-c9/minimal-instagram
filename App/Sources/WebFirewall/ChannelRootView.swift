import SidedoorCore
import SwiftUI

/// Owns the active channel and the store. With one channel it shows that
/// channel's screen alone; with more it is a system tab bar, one tab per channel,
/// every tab kept alive so a switch shows the other page where it was.
struct ChannelRootView: View {
    @StateObject private var store = ChannelStore()
    @AppStorage("activeChannel") private var activeChannelRawValue = ChannelID.instagram.rawValue

    private var activeChannel: ChannelID {
        ChannelID(rawValue: activeChannelRawValue) ?? .instagram
    }

    private var selection: Binding<ChannelID> {
        Binding(
            get: { activeChannel },
            set: { activeChannelRawValue = $0.rawValue }
        )
    }

    var body: some View {
        if ChannelID.allCases.count == 1 {
            ChannelScreen(model: store.model(for: activeChannel), logout: logout)
        } else {
            TabView(selection: selection) {
                ForEach(ChannelID.allCases, id: \.self) { channel in
                    ChannelScreen(model: store.model(for: channel), logout: logout)
                        .tabItem {
                            Label(channel.channel.displayName, systemImage: Self.symbolName(for: channel))
                        }
                        .tag(channel)
                }
            }
            .onChange(of: activeChannel) { previous, _ in
                // Audio from the outgoing channel must not keep playing under the
                // other tab. Nothing else happens on a switch (§6.7).
                store.model(for: previous).pauseMedia()
            }
        }
    }

    private func logout(_ channel: ChannelID) {
        store.model(for: channel).logout()
    }

    /// Exhaustive on purpose: a new channel does not compile until it has an icon.
    private static func symbolName(for channel: ChannelID) -> String {
        switch channel {
        case .instagram:
            "camera"
        }
    }
}

#Preview {
    ChannelRootView()
}
