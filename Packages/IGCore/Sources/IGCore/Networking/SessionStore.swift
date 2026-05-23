import Foundation

/// Read seam IGWebClient depends on (so its tests can fake the session).
public protocol SessionProviding: Sendable {
    func current() async -> Session?
    func updateClaim(_ claim: String) async
}

/// Persists the session via a SecureStore; serves a cached copy; refreshes the claim.
public actor SessionStore: SessionProviding {
    private let store: SecureStore
    private let key = "ig.session"
    private var cached: Session?

    public init(store: SecureStore = KeychainStore()) { self.store = store }

    public func current() -> Session? {
        if let cached { return cached }
        guard let data = try? store.read(key),
              let session = try? JSONDecoder().decode(Session.self, from: data) else { return nil }
        cached = session
        return session
    }

    public func save(_ session: Session) throws {
        cached = session
        try store.write(JSONEncoder().encode(session), key: key)
    }

    public func updateClaim(_ claim: String) {
        guard var session = current(), session.claim != claim else { return }
        session.claim = claim
        try? save(session)
    }

    public func clear() throws {
        cached = nil
        try store.delete(key)
    }
}
