import Foundation
import Testing
@testable import IGCore

// LIVE end-to-end smoke through the REFACTORED IGWebClient (mobile host + Bearer).
// INERT unless IG_SESSIONID is set; a plain `swift test` prints a skip notice and passes.
// Complements LiveTransportProbeV2 (standalone, validates the design): this exercises the
// actual production transport — Session → SessionStore → IGWebClient → DomainMapper.
//
//   IG_SESSIONID='<raw sessionid>' \
//   IG_IOS_UA='Instagram 309.0.0.40.113 (iPhone15,3; iOS 17_5_1; en_US; en-US; scale=3.00; 1179x2556; 0) AppleWebKit/605.1.15' \
//     swift test --filter LiveSmokeTests
//
//   Optional overrides: IG_DSUSERID, IG_MID, IG_DEVICE_ID, IG_FAMILY_ID, IG_BLOKS, IG_APP_VERSION.
//
// SECURITY: sessionid is password-grade — never hardcode/commit; rotate after probing.
// Prints COUNTS ONLY (no message text, names, or IDs).
@Suite(.serialized) struct LiveSmokeTests {

    private func liveSession() -> Session? {
        let env = ProcessInfo.processInfo.environment
        guard let sid = env["IG_SESSIONID"], !sid.isEmpty else { return nil }
        func opt(_ k: String) -> String? { env[k].flatMap { $0.isEmpty ? nil : $0 } }
        let ds = opt("IG_DSUSERID") ?? String(sid.prefix { $0.isNumber })
        let ua = opt("IG_IOS_UA")
            ?? "Instagram 309.0.0.40.113 (iPhone15,3; iOS 17_5_1; en_US; en-US; scale=3.00; 1179x2556; 0) AppleWebKit/605.1.15"
        let device = DeviceIdentity(
            deviceID: opt("IG_DEVICE_ID") ?? UUID().uuidString,
            familyDeviceID: opt("IG_FAMILY_ID") ?? UUID().uuidString,
            mid: env["IG_MID"] ?? "",
            bloksVersionID: opt("IG_BLOKS") ?? String(repeating: "0", count: 64),
            appVersion: opt("IG_APP_VERSION") ?? "309.0.0.40.113",
            capabilities: "3brTv10=",
            userAgent: ua)
        return Session(sessionid: sid, dsUserID: ds, claim: "0", device: device)
    }

    private func liveClient(_ session: Session) async throws -> IGWebClient {
        let store = SessionStore(store: InMemorySecureStore())
        try await store.save(session)
        return IGWebClient(session: store)   // real URLSession.shared — NOT MockURLProtocol
    }

    @Test func liveInboxAndThreadSmoke() async throws {
        guard let session = liveSession() else {
            print("⏭️  LiveSmoke skipped — set IG_SESSIONID (and ideally IG_IOS_UA) to run.")
            return
        }
        let client = try await liveClient(session)

        let rawInbox = try await client.inbox(limit: 10)
        let convos = DomainMapper.mapInbox(rawInbox)
        print("✅ inbox: \(rawInbox.inbox.threads.count) raw threads → \(convos.count) mapped conversations")
        #expect(!convos.isEmpty)

        guard let firstID = rawInbox.inbox.threads.first?.threadID, !firstID.isEmpty else {
            print("ℹ️  no threads to drill into"); return
        }
        let rawThread = try await client.thread(id: firstID, limit: 20)
        let detail = DomainMapper.mapThread(rawThread)
        print("✅ thread: \(rawThread.thread.items.count) raw items → \(detail.items.count) mapped items")
        #expect(!detail.id.isEmpty)
    }
}
