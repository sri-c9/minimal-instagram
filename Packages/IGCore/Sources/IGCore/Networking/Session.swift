import Foundation

/// An authenticated IG web session. Captured once via WebView login (later increment),
/// persisted in the Keychain. `claim` self-refreshes from response headers; `userAgent`
/// is the exact WebView UA so JSON calls match the login fingerprint (§7).
public struct Session: Sendable, Equatable, Codable {
    public var cookieHeader: String   // full Cookie: header value (sessionid=...; csrftoken=...; ds_user_id=...)
    public var csrfToken: String      // csrftoken cookie value, sent as X-CSRFToken
    public var dsUserID: String       // ds_user_id
    public var claim: String          // X-IG-WWW-Claim; "0" until the first response sets it
    public var userAgent: String

    public init(cookieHeader: String, csrfToken: String, dsUserID: String, claim: String = "0", userAgent: String) {
        self.cookieHeader = cookieHeader
        self.csrfToken = csrfToken
        self.dsUserID = dsUserID
        self.claim = claim
        self.userAgent = userAgent
    }
}
