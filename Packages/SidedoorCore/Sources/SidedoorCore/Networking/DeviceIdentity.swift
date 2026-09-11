import Foundation

/// Stable per-install device fingerprint for the iOS private-API profile (§5.2).
/// Minted once by the (deferred) auth coordinator, Keychain-persisted via `Session`,
/// loaded before login, and NEVER regenerated — regeneration reads as a new device and
/// invites re-login/flagging. `mid` is the one mutable field: it starts empty and is
/// bootstrapped from the first `ig-set-x-mid` response header (§7).
public struct DeviceIdentity: Sendable, Equatable, Codable {
    public var deviceID: String        // X-IG-Device-ID (UUID)
    public var familyDeviceID: String  // X-IG-Family-Device-ID (UUID)
    public var mid: String             // X-MID ("" until IG sends ig-set-x-mid)
    public var bloksVersionID: String  // X-Bloks-Version-Id
    public var appVersion: String      // renders into userAgent
    public var capabilities: String    // X-IG-Capabilities (e.g. "3brTv10=")
    public var userAgent: String       // User-Agent (rendered once from appVersion + device values)

    public init(deviceID: String, familyDeviceID: String, mid: String = "",
                bloksVersionID: String, appVersion: String, capabilities: String, userAgent: String) {
        self.deviceID = deviceID
        self.familyDeviceID = familyDeviceID
        self.mid = mid
        self.bloksVersionID = bloksVersionID
        self.appVersion = appVersion
        self.capabilities = capabilities
        self.userAgent = userAgent
    }
}
