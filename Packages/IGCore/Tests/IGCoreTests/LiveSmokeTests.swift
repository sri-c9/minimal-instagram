import Foundation
import Testing
@testable import IGCore

// LIVE smoke tests — these hit REAL Instagram and are INERT unless you supply a
// session through environment variables. The normal `swift test` run never touches
// the network: with no env vars set, each test prints a skip notice and passes.
//
// Run explicitly (capture the values from a logged-in browser's DevTools → Network →
// any /api/v1/... request → Request Headers):
//
//   IG_COOKIE='sessionid=…; csrftoken=…; ds_user_id=…' \
//   IG_CSRF='…' \
//   IG_UA='Mozilla/5.0 (…) …' \
//     swift test --filter LiveSmokeTests
//
// SECURITY: a real sessionid is password-grade — never hardcode it, never commit it.
// These tests print COUNTS ONLY (no message text, names, or IDs) so real DM content
// never lands in your terminal scrollback or CI logs.
//
// BAN-RISK: use your browser's exact User-Agent, run from the same machine/IP, and
// run sparingly. Automated fetches with a mismatched fingerprint are the risky pattern.
@Suite(.serialized) struct LiveSmokeTests {

    /// A real session built from the environment, or nil (the test then no-ops).
    private func liveSession() -> Session? {
        let env = ProcessInfo.processInfo.environment
        guard let cookie = env["IG_COOKIE"], !cookie.isEmpty,
              let csrf = env["IG_CSRF"], !csrf.isEmpty,
              let ua = env["IG_UA"], !ua.isEmpty else { return nil }
        // dsUserID isn't sent as its own header (it rides in the cookie), so "" is fine here.
        return Session(cookieHeader: cookie, csrfToken: csrf, dsUserID: "", userAgent: ua)
    }

    /// Wires a real session through SessionStore into a client backed by the real network.
    private func liveClient(_ session: Session) async throws -> IGWebClient {
        let store = SessionStore(store: InMemorySecureStore())
        try await store.save(session)
        return IGWebClient(session: store)   // real URLSession.shared — NOT MockURLProtocol
    }

    @Test func liveInboxAndThreadSmoke() async throws {
        guard let session = liveSession() else {
            print("⏭️  LiveSmoke skipped — set IG_COOKIE / IG_CSRF / IG_UA to run against real Instagram.")
            return
        }
        let client = try await liveClient(session)

        // 1) Inbox: real JSON → decoded DTOs → firewall → domain Conversations.
        let rawInbox = try await client.inbox(limit: 10)
        let convos = DomainMapper.mapInbox(rawInbox)
        print("✅ inbox: \(rawInbox.inbox.threads.count) raw threads → \(convos.count) mapped conversations")
        #expect(!convos.isEmpty)

        // 2) First thread end-to-end. The raw→mapped delta is the firewall dropping
        //    ads/suggestions/unknown item types on live data.
        guard let firstID = rawInbox.inbox.threads.first?.threadID, !firstID.isEmpty else {
            print("ℹ️  no threads to drill into")
            return
        }
        let rawThread = try await client.thread(id: firstID, limit: 20)
        let detail = DomainMapper.mapThread(rawThread)
        let rawCount = rawThread.thread.items.count
        let dropped = rawCount - detail.items.count
        print("✅ thread: \(rawCount) raw items → \(detail.items.count) mapped items (firewall dropped \(dropped))")
        #expect(!detail.id.isEmpty)
    }
}
