import Foundation

/// Wraps a `Decodable` so one bad element (wrong JSON type, etc.) yields `nil`
/// rather than throwing and discarding the entire array. This is how "malformed
/// items are ignored" survives at the decode boundary, before the mapper runs.
struct FailableElement<Wrapped: Decodable>: Decodable {
    let wrapped: Wrapped?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrapped = try? container.decode(Wrapped.self)
    }
}

extension KeyedDecodingContainer {
    /// Decode an array, silently dropping elements that fail to decode. Missing key -> [].
    func decodeLossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        guard let raw = try? decode([FailableElement<T>].self, forKey: key) else { return [] }
        return raw.compactMap(\.wrapped)
    }
}
