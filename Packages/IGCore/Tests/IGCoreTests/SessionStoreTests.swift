import Foundation
import Testing
@testable import IGCore

@Suite struct SessionStoreTests {
    private func sample() -> Session {
        Session(cookieHeader: "sessionid=x; csrftoken=c; ds_user_id=9",
                csrfToken: "c", dsUserID: "9", claim: "0", userAgent: "UA/1.0")
    }

    @Test func savesAndLoadsSession() async throws {
        let store = SessionStore(store: InMemorySecureStore())
        #expect(await store.current() == nil)
        try await store.save(sample())
        #expect(await store.current() == sample())
    }

    @Test func updateClaimMutatesStoredSession() async throws {
        let store = SessionStore(store: InMemorySecureStore())
        try await store.save(sample())
        await store.updateClaim("hmac.NEW")
        #expect(await store.current()?.claim == "hmac.NEW")
    }

    @Test func clearRemovesSession() async throws {
        let store = SessionStore(store: InMemorySecureStore())
        try await store.save(sample())
        try await store.clear()
        #expect(await store.current() == nil)
    }
}
