import Foundation
import WebKit

/// Before channels had their own stores, the app used `WKWebsiteDataStore.default()`.
/// A session left there by an older build could never be cleared by a per-channel
/// logout, so it is wiped once. Harmless on a fresh install.
enum LegacyDataStoreCleanup {
    private static let completedKey = "didClearDefaultWebsiteDataStore"

    @MainActor
    static func runIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: completedKey) else { return }
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                modifiedSince: .distantPast) {
            UserDefaults.standard.set(true, forKey: completedKey)
        }
    }
}
