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
}
