import Foundation
import Security

/// Minimal secure key/value byte store. Seam so SessionStore logic is testable
/// without the real Keychain (which needs entitlements / a host app).
public protocol SecureStore: Sendable {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func delete(_ key: String) throws
}

/// In-memory store for tests/dev. Not persistent, not secure.
public final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    public init() {}
    public func read(_ key: String) throws -> Data? { lock.withLock { items[key] } }
    public func write(_ data: Data, key: String) throws { lock.withLock { items[key] = data } }
    public func delete(_ key: String) throws { _ = lock.withLock { items.removeValue(forKey: key) } }
}

/// Keychain-backed store (kSecClassGenericPassword). Smoke-tested on device, not in CI
/// (the macOS host test process may lack keychain entitlements).
public struct KeychainStore: SecureStore {
    private let service: String
    public init(service: String = "com.sri.minimalinstagram.session") { self.service = service }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    public func read(_ key: String) throws -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw IGClientError.transport }
        return out as? Data
    }

    public func write(_ data: Data, key: String) throws {
        let status = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(key)
            add[kSecValueData as String] = data
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw IGClientError.transport }
        } else {
            guard status == errSecSuccess else { throw IGClientError.transport }
        }
    }

    public func delete(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw IGClientError.transport }
    }
}
