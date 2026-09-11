import Foundation
import Testing

/// Loads and decodes a JSON fixture from the test bundle's copied `Fixtures/` dir.
/// Fixtures are sanitized (real) or hand-authored (synthetic) — tests never hit IG.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(type, from: data(name))
    }
}
