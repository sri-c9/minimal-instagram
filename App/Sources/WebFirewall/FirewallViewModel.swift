import Combine
import Foundation
import IGCore
import WebKit

/// Thin observable wrapper over `FirewallSurface`. Everything that decides *what*
/// the shell shows lives in `IGCore`; this holds only what needs a main actor and a
/// WebView — loading state, the pending load, and website data.
@MainActor
final class FirewallViewModel: ObservableObject {
    @Published private(set) var surface = FirewallSurface()
    @Published var isLoading = false
    @Published var reloadToken = UUID()

    private var pendingLoadURL: URL?

    var homeURL: URL { RouteFirewall.inboxURL }

    var screen: FirewallScreenState { surface.screen }

    var showsBackToDMs: Bool { surface.showsBackToDMs }

    func decision(for targetURL: URL) -> RouteDecision {
        let decision = surface.decide(for: targetURL)
        if case .block = decision {
            isLoading = false
        }
        return decision
    }

    func observeCommittedURL(_ url: URL) {
        surface.observeCommittedURL(url)
    }

    func observeInlineMediaSurface(isPresent: Bool) {
        surface.observeInlineMediaSurface(isPresent: isPresent)
    }

    func fail(_ error: Error) {
        isLoading = false
        guard !error.isNavigationCancellation else { return }
        surface.fail(error.localizedDescription)
    }

    func backToDMs() {
        load(surface.backToDMsURL())
    }

    func reloadInstagram() {
        load(homeURL)
    }

    func consumePendingLoadURL() -> URL? {
        let url = pendingLoadURL
        pendingLoadURL = nil
        return url
    }

    func logout() {
        isLoading = true
        let dataStore = WKWebsiteDataStore.default()
        dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                             modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                self.pendingLoadURL = nil
                self.surface.reset()
                self.reloadToken = UUID()
            }
        }
    }

    private func load(_ url: URL) {
        pendingLoadURL = url
        isLoading = true
        surface.prepareLoad()
    }
}

private extension Error {
    var isNavigationCancellation: Bool {
        let error = self as NSError
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
            return true
        }

        // WebKit also reports policy-cancelled loads as WebKitErrorDomain code 102.
        return error.domain == WKErrorDomain && error.code == 102
    }
}
