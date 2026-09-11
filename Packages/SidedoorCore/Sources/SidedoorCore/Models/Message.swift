import Foundation

/// A text message in a thread. Allow-listed content type.
public struct Message: Equatable, Sendable, Identifiable {
    public let id: String
    public let senderID: String
    public let text: String
    public let sentAt: Date

    public init(id: String, senderID: String, text: String, sentAt: Date) {
        self.id = id
        self.senderID = senderID
        self.text = text
        self.sentAt = sentAt
    }
}
