import Foundation

/// Pure transport: authed GETs to instagram.com/api/v1/direct_v2/*, returns raw DTOs.
/// No mapping (DomainMapper does that). Refreshes X-IG-WWW-Claim from responses (§7).
struct IGWebClient: Sendable {
    private let session: any SessionProviding
    private let urlSession: URLSession
    private let appID = "936619743392459"

    init(session: any SessionProviding, urlSession: URLSession = .shared) {
        self.session = session
        self.urlSession = urlSession
    }

    func inbox(limit: Int = 20) async throws -> RawInboxResponse {
        try await get("/api/v1/direct_v2/inbox/", query: ["limit": String(limit)], as: RawInboxResponse.self)
    }

    func thread(id: String, limit: Int = 40) async throws -> RawThreadResponse {
        try await get("/api/v1/direct_v2/threads/\(id)/", query: ["limit": String(limit)], as: RawThreadResponse.self)
    }

    // Shared request builder + claim refresh + error mapping.
    private func get<T: Decodable>(_ path: String, query: [String: String], as type: T.Type) async throws -> T {
        guard let session = await session.current() else { throw IGClientError.needsLogin }
        var comps = URLComponents(string: "https://www.instagram.com")!
        comps.path = path
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!)
        req.setValue(appID, forHTTPHeaderField: "X-IG-App-ID")
        req.setValue(session.claim, forHTTPHeaderField: "X-IG-WWW-Claim")
        req.setValue(session.csrfToken, forHTTPHeaderField: "X-CSRFToken")
        req.setValue(session.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")

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

        try Self.checkStatus(http, data: data)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw IGClientError.decoding
        }
    }

    /// Maps an HTTP response to a thrown `IGClientError`, or returns normally if OK.
    static func checkStatus(_ http: HTTPURLResponse, data: Data) throws {
        // TODO(human): the session-death firewall. IG signals an expired/blocked
        // session in two ways — map BOTH to `IGClientError.needsLogin`:
        //   1. status 401 or 403
        //   2. a 200 body that still contains "login_required" or "checkpoint_required"
        //      (IG often returns 200 with a failure message)
        // Any other non-2xx status should throw `IGClientError.http(http.statusCode)`.
        // The minimal stub below only handles the success case, so the error tests fail.
        guard (200..<300).contains(http.statusCode) else { throw IGClientError.http(http.statusCode) }
    }
}
