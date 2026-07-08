import Foundation
import Testing
@testable import IGCore

// Serialized: MockURLProtocol uses shared static state (URLSession owns protocol
// instantiation), which isn't safe under Swift Testing's default parallelism.
@Suite(.serialized) struct IGWebClientTests {
    struct FakeSession: SessionProviding {
        let session: Session?
        let onClaim: @Sendable (String) -> Void
        let onMID: @Sendable (String) -> Void
        init(_ session: Session?,
             onClaim: @escaping @Sendable (String) -> Void = { _ in },
             onMID: @escaping @Sendable (String) -> Void = { _ in }) {
            self.session = session
            self.onClaim = onClaim
            self.onMID = onMID
        }
        func current() async -> Session? { session }
        func updateClaim(_ claim: String) async { onClaim(claim) }
        func updateMID(_ mid: String) async { onMID(mid) }
    }

    private func device() -> DeviceIdentity {
        DeviceIdentity(deviceID: "dev-1", familyDeviceID: "fam-1", mid: "MID123",
                       bloksVersionID: "bloks-1", appVersion: "309.0.0.40.113",
                       capabilities: "3brTv10=", userAgent: "UA/Test")
    }

    private func session() -> Session {
        Session(sessionid: "fake_session_id", dsUserID: "12345", claim: "0",
                device: device(), csrfToken: "c")
    }

    @Test func buildBearerEncodesAuthData() throws {
        let bearer = IGWebClient.buildBearer(for: session())
        #expect(bearer.hasPrefix("Bearer IGT:2:"))
        let b64 = String(bearer.dropFirst("Bearer IGT:2:".count))
        let data = try #require(Data(base64Encoded: b64))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["ds_user_id"] as? String == "12345")
        #expect(obj["sessionid"] as? String == "fake_session_id")
        #expect(obj["should_use_header_over_cookies"] as? Bool == true)
    }

    @Test func inboxBuildsMobileAuthedRequestAndDecodes() async throws {
        let body = try Fixture.data("inbox_real")
        MockURLProtocol.responder = { _ in (200, [:], body) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())

        let raw = try await client.inbox(limit: 20)

        #expect(!raw.inbox.threads.isEmpty)
        let req = try #require(MockURLProtocol.lastRequest)
        #expect(req.url?.host == "i.instagram.com")
        // Trailing slash is on the wire (IG requires it); URL.path strips it for display.
        #expect(req.url?.absoluteString.contains("/api/v1/direct_v2/inbox/") == true)
        #expect(req.url?.query?.contains("limit=20") == true)
        // Mobile auth + identity (deterministic headers only — Tier B is random; reserved
        // headers Host/Connection/Accept-Encoding are not asserted, per C5).
        #expect(req.value(forHTTPHeaderField: "X-IG-App-ID") == "567067343352427")
        #expect(req.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer IGT:2:") == true)
        #expect(req.value(forHTTPHeaderField: "X-IG-Device-ID") == "dev-1")
        #expect(req.value(forHTTPHeaderField: "X-IG-Family-Device-ID") == "fam-1")
        #expect(req.value(forHTTPHeaderField: "X-MID") == "MID123")
        #expect(req.value(forHTTPHeaderField: "X-IG-Capabilities") == "3brTv10=")
        #expect(req.value(forHTTPHeaderField: "User-Agent") == "UA/Test")
        #expect(req.value(forHTTPHeaderField: "IG-INTENDED-USER-ID") == "12345")
        #expect(req.value(forHTTPHeaderField: "X-IG-Nav-Chain")?.isEmpty == false)
        // Web-era headers are gone.
        #expect(req.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(req.value(forHTTPHeaderField: "X-CSRFToken") == nil)
        #expect(req.value(forHTTPHeaderField: "X-Requested-With") == nil)
        #expect(req.value(forHTTPHeaderField: "Sec-Fetch-Mode") == nil)
    }

    @Test func emptyDeviceMIDOmitsXMIDHeader() async throws {
        let body = try Fixture.data("inbox_real")
        MockURLProtocol.responder = { _ in (200, [:], body) }
        var mutableSession = session()
        mutableSession.device.mid = ""
        let client = IGWebClient(session: FakeSession(mutableSession), urlSession: MockURLProtocol.session())
        _ = try await client.inbox()
        #expect(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-MID") == nil)
    }

    @Test func inboxSendsFullInitialParamSet() async throws {
        let body = try Fixture.data("inbox_real")
        MockURLProtocol.responder = { _ in (200, [:], body) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())
        _ = try await client.inbox(limit: 20)
        let query = try #require(MockURLProtocol.lastRequest?.url?.query)
        #expect(query.contains("visual_message_return_type=unseen"))
        #expect(query.contains("thread_message_limit=10"))
        #expect(query.contains("fetch_reason=initial_snapshot"))
        #expect(query.contains("limit=20"))
        #expect(query.contains("igd_request_log_tracking_id="))
        #expect(!query.contains("cursor="))
    }

    @Test func inboxPaginationAddsCursorAndPageScroll() async throws {
        let body = try Fixture.data("inbox_real")
        MockURLProtocol.responder = { _ in (200, [:], body) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())
        _ = try await client.inbox(limit: 20, cursor: "CUR123")
        let query = try #require(MockURLProtocol.lastRequest?.url?.query)
        #expect(query.contains("cursor=CUR123"))
        #expect(query.contains("direction=older"))
        #expect(query.contains("fetch_reason=page_scroll"))
        #expect(!query.contains("fetch_reason=initial_snapshot"))
    }

    @Test func threadBuildsRequestWithIDAndDecodes() async throws {
        let body = try Fixture.data("thread_real")
        MockURLProtocol.responder = { _ in (200, [:], body) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())

        let raw = try await client.thread(id: "rt_real_1")

        #expect(!raw.thread.items.isEmpty)
        let req = try #require(MockURLProtocol.lastRequest)
        #expect(req.url?.host == "i.instagram.com")
        #expect(req.url?.absoluteString.contains("/api/v1/direct_v2/threads/rt_real_1/") == true)
        #expect(req.url?.query?.contains("limit=20") == true)   // was 40 (V1); instagrapi default is 20
    }

    @Test func threadSendsFullParamSet() async throws {
        let body = try Fixture.data("thread_real")
        MockURLProtocol.responder = { _ in (200, [:], body) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())
        _ = try await client.thread(id: "rt_real_1")
        let query = try #require(MockURLProtocol.lastRequest?.url?.query)
        #expect(query.contains("visual_message_return_type=unseen"))
        #expect(query.contains("direction=older"))
        #expect(query.contains("seq_id=40065"))
        #expect(query.contains("limit=20"))
        #expect(!query.contains("cursor="))
    }

    @Test func threadPaginationAddsCursor() async throws {
        let body = try Fixture.data("thread_real")
        MockURLProtocol.responder = { _ in (200, [:], body) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())
        _ = try await client.thread(id: "rt_real_1", cursor: "TC9")
        let query = try #require(MockURLProtocol.lastRequest?.url?.query)
        #expect(query.contains("cursor=TC9"))
    }

    @Test func capturesMIDFromResponseHeader() async throws {
        let body = try Fixture.data("inbox_real")
        MockURLProtocol.responder = { _ in (200, ["ig-set-x-mid": "MID_FROM_SERVER"], body) }
        let captured = ClaimBox()
        let client = IGWebClient(session: FakeSession(session(), onMID: { captured.value = $0 }),
                                 urlSession: MockURLProtocol.session())
        _ = try await client.inbox()
        #expect(captured.value == "MID_FROM_SERVER")
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
