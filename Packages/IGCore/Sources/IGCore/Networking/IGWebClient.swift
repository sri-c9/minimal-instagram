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
        guard var comps = URLComponents(string: "https://www.instagram.com") else { throw IGClientError.transport }
        comps.path = path
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw IGClientError.transport }
        var req = URLRequest(url: url)
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
