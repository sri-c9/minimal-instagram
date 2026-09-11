import Foundation

/// One social network's web surface, described statelessly. `ChannelID` owns the
/// mapping from identity to conformance; the protocol carries no `id` so tests can
/// build throwaway conformances.
public protocol Channel: Sendable {
    var displayName: String { get }

    /// Lowercase hostnames, matched exactly. Scheme, port, and credentials are
    /// checked by `RouteFirewall`, not here.
    var hosts: Set<String> { get }

    /// https, on a listed host, and classifies as `.dm`.
    var homeURL: URL { get }

    /// Receives the normalized path only: `"/"` for empty, no host, no query, no
    /// fragment. Never sees the host.
    func classify(path: String) -> RouteKind

    var webScript: ChannelWebScript { get }
}

extension Channel {
    /// Exact-or-prefix matching: `/direct` and `/direct/...`, never `/directory`.
    static func path(_ path: String, isOrUnder route: String) -> Bool {
        path == route || path.hasPrefix(route + "/")
    }

    /// Builds a compile-time-constant URL; a typo is a programmer error, not an optional.
    static func constantURL(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Static channel URL is invalid: \(string)")
        }
        return url
    }
}
