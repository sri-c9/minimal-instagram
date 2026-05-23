import Foundation

struct RawThreadResponse: Decodable {
    let thread: RawThreadDetail
}

struct RawThreadDetail: Decodable {
    let threadID: String?
    let users: [RawUser]
    let items: [RawItem]

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case users
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        users = container.decodeLossyArray(RawUser.self, forKey: .users)
        items = container.decodeLossyArray(RawItem.self, forKey: .items)
    }
}

/// A thread item. All type-specific fields are optional so unknown/junk items still
/// decode (then get dropped by the mapper). `itemType` is the allow-list discriminator.
struct RawItem: Decodable {
    let itemID: String?
    let userID: IGIdentifier?
    let timestamp: Int64?
    let itemType: String?
    let text: String?
    let clip: RawClipWrapper?
    let mediaShare: RawMedia?

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case userID = "user_id"
        case timestamp
        case itemType = "item_type"
        case text
        case clip
        case mediaShare = "media_share"
    }
}

/// Clips nest one level deeper than media_share: item.clip.clip.video_versions
struct RawClipWrapper: Decodable {
    let clip: RawMedia?
}

struct RawMedia: Decodable {
    let videoVersions: [RawVideoVersion]?
    let imageVersions2: RawImageVersions?

    enum CodingKeys: String, CodingKey {
        case videoVersions = "video_versions"
        case imageVersions2 = "image_versions2"
    }

    /// First playable video URL, if any. The video gate for SharedReel.
    var bestVideoURL: URL? {
        guard let raw = videoVersions?.first?.url else { return nil }
        return URL(string: raw)
    }

    var bestThumbnailURL: URL? {
        guard let raw = imageVersions2?.candidates.first?.url else { return nil }
        return URL(string: raw)
    }
}

struct RawVideoVersion: Decodable {
    let url: String
}

struct RawImageVersions: Decodable {
    let candidates: [RawImageCandidate]
}

struct RawImageCandidate: Decodable {
    let url: String
}
