import Foundation

/// An authenticated IG session for the mobile private API (§5.1). Minted once via
/// WebView web login (deferred), persisted in the Keychain. `Authorization: Bearer IGT:2:`
/// is built from `sessionid` + `dsUserID` (§7); `device` is the stable fingerprint (§5.2);
/// `claim` self-refreshes from response headers. `csrfToken` is retained only for the
/// deferred write (POST) path — it is NOT sent on reads.
public struct Session: Sendable, Equatable, Codable {
    public var sessionid: String       // password-grade; the Bearer is built from this
    public var dsUserID: String        // ds_user_id; sent as IG-INTENDED-USER-ID
    public var claim: String           // X-IG-WWW-Claim; "0" until a response sets it
    public var device: DeviceIdentity  // stable fingerprint incl. rendered userAgent (§5.2)
    public var csrfToken: String       // deferred POST path only; NOT sent on reads

    public init(sessionid: String, dsUserID: String, claim: String = "0",
                device: DeviceIdentity, csrfToken: String = "") {
        self.sessionid = sessionid
        self.dsUserID = dsUserID
        self.claim = claim
        self.device = device
        self.csrfToken = csrfToken
    }
}
