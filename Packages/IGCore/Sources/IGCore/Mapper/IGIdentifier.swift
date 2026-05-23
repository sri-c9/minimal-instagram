import Foundation

/// Instagram returns ids inconsistently as JSON numbers (`pk`, `user_id`) or strings
/// (`pk_id`, `thread_id`). Decode either, expose a canonical string.
struct IGIdentifier: Decodable, Equatable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else {
            value = String(try container.decode(Int64.self))
        }
    }
}
