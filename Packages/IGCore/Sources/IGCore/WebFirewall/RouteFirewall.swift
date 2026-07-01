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

    public private(set) var lastDMURL: URL?

    public init(lastDMURL: URL? = nil) {
        self.lastDMURL = lastDMURL
    }

    public mutating func decision(for targetURL: URL, currentURL: URL?) -> RouteDecision {
        guard Self.isInstagramWebURL(targetURL) else {
            return .block(returnURL: backToDMsURL())
        }

        if Self.isAllowedAuthURL(targetURL) {
            return .allow
        }

        if Self.isDirectURL(targetURL) {
            lastDMURL = targetURL
            return .allow
        }

        if Self.isMediaURL(targetURL), let currentURL, Self.isDirectURL(currentURL) {
            lastDMURL = currentURL
            return .allowMedia(returnURL: currentURL)
        }

        return .block(returnURL: backToDMsURL())
    }

    public mutating func rememberIfDM(_ url: URL) {
        guard Self.isInstagramWebURL(url), Self.isDirectURL(url) else { return }
        lastDMURL = url
    }

    public func backToDMsURL() -> URL {
        lastDMURL ?? Self.inboxURL
    }

    public static func isAllowedAuthURL(_ url: URL) -> Bool {
        guard isInstagramWebURL(url) else { return false }
        return path(url, is: "/accounts/login")
            || path(url, hasPrefix: "/accounts/login/")
            || path(url, is: "/accounts/onetap")
            || path(url, hasPrefix: "/accounts/onetap/")
            || path(url, is: "/challenge")
            || path(url, hasPrefix: "/challenge/")
    }

    public static func isDirectURL(_ url: URL) -> Bool {
        guard isInstagramWebURL(url) else { return false }
        return path(url, is: "/direct") || path(url, hasPrefix: "/direct/")
    }

    public static func isMediaURL(_ url: URL) -> Bool {
        guard isInstagramWebURL(url) else { return false }
        return path(url, is: "/reel")
            || path(url, hasPrefix: "/reel/")
            || path(url, is: "/p")
            || path(url, hasPrefix: "/p/")
            || path(url, is: "/stories")
            || path(url, hasPrefix: "/stories/")
    }

    private static func isInstagramWebURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
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
