import Foundation

/// The web firewall's screen state machine, kept UI-free so its transitions can be
/// exercised without a WebView.
///
/// Two independent inputs drive it:
///
/// - **Navigations** go through `RouteFirewall`, which decides purely from the URL.
/// - **The inline reels feed** has no URL of its own. Instagram mounts that
///   component inside `/direct/t/<thread>/` without navigating, so `RouteFirewall`
///   is never given a decision to make and the injected script has to report the
///   surface separately via `observeInlineMediaSurface(isPresent:)`.
///
/// The two must not fight each other, which is the whole reason this is one type
/// rather than flags scattered across a view model: a report that the inline feed
/// went away must never take down a media mode that a real `/reel/` navigation put
/// up.
public struct FirewallSurface: Equatable, Sendable {
    public private(set) var screen: FirewallScreenState = .web

    private var routeFirewall = RouteFirewall()

    /// The DM thread the WebView is sitting on, or `nil` when it is anywhere else.
    /// Doubles as the marker for "the inline surface is the only thing that could
    /// have raised media mode here".
    private var currentDirectURL: URL?

    /// Whether the injected script currently reports the inline reels feed mounted.
    /// Tracked apart from `screen` so a stale or duplicated report is a no-op.
    private var isInlineMediaActive = false

    public init() {}

    public var showsBackToDMs: Bool { screen.showsBackToDMs }

    /// Where the `Back to DMs` control should send the user.
    public func backToDMsURL() -> URL {
        screen.returnURL ?? routeFirewall.backToDMsURL()
    }

    /// Applies the route policy to a navigation and folds the result into `screen`.
    @discardableResult
    public mutating func decide(for targetURL: URL) -> RouteDecision {
        let decision = routeFirewall.decision(for: targetURL, currentURL: currentDirectURL)

        switch decision {
        case .allow:
            if RouteFirewall.isDirectURL(targetURL) || RouteFirewall.isAllowedAuthURL(targetURL) {
                screen = .web
            }
        case .allowMedia(let returnURL):
            // A real media route owns the screen from here; the inline surface, if
            // one was up, is about to be navigated away from.
            currentDirectURL = nil
            isInlineMediaActive = false
            screen = .media(returnURL: returnURL)
        case .block(let returnURL):
            screen = .blocked(returnURL: returnURL)
        }

        return decision
    }

    public mutating func observeCommittedURL(_ url: URL) {
        // A committed navigation tears down whatever the script was watching. This
        // reset is also what lets a later report recover the state if a commit
        // raced ahead of the script's first message on a fresh load.
        isInlineMediaActive = false

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

    /// Reports whether Instagram's reels feed is mounted inline in the current DM
    /// thread. Idempotent: repeated reports of the same value do nothing.
    public mutating func observeInlineMediaSurface(isPresent: Bool) {
        guard isInlineMediaActive != isPresent else { return }

        if isPresent {
            // Only a DM thread hosts this surface. Anywhere else the route firewall
            // already owns the decision and this must not second-guess it.
            guard let returnURL = currentDirectURL else { return }
            isInlineMediaActive = true
            screen = .media(returnURL: returnURL)
            return
        }

        isInlineMediaActive = false
        // `currentDirectURL` is nil once a real `/reel/` navigation has taken over,
        // which is exactly the media mode this must keep its hands off.
        if case .media = screen, currentDirectURL != nil {
            screen = .web
        }
    }

    public mutating func fail(_ message: String) {
        isInlineMediaActive = false
        screen = .error(message)
    }

    /// Called when the shell is about to load a URL of its own choosing.
    public mutating func prepareLoad() {
        isInlineMediaActive = false
        screen = .web
    }

    /// Drops every trace of the signed-in session's browsing state.
    public mutating func reset() {
        self = FirewallSurface()
    }
}
