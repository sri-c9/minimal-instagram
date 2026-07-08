import Foundation

private struct IGAuthorizationPayload: Encodable {
    let dsUserID: String
    let sessionid: String
    let shouldUseHeaderOverCookies: Bool

    enum CodingKeys: String, CodingKey {
        case dsUserID = "ds_user_id"
        case sessionid
        case shouldUseHeaderOverCookies = "should_use_header_over_cookies"
    }
}

/// Pure transport: authed GETs to i.instagram.com/api/v1/direct_v2/*, returns raw DTOs.
/// No mapping (DomainMapper does that). Builds the iOS private-API header set (§5.3) +
/// Bearer auth (§7); refreshes X-IG-WWW-Claim from responses.
struct IGWebClient: Sendable {
    private let session: any SessionProviding
    private let urlSession: URLSession
    private let appID = "567067343352427"
    private static let navChain =
        "9MV:self_profile:2,ProfileMediaTabFragment:self_profile:3,9Xf:self_following:4"

    init(session: any SessionProviding, urlSession: URLSession = .shared) {
        self.session = session
        self.urlSession = urlSession
    }

    func inbox(limit: Int = 20, cursor: String? = nil) async throws -> RawInboxResponse {
        var query = [
            "visual_message_return_type": "unseen",
            "thread_message_limit": "10",
            "persistentBadging": "true",
            "limit": String(limit),
            "is_prefetching": "false",
            "fetch_reason": "initial_snapshot",
            "include_old_mrs": "false",
            "no_pending_badge": "true",
            "push_disabled": "false",
            "eb_device_id": "0",
            "igd_request_log_tracking_id": UUID().uuidString
        ]
        if let cursor {
            query["cursor"] = cursor
            query["direction"] = "older"
            query["fetch_reason"] = "page_scroll"   // overrides initial_snapshot
        }
        return try await get("/api/v1/direct_v2/inbox/", query: query, as: RawInboxResponse.self)
    }

    func thread(id: String, limit: Int = 20, cursor: String? = nil) async throws -> RawThreadResponse {
        var query = [
            "visual_message_return_type": "unseen",
            "direction": "older",
            "seq_id": "40065",
            "limit": String(limit)
        ]
        if let cursor { query["cursor"] = cursor }
        return try await get("/api/v1/direct_v2/threads/\(id)/", query: query, as: RawThreadResponse.self)
    }

    // Shared request builder + claim refresh + error mapping.
    private func get<T: Decodable>(_ path: String, query: [String: String], as type: T.Type) async throws -> T {
        guard let session = await session.current() else { throw IGClientError.needsLogin }
        guard var comps = URLComponents(string: "https://i.instagram.com") else { throw IGClientError.transport }
        comps.path = path
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw IGClientError.transport }
        var req = URLRequest(url: url)
        applyHeaders(to: &req, session)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: req)
        } catch {
            throw IGClientError.transport
        }
        guard let http = response as? HTTPURLResponse else { throw IGClientError.transport }

        // Self-refreshing claim (§7). Header names are case-insensitive; allHeaderFields
        // avoids value(forHTTPHeaderField:) which requires a newer host-OS floor than the package sets.
        let newClaim = http.allHeaderFields.first {
            ($0.key as? String)?.caseInsensitiveCompare("x-ig-set-www-claim") == .orderedSame
        }?.value as? String
        if let newClaim {
            await self.session.updateClaim(newClaim)
        }

        // MID bootstrap (§7): the one "set" header that can arrive on a read. Case-insensitive.
        let newMID = http.allHeaderFields.first {
            ($0.key as? String)?.caseInsensitiveCompare("ig-set-x-mid") == .orderedSame
        }?.value as? String
        if let newMID, !newMID.isEmpty {
            await self.session.updateMID(newMID)
        }

        try Self.checkStatus(http, data: data)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw IGClientError.decoding
        }
    }

    /// Applies the iOS private-API header set: Tier A (stable device identity), Tier B
    /// (per-request noise), Tier C (shared infra incl. Bearer). Tier D (IG-U-*) is omitted
    /// until IG issues it (§5.3). Reserved headers (Host/Connection/Accept-Encoding) are set
    /// for fidelity but URLSession may override them (C5) — tests never assert them.
    private func applyHeaders(to req: inout URLRequest, _ session: Session) {
        let device = session.device
        func set(_ value: String, _ header: String) { req.setValue(value, forHTTPHeaderField: header) }

        // Tier A — stable device identity
        set(device.deviceID, "X-IG-Device-ID")
        set(device.familyDeviceID, "X-IG-Family-Device-ID")
        if !device.mid.isEmpty { set(device.mid, "X-MID") }   // omit until bootstrapped (C10)
        set(device.bloksVersionID, "X-Bloks-Version-Id")
        set(appID, "X-IG-App-ID")
        set(device.capabilities, "X-IG-Capabilities")
        set(device.userAgent, "User-Agent")
        set("US", "X-IG-App-Startup-Country")
        set(String(TimeZone.current.secondsFromGMT()), "X-IG-Timezone-Offset")  // signed seconds (C12)
        set("WIFI", "X-IG-Connection-Type")
        set("false", "X-Bloks-Is-Layout-RTL")
        set("true", "X-Bloks-Is-Panorama-Enabled")
        set("en_US", "X-IG-App-Locale")
        set("en_US", "X-IG-Device-Locale")
        set("en_US", "X-IG-Mapped-Locale")
        set(session.dsUserID, "IG-INTENDED-USER-ID")
        set(Self.navChain, "X-IG-Nav-Chain")

        // Tier B — per-request noise
        set("UFS-\(UUID().uuidString)-1", "X-Pigeon-Session-Id")
        set(String(format: "%.3f", Date().timeIntervalSince1970), "X-Pigeon-Rawclienttime")
        set(String(format: "%.3f", Double.random(in: 2500...3000)), "X-IG-Bandwidth-Speed-KBPS")
        set(String(Int.random(in: 5_000_000...90_000_000)), "X-IG-Bandwidth-TotalBytes-B")
        set(String(Int.random(in: 2000...9000)), "X-IG-Bandwidth-TotalTime-MS")
        set(String(Int.random(in: 1_061_162_222...1_061_262_222)), "X-IG-SALT-IDS")

        // Tier C — shared infra
        set(Self.buildBearer(for: session), "Authorization")
        set("u=3", "Priority")
        set("en-US", "Accept-Language")
        set("gzip, deflate", "Accept-Encoding")
        set("i.instagram.com", "Host")
        set("Tigon/MNS/TCP", "X-FB-HTTP-Engine")
        set("False", "X-Tigon-Is-Retry")
        set("keep-alive", "Connection")
        set("True", "X-FB-Client-IP")
        set("True", "X-FB-Server-Cluster")
        set(session.claim, "X-IG-WWW-Claim")
        set("INIT", "X-Zero-Balance")
        set("unknown", "X-Zero-State")
        set("wifi", "Zero-HTTP-Network-Interface")
    }

    /// Builds `Authorization: Bearer IGT:2:<base64>` from the session (§7). The credential
    /// is base64 of `{ds_user_id, sessionid, should_use_header_over_cookies:true}`.
    /// `.sortedKeys` makes the bytes reproducible (C6); `dsUserID` is taken from the session,
    /// never re-derived from the sessionid (C13). No cookie, no signing (GET).
    static func buildBearer(for session: Session) -> String {
        let payload = IGAuthorizationPayload(dsUserID: session.dsUserID, sessionid: session.sessionid,
                                             shouldUseHeaderOverCookies: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let json = try? encoder.encode(payload) else { return "" }
        return "Bearer IGT:2:\(json.base64EncodedString())"
    }

    /// Maps an HTTP response to a thrown `IGClientError`, or returns normally if OK.
    /// IG signals a dead/blocked session two ways — both map to `.needsLogin`:
    /// (1) a 401/403 status, or (2) a 200 whose body still says login_required /
    /// checkpoint_required (IG often returns 200 with a failure payload). Any other
    /// non-2xx is a generic `.http(code)`.
    static func checkStatus(_ http: HTTPURLResponse, data: Data) throws {
        switch http.statusCode {
        case 401, 403:
            throw IGClientError.needsLogin
        case 200:
            if let body = String(data: data, encoding: .utf8),
               body.contains("login_required") || body.contains("checkpoint_required") {
                throw IGClientError.needsLogin
            }
        default:
            break
        }

        guard (200..<300).contains(http.statusCode) else { throw IGClientError.http(http.statusCode) }
    }
}
