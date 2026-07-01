import Combine
import Foundation
import IGCore
import WebKit

@MainActor
final class FirewallViewModel: ObservableObject {
    @Published var screen: FirewallScreenState = .web
    @Published var isLoading = false
    @Published var currentURL: URL?
    @Published var reloadToken = UUID()

    private var routeFirewall = RouteFirewall()
    private var pendingLoadURL: URL?

    var homeURL: URL { RouteFirewall.inboxURL }

    var showsBackToDMs: Bool { screen.showsBackToDMs }

    func decision(for targetURL: URL) -> RouteDecision {
        let decision = routeFirewall.decision(for: targetURL, currentURL: currentURL)
        apply(decision, targetURL: targetURL)
        return decision
    }

    func observeCommittedURL(_ url: URL) {
        currentURL = url
        routeFirewall.rememberIfDM(url)

        if RouteFirewall.isDirectURL(url) || RouteFirewall.isAllowedAuthURL(url) {
            screen = .web
        }
    }

    func fail(_ error: Error) {
        isLoading = false
        screen = .error(error.localizedDescription)
    }

    func backToDMs() {
        let returnURL = screen.returnURL ?? routeFirewall.backToDMsURL()
        pendingLoadURL = returnURL
        screen = .web
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
                self.currentURL = nil
                self.routeFirewall = RouteFirewall()
                self.pendingLoadURL = nil
                self.screen = .web
                self.reloadToken = UUID()
            }
        }
    }

    private func apply(_ decision: RouteDecision, targetURL: URL) {
        switch decision {
        case .allow:
            if RouteFirewall.isDirectURL(targetURL) || RouteFirewall.isAllowedAuthURL(targetURL) {
                screen = .web
            }
        case .allowMedia(let returnURL):
            screen = .media(returnURL: returnURL)
        case .block(let returnURL):
            screen = .blocked(returnURL: returnURL)
        }
    }
}
