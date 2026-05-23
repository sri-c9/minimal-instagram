import Foundation

/// The firewall. Pure (no I/O): maps raw IG DTOs to clean domain models, emitting
/// only allow-listed types. Anything not explicitly mapped is silently dropped.
public enum DomainMapper {

    static func mapThread(_ raw: RawThreadResponse) -> ThreadDetail {
        let thread = raw.thread
        return ThreadDetail(
            id: thread.threadID ?? "",
            title: title(for: thread.users),
            items: thread.items.compactMap(mapItem)
        )
    }

    static func mapInbox(_ raw: RawInboxResponse) -> [Conversation] {
        raw.inbox.threads.compactMap(mapConversation)
    }

    /// A thread with no id or no users isn't a renderable conversation -> dropped.
    static func mapConversation(_ raw: RawThread) -> Conversation? {
        guard let id = raw.threadID, !id.isEmpty, !raw.users.isEmpty else { return nil }
        let participants = raw.users.map {
            Participant(
                id: $0.pk.value,
                username: $0.username,
                displayName: displayName(for: $0)
            )
        }
        return Conversation(
            id: id,
            title: title(for: raw.users),
            participants: participants,
            isUnread: (raw.readState ?? 0) != 0,
            isPinned: raw.isPin ?? false,
            lastActivityAt: raw.lastActivityAt.map(date(fromMicroseconds:))
        )
    }

    /// Maps one raw item to an allow-listed ThreadItem, or nil to drop it.
    static func mapItem(_ raw: RawItem) -> ThreadItem? {
        guard let id = raw.itemID, let type = raw.itemType,
              let timestamp = raw.timestamp else { return nil }
        let sender = raw.userID?.value ?? ""
        let sentAt = date(fromMicroseconds: timestamp)

        // The firewall allow-list. Map ONLY allow-listed item types:
        //   - "text"        -> .message(Message(id:senderID:text:sentAt:)) when raw.text is non-empty
        //   - "clip"        -> reel(id:sender:sentAt:media: raw.clip?.clip)
        //   - "media_share" -> reel(id:sender:sentAt:media: raw.mediaShare)
        //   - default       -> nil   (ads, suggestions, unknown types are dropped)
        switch type {
        case "text":
            if let text = raw.text, !text.isEmpty {
                return .message(Message(id: id, senderID: sender, text: text, sentAt: sentAt))
            } else {
                return nil
            }
        case "clip":
            return reel(id: id, sender: sender, sentAt: sentAt, media: raw.clip?.clip)
        case "media_share":
            return reel(id: id, sender: sender, sentAt: sentAt, media: raw.directMediaShare?.media)
        default:
            return nil
        }
    }

    /// Video gate: emit a reel only when the media carries a playable video URL.
    static func reel(id: String, sender: String, sentAt: Date, media: RawMedia?) -> ThreadItem? {
        guard let media, let videoURL = media.bestVideoURL else { return nil }
        return .reel(SharedReel(
            id: id,
            senderID: sender,
            sentAt: sentAt,
            videoURL: videoURL,
            thumbnailURL: media.bestThumbnailURL
        ))
    }

    static func title(for users: [RawUser]) -> String {
        users.map(displayName(for:)).joined(separator: ", ")
    }

    /// The name shown for a user: their `fullName` when present and non-empty,
    /// otherwise their `username`. No force-unwrapping.
    static func displayName(for user: RawUser) -> String {
        if let fullname = user.fullName, !fullname.isEmpty {
            return fullname
        } else {
            return user.username
        }
    }

    static func date(fromMicroseconds micros: Int64) -> Date {
        Date(timeIntervalSince1970: Double(micros) / 1_000_000)
    }
}
