import Foundation

struct RawInboxResponse: Decodable {
    let inbox: RawInbox
}

struct RawInbox: Decodable {
    let threads: [RawThread]

    enum CodingKeys: String, CodingKey { case threads }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threads = container.decodeLossyArray(RawThread.self, forKey: .threads)
    }
}

struct RawThread: Decodable {
    let threadID: String?
    let users: [RawUser]
    let readState: Int?
    let isPin: Bool?
    let lastActivityAt: Int64?

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case users
        case readState = "read_state"
        case isPin = "is_pin"
        case lastActivityAt = "last_activity_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        users = container.decodeLossyArray(RawUser.self, forKey: .users)
        readState = try container.decodeIfPresent(Int.self, forKey: .readState)
        isPin = try container.decodeIfPresent(Bool.self, forKey: .isPin)
        lastActivityAt = try container.decodeIfPresent(Int64.self, forKey: .lastActivityAt)
    }
}

struct RawUser: Decodable {
    let pk: IGIdentifier
    let username: String
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case pk
        case username
        case fullName = "full_name"
    }
}
