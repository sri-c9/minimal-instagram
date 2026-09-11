import Foundation

/// A reel shared into a DM. Allow-listed content type. Video-gated: only constructed
/// when a playable video URL exists (a shared post with no video is never a SharedReel).
public struct SharedReel: Equatable, Sendable, Identifiable {
    public let id: String
    public let senderID: String
    public let sentAt: Date
    public let videoURL: URL
    public let thumbnailURL: URL?

    public init(id: String, senderID: String, sentAt: Date, videoURL: URL, thumbnailURL: URL?) {
        self.id = id
        self.senderID = senderID
        self.sentAt = sentAt
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
    }
}
