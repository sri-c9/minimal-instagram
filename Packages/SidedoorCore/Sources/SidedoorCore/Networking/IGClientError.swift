import Foundation

/// Errors surfaced by IGWebClient. `.needsLogin` is the calm session-death signal
/// the Repository will route to re-auth (§7); it never crashes or retry-storms.
public enum IGClientError: Error, Equatable {
    case needsLogin
    case http(Int)
    case transport
    case decoding
}
