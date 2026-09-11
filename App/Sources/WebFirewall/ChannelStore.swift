import Combine
import SidedoorCore

/// One `FirewallViewModel` per channel, created lazily and kept for the life of
/// the process so a channel's page is exactly where the user left it. The cache
/// is a plain dictionary on purpose: `model(for:)` is called from `body`, and
/// publishing from there is a SwiftUI runtime warning.
@MainActor
final class ChannelStore: ObservableObject {
    private var models: [ChannelID: FirewallViewModel] = [:]

    func model(for channel: ChannelID) -> FirewallViewModel {
        if let model = models[channel] {
            return model
        }
        let model = FirewallViewModel(channel: channel)
        models[channel] = model
        return model
    }
}
