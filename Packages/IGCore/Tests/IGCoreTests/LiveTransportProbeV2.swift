import Foundation
import Testing
@testable import IGCore

// LIVE V2 transport probe — validates the Technical Design (V2) transport assumptions
// (host i.instagram.com + Bearer IGT:2 + the iOS header set) BEFORE we refactor
// IGWebClient. It is INERT unless you supply a session via environment variables;
// a plain `swift test` run prints a skip notice and passes without touching the network.
//
// It is deliberately STANDALONE — it does NOT go through IGWebClient (which is still
// web-era). A red result here therefore indicts the *design*, not an in-progress refactor.
//
// Run explicitly against the SECONDARY account (capture the sessionid from a logged-in
// browser's DevTools → Application → Cookies → instagram.com → sessionid):
//
//   IG_SESSIONID='<raw sessionid value>' \
//   IG_IOS_UA='Instagram 309.0.0.40.113 (iPhone15,3; iOS 17_5_1; en_US; en-US; scale=3.00; 1179x2556; 0) AppleWebKit/605.1.15' \
//     swift test --filter LiveTransportProbeV2
//
//   Optional overrides (else derived/defaulted): IG_DSUSERID, IG_MID, IG_THREAD_ID,
//   IG_DEVICE_ID, IG_FAMILY_ID, IG_BLOKS, IG_APP_VERSION.
//
// SECURITY: the sessionid is password-grade — never hardcode it, never commit it, and
// rotate it after probing. This probe prints ONLY HTTP status, byte counts, top-level
// JSON key NAMES, and counts — never the sessionid, the Bearer, header values, thread
// IDs, or any DM content. Nothing here should let real data into terminal scrollback.
//
// BAN-RISK: device identity is "sacred" — pass IG_DEVICE_ID/IG_FAMILY_ID/IG_MID to reuse
// one identity across runs; otherwise each run looks like a new device. Run sparingly.
@Suite(.serialized) struct LiveTransportProbeV2 {

    // Pinned app-tier constants (see Technical Design V2 §5.3). Override via env to pin
    // current real values; the defaults are plausible placeholders for a one-off probe.
    private static let appID = "567067343352427"
    private static let capabilities = "3brTv10="
    private static let navChain = "9MV:self_profile:2,ProfileMediaTabFragment:self_profile:3,9Xf:self_following:4"
    private static let defaultAppVersion = "309.0.0.40.113"
    private static let defaultBloks = "0000000000000000000000000000000000000000000000000000000000000000"
    private static let defaultIOSUA =
        "Instagram 309.0.0.40.113 (iPhone15,3; iOS 17_5_1; en_US; en-US; scale=3.00; 1179x2556; 0) AppleWebKit/605.1.15"

    /// Per-run inputs resolved from the environment. `nil` sessionid ⇒ the probe no-ops.
    private struct Inputs {
        let sessionid: String
        let dsUserID: String
        let userAgent: String
        let bloks: String
        let appVersion: String
        var mid: String          // may start empty; bootstrapped from ig-set-x-mid
        let deviceID: String
        let familyID: String
        let threadID: String?    // else derived from the inbox response
    }

    private func inputs() -> Inputs? {
        let env = ProcessInfo.processInfo.environment
        guard let sid = env["IG_SESSIONID"], !sid.isEmpty else { return nil }
        // ds_user_id is the leading digits of the sessionid (instagrapi auth.py), unless overridden.
        let derivedDS = String(sid.prefix { $0.isNumber })
        return Inputs(
            sessionid: sid,
            dsUserID: env["IG_DSUSERID"].flatMap { $0.isEmpty ? nil : $0 } ?? derivedDS,
            userAgent: env["IG_IOS_UA"].flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultIOSUA,
            bloks: env["IG_BLOKS"].flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultBloks,
            appVersion: env["IG_APP_VERSION"].flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultAppVersion,
            mid: env["IG_MID"] ?? "",
            deviceID: env["IG_DEVICE_ID"].flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString,
            familyID: env["IG_FAMILY_ID"].flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString,
            threadID: env["IG_THREAD_ID"].flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    /// Builds the `Authorization: Bearer IGT:2:<base64>` header value (Technical Design V2 §7).
    ///
    /// The credential is the base64 of a JSON object with exactly these keys:
    ///   { "ds_user_id": <dsUserID>, "sessionid": <sessionid>, "should_use_header_over_cookies": true }
    /// then prefixed with "Bearer IGT:2:". No cookie, no signing (GET).
    private func buildBearer(sessionid: String, dsUserID: String) -> String {
        // Codable struct → Bool serializes as JSON `true` (not "true"); .sortedKeys makes
        // the byte output reproducible (C6). Sorted order: ds_user_id, sessionid,
        // should_use_header_over_cookies.
        struct AuthData: Encodable {
            let ds_user_id: String
            let sessionid: String
            let should_use_header_over_cookies: Bool
        }
        let payload = AuthData(ds_user_id: dsUserID, sessionid: sessionid, should_use_header_over_cookies: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let json = try? encoder.encode(payload) else { return "" }
        return "Bearer IGT:2:\(json.base64EncodedString())"
    }

    /// Applies the full V2 iOS header set (Tier A stable / B noise / C infra) to `req`.
    private func applyV2Headers(to req: inout URLRequest, _ i: Inputs) {
        func set(_ v: String, _ h: String) { req.setValue(v, forHTTPHeaderField: h) }

        // Tier A — stable device identity
        set(i.deviceID, "X-IG-Device-ID")
        set(i.familyID, "X-IG-Family-Device-ID")
        if !i.mid.isEmpty { set(i.mid, "X-MID") }   // omit until bootstrapped (C10)
        set(i.bloks, "X-Bloks-Version-Id")
        set(Self.appID, "X-IG-App-ID")
        set(Self.capabilities, "X-IG-Capabilities")
        set(i.userAgent, "User-Agent")
        set("US", "X-IG-App-Startup-Country")
        set(String(TimeZone.current.secondsFromGMT()), "X-IG-Timezone-Offset")  // signed (C12)
        set("WIFI", "X-IG-Connection-Type")
        set("false", "X-Bloks-Is-Layout-RTL")
        set("true", "X-Bloks-Is-Panorama-Enabled")
        set("en_US", "X-IG-App-Locale")
        set("en_US", "X-IG-Device-Locale")
        set("en_US", "X-IG-Mapped-Locale")
        set(i.dsUserID, "IG-INTENDED-USER-ID")
        set(Self.navChain, "X-IG-Nav-Chain")

        // Tier B — per-request noise
        set("UFS-\(UUID().uuidString)-1", "X-Pigeon-Session-Id")
        set(String(format: "%.3f", Date().timeIntervalSince1970), "X-Pigeon-Rawclienttime")
        set(String(format: "%.3f", Double.random(in: 2500...3000)), "X-IG-Bandwidth-Speed-KBPS")
        set(String(Int.random(in: 5_000_000...90_000_000)), "X-IG-Bandwidth-TotalBytes-B")
        set(String(Int.random(in: 2000...9000)), "X-IG-Bandwidth-TotalTime-MS")
        set(String(Int.random(in: 1_061_162_222...1_061_262_222)), "X-IG-SALT-IDS")

        // Tier C — shared infra (Authorization + plumbing). Host/Connection/Accept-Encoding
        // are URLSession-managed (C5) — set for fidelity; the system may override them.
        set(buildBearer(sessionid: i.sessionid, dsUserID: i.dsUserID), "Authorization")
        set("u=3", "Priority")
        set("en-US", "Accept-Language")
        set("gzip, deflate", "Accept-Encoding")
        set("i.instagram.com", "Host")
        set("Tigon/MNS/TCP", "X-FB-HTTP-Engine")
        set("False", "X-Tigon-Is-Retry")
        set("keep-alive", "Connection")
        set("True", "X-FB-Client-IP")
        set("True", "X-FB-Server-Cluster")
        set("0", "X-IG-WWW-Claim")
        set("INIT", "X-Zero-Balance")
        set("unknown", "X-Zero-State")
        set("wifi", "Zero-HTTP-Network-Interface")
    }

    /// GETs a V2 request and prints a PII-safe summary (status, bytes, JSON key names, count).
    /// Returns the parsed top-level object so the caller can derive a thread id.
    @discardableResult
    private func probe(_ label: String, path: String, query: [String: String], _ i: Inputs) async -> [String: Any]? {
        guard var comps = URLComponents(string: "https://i.instagram.com") else { return nil }
        comps.path = path
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        applyV2Headers(to: &req, i)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else {
            print("🔴 \(label): transport failure")
            return nil
        }
        let hasMID = http.allHeaderFields.contains { ($0.key as? String)?.caseInsensitiveCompare("ig-set-x-mid") == .orderedSame }
        let hasClaim = http.allHeaderFields.contains { ($0.key as? String)?.caseInsensitiveCompare("x-ig-set-www-claim") == .orderedSame }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keys = json?.keys.sorted().joined(separator: ", ") ?? "<unparsed>"
        let icon = (200..<300).contains(http.statusCode) ? "✅" : "🔴"
        print("\(icon) \(label): status=\(http.statusCode) bytes=\(data.count) ig-set-x-mid=\(hasMID) set-www-claim=\(hasClaim)")
        print("   top-level keys: [\(keys)]")
        return json
    }

    @Test func liveV2TransportProbe() async throws {
        guard let i = inputs() else {
            print("⏭️  LiveTransportProbeV2 skipped — set IG_SESSIONID (and ideally IG_IOS_UA) to run.")
            return
        }
        if buildBearer(sessionid: i.sessionid, dsUserID: i.dsUserID).isEmpty {
            print("⏭️  buildBearer is not implemented yet (TODO human) — fill it in to run the probe.")
            return
        }

        // 1) INBOX — full V2 param set (Technical Design V2 §5.4).
        let inbox = await probe("inbox", path: "/api/v1/direct_v2/inbox/", query: [
            "visual_message_return_type": "unseen",
            "thread_message_limit": "10",
            "persistentBadging": "true",
            "limit": "20",
            "is_prefetching": "false",
            "fetch_reason": "initial_snapshot",
            "include_old_mrs": "false",
            "no_pending_badge": "true",
            "push_disabled": "false",
            "eb_device_id": "0",
            "igd_request_log_tracking_id": UUID().uuidString,
        ], i)

        // Print thread count + cursor presence (no IDs).
        if let inboxObj = inbox?["inbox"] as? [String: Any] {
            let threads = (inboxObj["threads"] as? [Any])?.count ?? 0
            let hasCursor = inboxObj["oldest_cursor"] != nil
            print("   inbox.threads=\(threads) has oldest_cursor=\(hasCursor)")
        }

        // 2) THREAD — derive the id from the inbox response (never printed).
        let firstThreadID = i.threadID
            ?? ((inbox?["inbox"] as? [String: Any])?["threads"] as? [[String: Any]])?
                .first?["thread_id"] as? String
        guard let threadID = firstThreadID, !threadID.isEmpty else {
            print("ℹ️  no thread id available — set IG_THREAD_ID to probe the thread endpoint.")
            return
        }
        let thread = await probe("thread", path: "/api/v1/direct_v2/threads/\(threadID)/", query: [
            "visual_message_return_type": "unseen",
            "direction": "older",
            "seq_id": "40065",
            "limit": "20",
        ], i)
        if let threadObj = thread?["thread"] as? [String: Any] {
            let items = (threadObj["items"] as? [Any])?.count ?? 0
            let hasCursor = threadObj["oldest_cursor"] != nil
            print("   thread.items=\(items) has oldest_cursor=\(hasCursor)")
        }
    }
}
