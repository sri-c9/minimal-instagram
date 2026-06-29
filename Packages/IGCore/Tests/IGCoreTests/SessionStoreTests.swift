import Foundation
import Testing
@testable import IGCore

@Suite struct SessionStoreTests {
    private func device() -> DeviceIdentity {
        DeviceIdentity(deviceID: "dev-1", familyDeviceID: "fam-1", mid: "MID123",
                       bloksVersionID: "bloks-1", appVersion: "309.0.0.40.113",
                       capabilities: "3brTv10=", userAgent: "UA/1.0")
    }

    private func sample() -> Session {
        Session(sessionid: "fake_session_id", dsUserID: "12345", claim: "0",
                device: device(), csrfToken: "c")
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

    @Test func roundTripsDeviceIdentity() async throws {
        let store = SessionStore(store: InMemorySecureStore())
        try await store.save(sample())
        let loaded = try #require(await store.current())
        #expect(loaded.device == sample().device)
        #expect(loaded.sessionid == "fake_session_id")
    }

    @Test func updateMIDMutatesDeviceMID() async throws {
        let store = SessionStore(store: InMemorySecureStore())
        try await store.save(sample())
        await store.updateMID("MID_NEW")
        #expect(await store.current()?.device.mid == "MID_NEW")
    }
}
