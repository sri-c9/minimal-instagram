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

    /// True while the injected script reports Instagram's reels feed mounted inline
    /// in a `/direct/` thread. Tracked apart from `screen` so that clearing it can
    /// never take down a media mode that a real `/reel/` navigation put up.
    private var isInlineMediaSurfaceActive = false

    var homeURL: URL { RouteFirewall.inboxURL }

    var showsBackToDMs: Bool { screen.showsBackToDMs }

    func decision(for targetURL: URL) -> RouteDecision {
        let decision = routeFirewall.decision(for: targetURL, currentURL: currentDirectURL)
        apply(decision, targetURL: targetURL)
        return decision
    }

    func observeCommittedURL(_ url: URL) {
        // A committed navigation tears down whatever the script was watching, and
        // resetting here is also what lets a re-report recover if this raced ahead
        // of the script's first message on a fresh load.
        isInlineMediaSurfaceActive = false

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

    /// Instagram mounts its reels feed inline in `/direct/t/<thread>/` without
    /// navigating, so `RouteFirewall` never sees it and the shell would otherwise
    /// keep claiming to show DMs while a full-screen reel plays.
    func observeInlineMediaSurface(isPresent: Bool) {
        guard isInlineMediaSurfaceActive != isPresent else { return }

        if isPresent {
            // Only a DM thread can host this surface; anywhere else the route
            // firewall already owns the decision.
            guard let returnURL = currentDirectURL else { return }
            isInlineMediaSurfaceActive = true
            screen = .media(returnURL: returnURL)
            return
        }

        isInlineMediaSurfaceActive = false
        // `currentDirectURL` is nil once a real `/reel/` navigation takes over, which
        // is the case where this must keep its hands off `screen`.
        if case .media = screen, currentDirectURL != nil {
            screen = .web
        }
    }

    func fail(_ error: Error) {
        isLoading = false
        guard !error.isNavigationCancellation else { return }
        screen = .error(error.localizedDescription)
    }

    func backToDMs() {
        load(screen.returnURL ?? routeFirewall.backToDMsURL())
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
                self.currentDirectURL = nil
                self.routeFirewall = RouteFirewall()
                self.pendingLoadURL = nil
                self.isInlineMediaSurfaceActive = false
                self.screen = .web
                self.reloadToken = UUID()
            }
        }
    }

    private func load(_ url: URL) {
        pendingLoadURL = url
        isLoading = true
        isInlineMediaSurfaceActive = false
        screen = .web
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
