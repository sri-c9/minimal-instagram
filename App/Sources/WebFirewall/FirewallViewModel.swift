import Combine
import Foundation
import IGCore
import WebKit

@MainActor
final class FirewallViewModel: ObservableObject {
    @Published var screen: FirewallScreenState = .web
    @Published var isLoading = false
    @Published var reloadToken = UUID()

    private var currentDirectURL: URL?
    private var routeFirewall = RouteFirewall()
    private var pendingLoadURL: URL?

    var homeURL: URL { RouteFirewall.inboxURL }

    var showsBackToDMs: Bool { screen.showsBackToDMs }

    func decision(for targetURL: URL) -> RouteDecision {
        let decision = routeFirewall.decision(for: targetURL, currentURL: currentDirectURL)
        apply(decision, targetURL: targetURL)
        return decision
    }

    func observeCommittedURL(_ url: URL) {
        if RouteFirewall.isDirectURL(url) {
            let routeURL = RouteFirewall.routeURL(for: url)
            currentDirectURL = routeURL
            routeFirewall.rememberIfDM(routeURL)
            screen = .web
            return
        }

        currentDirectURL = nil
        if RouteFirewall.isAllowedAuthURL(url) {
            screen = .web
        }
    }

    func fail(_ error: Error) {
        isLoading = false
        guard !error.isNavigationCancellation else { return }
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
                self.currentDirectURL = nil
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
            currentDirectURL = nil
            screen = .media(returnURL: returnURL)
        case .block(let returnURL):
            isLoading = false
            screen = .blocked(returnURL: returnURL)
        }
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
