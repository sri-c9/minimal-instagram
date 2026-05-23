import Foundation
import Testing
@testable import IGCore

// Serialized: MockURLProtocol uses shared static state (URLSession owns protocol
// instantiation), which isn't safe under Swift Testing's default parallelism.
@Suite(.serialized) struct IGWebClientTests {
    struct FakeSession: SessionProviding {
        let session: Session?
        let onClaim: @Sendable (String) -> Void
        init(_ session: Session?, onClaim: @escaping @Sendable (String) -> Void = { _ in }) {
            self.session = session
            self.onClaim = onClaim
        }
        func current() async -> Session? { session }
        func updateClaim(_ claim: String) async { onClaim(claim) }
    }

    private func session() -> Session {
        Session(cookieHeader: "sessionid=x; csrftoken=c; ds_user_id=9",
                csrfToken: "c", dsUserID: "9", claim: "0", userAgent: "UA/Test")
    }

    @Test func inboxBuildsAuthedRequestAndDecodes() async throws {
        let body = try Fixture.data("inbox_real")
        MockURLProtocol.responder = { _ in (200, [:], body) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())

        let raw = try await client.inbox(limit: 20)

        #expect(!raw.inbox.threads.isEmpty)
        let req = try #require(MockURLProtocol.lastRequest)
        // Trailing slash is on the wire (IG requires it); URL.path strips it for display.
        #expect(req.url?.absoluteString.contains("/api/v1/direct_v2/inbox/") == true)
        #expect(req.url?.query?.contains("limit=20") == true)
        #expect(req.value(forHTTPHeaderField: "X-IG-App-ID") == "936619743392459")
        #expect(req.value(forHTTPHeaderField: "X-CSRFToken") == "c")
        #expect(req.value(forHTTPHeaderField: "X-IG-WWW-Claim") == "0")
        #expect(req.value(forHTTPHeaderField: "User-Agent") == "UA/Test")
        #expect(req.value(forHTTPHeaderField: "Cookie")?.contains("sessionid=x") == true)
    }

    @Test func threadBuildsRequestWithIDAndDecodes() async throws {
        let body = try Fixture.data("thread_real")
        MockURLProtocol.responder = { _ in (200, [:], body) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())

        let raw = try await client.thread(id: "rt_real_1", limit: 40)

        #expect(!raw.thread.items.isEmpty)
        let req = try #require(MockURLProtocol.lastRequest)
        #expect(req.url?.absoluteString.contains("/api/v1/direct_v2/threads/rt_real_1/") == true)
        #expect(req.url?.query?.contains("limit=40") == true)
    }

    @Test func refreshesClaimFromResponseHeader() async throws {
        let body = try Fixture.data("inbox_real")
        MockURLProtocol.responder = { _ in (200, ["x-ig-set-www-claim": "hmac.NEW"], body) }
        let captured = ClaimBox()
        let client = IGWebClient(session: FakeSession(session()) { captured.value = $0 },
                                 urlSession: MockURLProtocol.session())
        _ = try await client.inbox()
        #expect(captured.value == "hmac.NEW")
    }

    // MARK: - Error mapping (session-death firewall)

    @Test func loginRequiredBodyMapsToNeedsLogin() async throws {
        MockURLProtocol.responder = { _ in (200, [:], Data(#"{"message":"login_required","status":"fail"}"#.utf8)) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())
        await #expect(throws: IGClientError.needsLogin) { _ = try await client.inbox() }
    }

    @Test func forbiddenMapsToNeedsLogin() async throws {
        MockURLProtocol.responder = { _ in (403, [:], Data()) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())
        await #expect(throws: IGClientError.needsLogin) { _ = try await client.inbox() }
    }

    @Test func serverErrorMapsToHTTP() async throws {
        MockURLProtocol.responder = { _ in (500, [:], Data()) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())
        await #expect(throws: IGClientError.http(500)) { _ = try await client.inbox() }
    }

    @Test func missingSessionMapsToNeedsLogin() async throws {
        let client = IGWebClient(session: FakeSession(nil), urlSession: MockURLProtocol.session())
        await #expect(throws: IGClientError.needsLogin) { _ = try await client.inbox() }
    }
}

/// Mutable box so a Sendable closure can capture the refreshed claim across the await.
final class ClaimBox: @unchecked Sendable {
    var value: String?
}
