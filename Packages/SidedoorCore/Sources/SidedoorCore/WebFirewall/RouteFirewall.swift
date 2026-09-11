import Foundation

public enum RouteDecision: Equatable, Sendable {
    case allow
    case allowMedia(returnURL: URL)
    case block(returnURL: URL)
}

/// The stateful route rule, shared by every channel: remember the last DM route,
/// allow media only from a DM, block a second media navigation, block by default.
/// The channel supplies only hosts, home, and the path classifier.
public struct RouteFirewall: Equatable, Sendable {
    public let channelID: ChannelID

    private var lastDMURL: URL?

    public init(channel: ChannelID, lastDMURL: URL? = nil) {
        self.channelID = channel
        if let lastDMURL, kind(of: lastDMURL) == .dm {
            self.lastDMURL = Self.routeURL(for: lastDMURL)
        }
    }

    public var homeURL: URL { channelID.channel.homeURL }

    public mutating func decision(for targetURL: URL, currentURL: URL?) -> RouteDecision {
        guard let targetKind = kind(of: targetURL) else {
            return .block(returnURL: backToDMsURL())
        }

        switch targetKind {
        case .auth:
            return .allow
        case .dm:
            lastDMURL = Self.routeURL(for: targetURL)
            return .allow
        case .media:
            if let currentURL, kind(of: currentURL) == .dm {
                let currentRouteURL = Self.routeURL(for: currentURL)
                lastDMURL = currentRouteURL
                return .allowMedia(returnURL: currentRouteURL)
            }
            return .block(returnURL: backToDMsURL())
        case .other:
            return .block(returnURL: backToDMsURL())
        }
    }

    public mutating func rememberIfDM(_ url: URL) {
        guard kind(of: url) == .dm else { return }
        lastDMURL = Self.routeURL(for: url)
    }

    public func backToDMsURL() -> URL {
        lastDMURL ?? homeURL
    }

    /// `nil` when the URL is not this channel's web surface: scheme not https, host
    /// not listed, credentials present, or a non-443 port.
    public func kind(of url: URL) -> RouteKind? {
        let channel = channelID.channel
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              channel.hosts.contains(host),
              url.user == nil,
              url.password == nil else { return nil }

        if let port = url.port, port != 443 {
            return nil
        }

        return channel.classify(path: Self.normalizedPath(url))
    }

    /// Strips credentials, port, query, and fragment and lowercases scheme and host.
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

    private static func normalizedPath(_ url: URL) -> String {
        let path = url.path
        return path.isEmpty ? "/" : path
    }
}
