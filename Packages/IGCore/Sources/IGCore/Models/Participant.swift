import Foundation

/// A person in a conversation. `displayName` falls back to `username` when IG has no full name.
public struct Participant: Equatable, Sendable, Identifiable {
    public let id: String
    public let username: String
    public let displayName: String

    public init(id: String, username: String, displayName: String) {
        self.id = id
        self.username = username
        self.displayName = displayName
    }
}
