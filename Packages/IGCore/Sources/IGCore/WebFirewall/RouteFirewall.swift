import Foundation

public enum RouteDecision: Equatable, Sendable {
    case allow
    case allowMedia(returnURL: URL)
    case block(returnURL: URL)
}

public struct RouteFirewall: Equatable, Sendable {
    public static var inboxURL: URL {
        guard let url = URL(string: "https://www.instagram.com/direct/inbox/") else {
            preconditionFailure("Static Instagram inbox URL is invalid")
        }
        return url
    }

    private var lastDMURL: URL?

    public init(lastDMURL: URL? = nil) {
        if let lastDMURL, Self.isDirectURL(lastDMURL) {
            self.lastDMURL = Self.routeURL(for: lastDMURL)
        }
    }

    public mutating func decision(for targetURL: URL, currentURL: URL?) -> RouteDecision {
        guard Self.isInstagramWebURL(targetURL) else {
            return .block(returnURL: backToDMsURL())
        }
        let targetRouteURL = Self.routeURL(for: targetURL)

        if Self.isAllowedAuthURL(targetRouteURL) {
            return .allow
        }

        if Self.isDirectURL(targetRouteURL) {
            lastDMURL = targetRouteURL
            return .allow
        }

        if Self.isMediaURL(targetRouteURL), let currentURL, Self.isDirectURL(currentURL) {
            let currentRouteURL = Self.routeURL(for: currentURL)
            lastDMURL = currentRouteURL
            return .allowMedia(returnURL: currentRouteURL)
        }

        return .block(returnURL: backToDMsURL())
    }

    public mutating func rememberIfDM(_ url: URL) {
        guard Self.isDirectURL(url) else { return }
        lastDMURL = Self.routeURL(for: url)
    }

    public func backToDMsURL() -> URL {
        lastDMURL ?? Self.inboxURL
    }

    public static func routeURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.user = nil
        components.password = nil
        components.port = nil
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    public static func isAllowedAuthURL(_ url: URL) -> Bool {
        guard isInstagramWebURL(url) else { return false }
        let normalizedURL = Self.routeURL(for: url)
        return path(normalizedURL, is: "/accounts/login")
            || path(normalizedURL, hasPrefix: "/accounts/login/")
            || path(normalizedURL, is: "/accounts/onetap")
            || path(normalizedURL, hasPrefix: "/accounts/onetap/")
            || path(normalizedURL, is: "/challenge")
            || path(normalizedURL, hasPrefix: "/challenge/")
    }

    public static func isDirectURL(_ url: URL) -> Bool {
        guard isInstagramWebURL(url) else { return false }
        let normalizedURL = Self.routeURL(for: url)
        return path(normalizedURL, is: "/direct") || path(normalizedURL, hasPrefix: "/direct/")
    }

    public static func isMediaURL(_ url: URL) -> Bool {
        guard isInstagramWebURL(url) else { return false }
        let normalizedURL = Self.routeURL(for: url)
        return path(normalizedURL, is: "/reel")
            || path(normalizedURL, hasPrefix: "/reel/")
            || path(normalizedURL, is: "/p")
            || path(normalizedURL, hasPrefix: "/p/")
            || path(normalizedURL, is: "/stories")
            || path(normalizedURL, hasPrefix: "/stories/")
    }

    private static func isInstagramWebURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              url.user == nil,
              url.password == nil else { return false }

        if let port = url.port, port != 443 {
            return false
        }

        return host == "instagram.com" || host == "www.instagram.com"
    }

    private static func path(_ url: URL, is expected: String) -> Bool {
        normalizedPath(url) == expected
    }

    private static func path(_ url: URL, hasPrefix prefix: String) -> Bool {
        normalizedPath(url).hasPrefix(prefix)
    }

    private static func normalizedPath(_ url: URL) -> String {
        let path = url.path
        return path.isEmpty ? "/" : path
    }
}
