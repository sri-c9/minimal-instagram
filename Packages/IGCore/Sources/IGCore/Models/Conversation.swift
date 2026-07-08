import Foundation

/// An inbox row. `isUnread`/`isPinned` drive the calm inbox's Unread/Pinned/Recent sections.
public struct Conversation: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let participants: [Participant]
    public let isUnread: Bool
    public let isPinned: Bool
    public let lastActivityAt: Date?

    public init(
        id: String,
        title: String,
        participants: [Participant],
        isUnread: Bool,
        isPinned: Bool,
        lastActivityAt: Date?
    ) {
        self.id = id
        self.title = title
        self.participants = participants
        self.isUnread = isUnread
        self.isPinned = isPinned
        self.lastActivityAt = lastActivityAt
    }
}
