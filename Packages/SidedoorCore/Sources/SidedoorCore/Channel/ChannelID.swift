import Foundation

/// The channel registry. Every case resolves to exactly one stateless conformance,
/// and the state machines hold this value rather than the existential so they keep
/// their synthesized `Equatable`.
public enum ChannelID: String, CaseIterable, Sendable {
    case instagram

    public var channel: any Channel {
        switch self {
        case .instagram:
            InstagramChannel()
        }
    }

    /// Fixed, committed identifier for this channel's `WKWebsiteDataStore`. Not
    /// derived from anything user-specific. Each channel's cookie jar lives under
    /// its own identifier and nothing is ever shared between them.
    public var webStoreIdentifier: UUID {
        switch self {
        case .instagram:
            Self.constantUUID("D36DECBA-C5F3-4C94-8647-11D599829E5B")
        }
    }

    private static func constantUUID(_ string: String) -> UUID {
        guard let uuid = UUID(uuidString: string) else {
            preconditionFailure("Static data store identifier is invalid: \(string)")
        }
        return uuid
    }
}
