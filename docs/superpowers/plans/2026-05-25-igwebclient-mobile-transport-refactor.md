# IGWebClient Mobile-Transport Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the read path (`inbox`/`thread`) off the web host onto Instagram's mobile private API (`i.instagram.com`) — Bearer auth, the iOS device header set, full param sets with pagination, and MID/claim capture — with `DomainMapper`, the domain models, and the UI untouched.

**Architecture:** Anti-corruption boundary. All Instagram churn is contained to `IGWebClient` + `Session`/`DeviceIdentity` + the `Raw*DTO` layer. The refactor uses **expand-contract** for the `Session` type change: expand (add new fields, Task 1) → migrate consumers (Tasks 2–8) → contract (drop dead web fields, Task 9). Every task ends with a compilable tree and a green `swift test`.

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM, Swift Testing (`import Testing`, `@Test`, `#expect`), `MockURLProtocol` for transport tests. Reference: instagrapi.

**Spec:** `docs/Technical Design (V2).md` (this plan implements §5.1–§5.4 and §7). Transport already validated live by `LiveTransportProbeV2` (inbox + thread → HTTP 200 on `i.instagram.com`, 2026-05-24).

**Working directory for all commands:** `Packages/IGCore`

**Commits:** Per the user's workflow (commit only when explicitly requested), each task's checkpoint is a **green `swift test`**, not a commit. The executor should pause for review at each checkpoint and only `git commit` when the user asks. A suggested commit message is included per task for when that moment comes.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `Sources/IGCore/Networking/DeviceIdentity.swift` | **Create** | Stable per-install iOS fingerprint (§5.2); Keychain-persisted via `Session`. |
| `Sources/IGCore/Networking/Session.swift` | Modify (T1 expand, T9 contract) | Mobile session: `sessionid` + `dsUserID` + `claim` + `device` (+ retained `csrfToken` for the deferred write path). |
| `Sources/IGCore/Networking/IGWebClient.swift` | Modify (T2,T3,T5,T6,T8) | Mobile transport: host `i`, Bearer, iOS header tiers, full params + pagination, MID/claim capture. |
| `Sources/IGCore/Networking/SessionStore.swift` | Modify (T7) | Add `updateMID(_:)` seam parallel to `updateClaim(_:)`. |
| `Sources/IGCore/Mapper/RawInboxDTO.swift` | Modify (T4) | Decode `inbox.oldest_cursor` (optional) for pagination. |
| `Sources/IGCore/Mapper/RawThreadDTO.swift` | Modify (T4) | Decode `thread.oldest_cursor` (optional) for pagination. |
| `Tests/IGCoreTests/IGWebClientTests.swift` | Modify (T1,T2,T3,T5,T6,T7,T8) | Mobile header/param/Bearer/MID assertions; `FakeSession` gains `updateMID`. |
| `Tests/IGCoreTests/SessionStoreTests.swift` | Modify (T1,T7,T9) | `sample()` to new shape; `updateMID` test. |
| `Tests/IGCoreTests/RawDTOCursorTests.swift` | **Create** (T4) | DTO `oldest_cursor` decode tests. |
| `Tests/IGCoreTests/Fixtures/inbox_mobile.json` | **Create** (T4) | Scrubbed synthetic mobile inbox incl. `oldest_cursor`. |
| `Tests/IGCoreTests/Fixtures/thread_mobile.json` | **Create** (T4) | Scrubbed synthetic mobile thread incl. `oldest_cursor`. |
| `Tests/IGCoreTests/LiveSmokeTests.swift` | Modify (T9) | Rewrite as live end-to-end **through the refactored client**. |

`Package.swift` already declares `.copy("Fixtures")`, so new fixture files are bundled automatically — no manifest change.

**Out of scope (unchanged):** `DomainMapper`, domain models, firewall, UI/App, `MediaFetcher`. Send/write (POST + `signed_body` + CSRF) and auth-minting (WebView login that generates `Session`+`DeviceIdentity`) are deferred increments. `DeviceIdentity` is a plain data holder here — minting it from real device values belongs to the deferred `AuthCoordinator`.

---

## Task 1: Create `DeviceIdentity` + expand `Session` (no behavior change)

**Files:**
- Create: `Sources/IGCore/Networking/DeviceIdentity.swift`
- Modify: `Sources/IGCore/Networking/Session.swift`
- Modify: `Tests/IGCoreTests/IGWebClientTests.swift` (add `device()` helper; update `session()`; fix one Cookie assertion)
- Modify: `Tests/IGCoreTests/SessionStoreTests.swift` (update `sample()`)
- Test: `Tests/IGCoreTests/SessionStoreTests.swift` (new Codable round-trip test)

Expand phase: `Session` gains `sessionid` + `device` but **keeps** `cookieHeader`/`userAgent`/`csrfToken` so the still-web `IGWebClient` and the existing web header assertions keep compiling. They are removed in Task 9.

- [ ] **Step 1: Create `DeviceIdentity`**

```swift
// Sources/IGCore/Networking/DeviceIdentity.swift
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
```

- [ ] **Step 2: Expand `Session` (additive)**

Replace the whole body of `Sources/IGCore/Networking/Session.swift`:

```swift
import Foundation

/// An authenticated IG session for the mobile private API (§5.1). Minted once via
/// WebView web login (deferred), persisted in the Keychain. The request
/// `Authorization: Bearer IGT:2:` is built from `sessionid` + `dsUserID` (§7);
/// `device` is the stable fingerprint (§5.2). `claim` self-refreshes from response headers.
///
/// EXPAND-CONTRACT: `cookieHeader` and `userAgent` are web-era and removed in Task 9.
/// They are kept now only so the still-web IGWebClient and its assertions compile.
public struct Session: Sendable, Equatable, Codable {
    public var sessionid: String       // password-grade; the Bearer is built from this
    public var dsUserID: String        // ds_user_id; sent as IG-INTENDED-USER-ID
    public var claim: String           // X-IG-WWW-Claim; "0" until a response sets it
    public var device: DeviceIdentity  // stable fingerprint incl. rendered userAgent (§5.2)
    public var csrfToken: String       // retained for the deferred POST path only; NOT sent on reads
    public var cookieHeader: String    // web-era — removed in Task 9
    public var userAgent: String       // web-era — moved into DeviceIdentity; removed in Task 9

    public init(sessionid: String = "", cookieHeader: String, csrfToken: String,
                dsUserID: String, claim: String = "0", userAgent: String, device: DeviceIdentity) {
        self.sessionid = sessionid
        self.cookieHeader = cookieHeader
        self.csrfToken = csrfToken
        self.dsUserID = dsUserID
        self.claim = claim
        self.userAgent = userAgent
        self.device = device
    }
}
```

- [ ] **Step 3: Update the test factories**

In `Tests/IGCoreTests/IGWebClientTests.swift`, add a `device()` helper and replace `session()`:

```swift
    private func device() -> DeviceIdentity {
        DeviceIdentity(deviceID: "dev-1", familyDeviceID: "fam-1", mid: "MID123",
                       bloksVersionID: "bloks-1", appVersion: "309.0.0.40.113",
                       capabilities: "3brTv10=", userAgent: "UA/Test")
    }

    private func session() -> Session {
        Session(sessionid: "fake_session_id",
                cookieHeader: "sessionid=fake_session_id; csrftoken=c; ds_user_id=12345",
                csrfToken: "c", dsUserID: "12345", claim: "0", userAgent: "UA/Test", device: device())
    }
```

In the existing `inboxBuildsAuthedRequestAndDecodes` test, update the one Cookie assertion to match the new scrubbed value (the rest of that web-era test is replaced in Task 3):

```swift
        #expect(req.value(forHTTPHeaderField: "Cookie")?.contains("sessionid=fake_session_id") == true)
```

In `Tests/IGCoreTests/SessionStoreTests.swift`, replace `sample()`:

```swift
    private func device() -> DeviceIdentity {
        DeviceIdentity(deviceID: "dev-1", familyDeviceID: "fam-1", mid: "MID123",
                       bloksVersionID: "bloks-1", appVersion: "309.0.0.40.113",
                       capabilities: "3brTv10=", userAgent: "UA/1.0")
    }

    private func sample() -> Session {
        Session(sessionid: "fake_session_id",
                cookieHeader: "sessionid=fake_session_id; csrftoken=c; ds_user_id=12345",
                csrfToken: "c", dsUserID: "12345", claim: "0", userAgent: "UA/1.0", device: device())
    }
```

- [ ] **Step 4: Write the failing test (device survives Keychain round-trip)**

Add to `SessionStoreTests`:

```swift
    @Test func roundTripsDeviceIdentity() async throws {
        let store = SessionStore(store: InMemorySecureStore())
        try await store.save(sample())
        let loaded = try #require(await store.current())
        #expect(loaded.device == sample().device)
        #expect(loaded.sessionid == "fake_session_id")
    }
```

- [ ] **Step 5: Run it to verify it passes (struct already supports it)**

Run: `swift test --filter roundTripsDeviceIdentity`
Expected: PASS. (`Session`/`DeviceIdentity` are `Codable`; `SessionStore` JSON-encodes the whole struct, so `device` persists with no store changes. This test pins that contract.)

- [ ] **Step 6: Checkpoint — full suite green**

Run: `swift build --build-tests && swift test`
Expected: build succeeds; all suites pass (web-era `IGWebClientTests` assertions still hold — `IGWebClient` is unchanged). Suggested commit message when asked: `refactor(igcore): add DeviceIdentity, expand Session (expand-contract step 1)`.

---

## Task 2: `IGWebClient.buildBearer(for:)`

**Files:**
- Modify: `Sources/IGCore/Networking/IGWebClient.swift`
- Test: `Tests/IGCoreTests/IGWebClientTests.swift`

A pure, statically-testable function — no wiring into requests yet. `static` + `internal` so the test calls it without constructing a client (mirrors the existing `checkStatus`).

- [ ] **Step 1: Write the failing test**

Add to `IGWebClientTests`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter buildBearerEncodesAuthData`
Expected: **build fails** — `type 'IGWebClient' has no member 'buildBearer'`.

- [ ] **Step 3: Implement `buildBearer`**

Add to `IGWebClient` (e.g. just above `checkStatus`):

```swift
    /// Builds `Authorization: Bearer IGT:2:<base64>` from the session (§7). The credential
    /// is base64 of `{ds_user_id, sessionid, should_use_header_over_cookies:true}`.
    /// `.sortedKeys` makes the bytes reproducible (C6); `dsUserID` is taken from the session,
    /// never re-derived from the sessionid (C13). No cookie, no signing (GET).
    static func buildBearer(for session: Session) -> String {
        struct AuthData: Encodable {
            let ds_user_id: String
            let sessionid: String
            let should_use_header_over_cookies: Bool
        }
        let payload = AuthData(ds_user_id: session.dsUserID, sessionid: session.sessionid,
                               should_use_header_over_cookies: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let json = try? encoder.encode(payload) else { return "" }
        return "Bearer IGT:2:\(json.base64EncodedString())"
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter buildBearerEncodesAuthData`
Expected: PASS.

- [ ] **Step 5: Checkpoint — full suite green**

Run: `swift test`
Expected: all pass. Suggested commit: `feat(igcore): add IGWebClient.buildBearer (Bearer IGT:2 construction)`.

---

## Task 3: Mobile transport — host, app id, Bearer, iOS header tiers

**Files:**
- Modify: `Sources/IGCore/Networking/IGWebClient.swift` (host, `appID`, `navChain`, `applyHeaders`; drop web headers)
- Modify: `Tests/IGCoreTests/IGWebClientTests.swift` (rewrite `inboxBuildsAuthedRequestAndDecodes`; add header-omit test)

The endpoint methods still use the **old simple params** (`["limit": ...]`) in this task — full param sets land in Tasks 5–6. This task is purely the request *fingerprint*: host `www`→`i`, app id → iOS, Bearer + Tier A/B/C headers from `session.device`, web headers removed. Claim-refresh logic is left exactly as-is (Task 8 adds MID capture).

- [ ] **Step 1: Rewrite the header-building in `IGWebClient`**

Change the `appID` constant and add `navChain`:

```swift
    private let appID = "567067343352427"
    private static let navChain =
        "9MV:self_profile:2,ProfileMediaTabFragment:self_profile:3,9Xf:self_following:4"
```

In `get(...)`, change the host and replace the block that set `X-IG-App-ID … Sec-Fetch-Site` (the manual `req.setValue` calls) with a single call `applyHeaders(to: &req, session)`. The host line becomes:

```swift
        guard var comps = URLComponents(string: "https://i.instagram.com") else { throw IGClientError.transport }
```

Add this method to `IGWebClient`:

```swift
    /// Applies the iOS private-API header set: Tier A (stable device identity), Tier B
    /// (per-request noise), Tier C (shared infra incl. Bearer). Tier D (IG-U-*) is omitted
    /// until IG issues it (§5.3). Reserved headers (Host/Connection/Accept-Encoding) are set
    /// for fidelity but URLSession may override them (C5) — tests never assert them.
    private func applyHeaders(to req: inout URLRequest, _ session: Session) {
        let d = session.device
        func set(_ v: String, _ h: String) { req.setValue(v, forHTTPHeaderField: h) }

        // Tier A — stable device identity
        set(d.deviceID, "X-IG-Device-ID")
        set(d.familyDeviceID, "X-IG-Family-Device-ID")
        if !d.mid.isEmpty { set(d.mid, "X-MID") }   // omit until bootstrapped (C10)
        set(d.bloksVersionID, "X-Bloks-Version-Id")
        set(appID, "X-IG-App-ID")
        set(d.capabilities, "X-IG-Capabilities")
        set(d.userAgent, "User-Agent")
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

        // Tier C — shared infra (Authorization + plumbing)
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
```

The top-of-file doc comment should now read `i.instagram.com`:

```swift
/// Pure transport: authed GETs to i.instagram.com/api/v1/direct_v2/*, returns raw DTOs.
/// No mapping (DomainMapper does that). Builds the iOS private-API header set (§5.3) +
/// Bearer auth (§7); refreshes X-IG-WWW-Claim from responses.
```

- [ ] **Step 2: Rewrite the failing test**

Replace `inboxBuildsAuthedRequestAndDecodes` in `IGWebClientTests` with:

```swift
    @Test func inboxBuildsMobileAuthedRequestAndDecodes() async throws {
        let body = try Fixture.data("inbox_real")
        MockURLProtocol.responder = { _ in (200, [:], body) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())

        let raw = try await client.inbox(limit: 20)

        #expect(!raw.inbox.threads.isEmpty)
        let req = try #require(MockURLProtocol.lastRequest)
        #expect(req.url?.host == "i.instagram.com")
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
        var s = session()
        s.device.mid = ""
        let client = IGWebClient(session: FakeSession(s), urlSession: MockURLProtocol.session())
        _ = try await client.inbox()
        #expect(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-MID") == nil)
    }
```

- [ ] **Step 3: Run to verify red→green**

Run: `swift test --filter "inboxBuildsMobileAuthedRequestAndDecodes|emptyDeviceMIDOmitsXMIDHeader"`
Expected: PASS after Step 1's implementation. (If you run the test before editing `IGWebClient`, it fails — old code sets `X-IG-App-ID=936619743392459` and a `Cookie`.)

- [ ] **Step 4: Checkpoint — full suite green**

Run: `swift test`
Expected: all pass. `refreshesClaimFromResponseHeader`, the error-mapping tests, and `threadBuildsRequestWithIDAndDecodes` (still `limit=40` until Task 6) remain green — note the thread URL host is now `i.instagram.com` but that test only checks the path/limit. Suggested commit: `feat(igcore): switch IGWebClient to i.instagram.com + Bearer + iOS header set`.

> ⚠️ **`Authorization` visibility in `MockURLProtocol`:** custom `Authorization` set via `URLRequest.setValue` is captured by the URLProtocol mock (the known stripping issue is redirect-only). If Step 3 shows `Authorization == nil` against expectation, that's the platform dropping it — fall back to asserting a header the mock definitely keeps (`X-IG-App-ID`) and note it; do not weaken the Bearer logic itself.

---

## Task 4: `oldest_cursor` in DTOs + synthetic mobile fixtures

**Files:**
- Modify: `Sources/IGCore/Mapper/RawInboxDTO.swift`
- Modify: `Sources/IGCore/Mapper/RawThreadDTO.swift`
- Create: `Tests/IGCoreTests/Fixtures/inbox_mobile.json`
- Create: `Tests/IGCoreTests/Fixtures/thread_mobile.json`
- Create: `Tests/IGCoreTests/RawDTOCursorTests.swift`

`oldest_cursor` is a JSON **string** (recon §3), decoded as optional (`inbox` omits it on a single page; `thread` includes it). Surfacing the cursor for pagination is done by **returning it inside the DTO** the client already returns — no return-type change, so `DomainMapper` is untouched (it ignores the new field).

- [ ] **Step 1: Create the scrubbed mobile fixtures**

`Tests/IGCoreTests/Fixtures/inbox_mobile.json`:

```json
{
  "inbox": {
    "threads": [
      {
        "thread_id": "fake_thread_1",
        "users": [{ "pk": 12345, "username": "alice_fake", "full_name": "Alice Fake" }],
        "read_state": 0,
        "is_pin": false,
        "last_activity_at": 1700000000000000
      }
    ],
    "oldest_cursor": "fake_inbox_cursor_abc"
  },
  "seq_id": 40065,
  "status": "ok"
}
```

`Tests/IGCoreTests/Fixtures/thread_mobile.json`:

```json
{
  "thread": {
    "thread_id": "fake_thread_1",
    "users": [{ "pk": 12345, "username": "alice_fake", "full_name": "Alice Fake" }],
    "items": [
      {
        "item_id": "fake_item_1",
        "user_id": 12345,
        "timestamp": 1700000000000000,
        "item_type": "text",
        "text": "hello from a fixture"
      }
    ],
    "oldest_cursor": "fake_thread_cursor_xyz"
  },
  "status": "ok"
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/IGCoreTests/RawDTOCursorTests.swift`:

```swift
import Foundation
import Testing
@testable import IGCore

@Suite struct RawDTOCursorTests {
    @Test func inboxDecodesOldestCursor() throws {
        let raw = try Fixture.decode(RawInboxResponse.self, "inbox_mobile")
        #expect(raw.inbox.oldestCursor == "fake_inbox_cursor_abc")
    }

    @Test func threadDecodesOldestCursor() throws {
        let raw = try Fixture.decode(RawThreadResponse.self, "thread_mobile")
        #expect(raw.thread.oldestCursor == "fake_thread_cursor_xyz")
    }

    @Test func inboxWithoutCursorDecodesNil() throws {
        let raw = try Fixture.decode(RawInboxResponse.self, "inbox_synthetic")
        #expect(raw.inbox.oldestCursor == nil)
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --filter RawDTOCursorTests`
Expected: **build fails** — `value of type 'RawInbox' has no member 'oldestCursor'`.

- [ ] **Step 4: Add `oldestCursor` to the DTOs**

In `RawInboxDTO.swift`, extend `RawInbox`:

```swift
struct RawInbox: Decodable {
    let threads: [RawThread]
    let oldestCursor: String?

    enum CodingKeys: String, CodingKey {
        case threads
        case oldestCursor = "oldest_cursor"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threads = container.decodeLossyArray(RawThread.self, forKey: .threads)
        oldestCursor = try container.decodeIfPresent(String.self, forKey: .oldestCursor)
    }
}
```

In `RawThreadDTO.swift`, extend `RawThreadDetail`:

```swift
struct RawThreadDetail: Decodable {
    let threadID: String?
    let users: [RawUser]
    let items: [RawItem]
    let oldestCursor: String?

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case users
        case items
        case oldestCursor = "oldest_cursor"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        users = container.decodeLossyArray(RawUser.self, forKey: .users)
        items = container.decodeLossyArray(RawItem.self, forKey: .items)
        oldestCursor = try container.decodeIfPresent(String.self, forKey: .oldestCursor)
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter RawDTOCursorTests`
Expected: all three PASS.

- [ ] **Step 6: Checkpoint — full suite green**

Run: `swift test`
Expected: all pass (additive optional field; existing fixtures decode unchanged). Suggested commit: `feat(igcore): decode oldest_cursor for inbox/thread pagination`.

---

## Task 5: Inbox full param set + cursor pagination

**Files:**
- Modify: `Sources/IGCore/Networking/IGWebClient.swift` (`inbox` signature + params)
- Test: `Tests/IGCoreTests/IGWebClientTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `IGWebClientTests`:

```swift
    @Test func inboxSendsFullInitialParamSet() async throws {
        let body = try Fixture.data("inbox_real")
        MockURLProtocol.responder = { _ in (200, [:], body) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())
        _ = try await client.inbox(limit: 20)
        let q = try #require(MockURLProtocol.lastRequest?.url?.query)
        #expect(q.contains("visual_message_return_type=unseen"))
        #expect(q.contains("thread_message_limit=10"))
        #expect(q.contains("fetch_reason=initial_snapshot"))
        #expect(q.contains("limit=20"))
        #expect(q.contains("igd_request_log_tracking_id="))
        #expect(!q.contains("cursor="))
    }

    @Test func inboxPaginationAddsCursorAndPageScroll() async throws {
        let body = try Fixture.data("inbox_real")
        MockURLProtocol.responder = { _ in (200, [:], body) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())
        _ = try await client.inbox(limit: 20, cursor: "CUR123")
        let q = try #require(MockURLProtocol.lastRequest?.url?.query)
        #expect(q.contains("cursor=CUR123"))
        #expect(q.contains("direction=older"))
        #expect(q.contains("fetch_reason=page_scroll"))
        #expect(!q.contains("fetch_reason=initial_snapshot"))
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter "inboxSendsFullInitialParamSet|inboxPaginationAddsCursorAndPageScroll"`
Expected: build fails (no `cursor:` parameter) or assertion fails (no full params yet).

- [ ] **Step 3: Implement the full inbox params**

Replace `inbox(limit:)` in `IGWebClient`:

```swift
    func inbox(limit: Int = 20, cursor: String? = nil) async throws -> RawInboxResponse {
        var q = [
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
            "igd_request_log_tracking_id": UUID().uuidString,
        ]
        if let cursor {
            q["cursor"] = cursor
            q["direction"] = "older"
            q["fetch_reason"] = "page_scroll"   // overrides initial_snapshot
        }
        return try await get("/api/v1/direct_v2/inbox/", query: q, as: RawInboxResponse.self)
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter "inboxSendsFullInitialParamSet|inboxPaginationAddsCursorAndPageScroll"`
Expected: PASS.

- [ ] **Step 5: Checkpoint — full suite green**

Run: `swift test`
Expected: all pass (`inboxBuildsMobileAuthedRequestAndDecodes` still passes — `limit=20` is still present among the params). Suggested commit: `feat(igcore): full inbox param set + cursor pagination`.

---

## Task 6: Thread full param set + cursor pagination

**Files:**
- Modify: `Sources/IGCore/Networking/IGWebClient.swift` (`thread` signature + params)
- Modify: `Tests/IGCoreTests/IGWebClientTests.swift` (update existing thread test; add param tests)

- [ ] **Step 1: Update the existing test + write new ones**

In `IGWebClientTests`, replace `threadBuildsRequestWithIDAndDecodes` and add two tests:

```swift
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
        let q = try #require(MockURLProtocol.lastRequest?.url?.query)
        #expect(q.contains("visual_message_return_type=unseen"))
        #expect(q.contains("direction=older"))
        #expect(q.contains("seq_id=40065"))
        #expect(q.contains("limit=20"))
        #expect(!q.contains("cursor="))
    }

    @Test func threadPaginationAddsCursor() async throws {
        let body = try Fixture.data("thread_real")
        MockURLProtocol.responder = { _ in (200, [:], body) }
        let client = IGWebClient(session: FakeSession(session()), urlSession: MockURLProtocol.session())
        _ = try await client.thread(id: "rt_real_1", cursor: "TC9")
        let q = try #require(MockURLProtocol.lastRequest?.url?.query)
        #expect(q.contains("cursor=TC9"))
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter "threadBuildsRequestWithIDAndDecodes|threadSendsFullParamSet|threadPaginationAddsCursor"`
Expected: build fails (no `cursor:` parameter) / assertion fails (`limit=40`, no full params).

- [ ] **Step 3: Implement the full thread params**

Replace `thread(id:limit:)` in `IGWebClient`:

```swift
    func thread(id: String, limit: Int = 20, cursor: String? = nil) async throws -> RawThreadResponse {
        var q = [
            "visual_message_return_type": "unseen",
            "direction": "older",
            "seq_id": "40065",
            "limit": String(limit),
        ]
        if let cursor { q["cursor"] = cursor }
        return try await get("/api/v1/direct_v2/threads/\(id)/", query: q, as: RawThreadResponse.self)
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter "threadBuildsRequestWithIDAndDecodes|threadSendsFullParamSet|threadPaginationAddsCursor"`
Expected: PASS.

- [ ] **Step 5: Checkpoint — full suite green**

Run: `swift test`
Expected: all pass. Suggested commit: `feat(igcore): full thread param set + cursor pagination (limit 40→20)`.

---

## Task 7: `updateMID` seam on `SessionProviding` / `SessionStore` / `FakeSession`

**Files:**
- Modify: `Sources/IGCore/Networking/SessionStore.swift` (protocol + actor)
- Modify: `Tests/IGCoreTests/IGWebClientTests.swift` (`FakeSession` conforms; add `onMID`)
- Test: `Tests/IGCoreTests/SessionStoreTests.swift`

The seam must exist (all conformers implement it) before Task 8 wires the call. Expanding the protocol forces both conformers to gain the method, so this task touches `SessionStore` and the test `FakeSession` together — that is what keeps the build green.

- [ ] **Step 1: Add `updateMID` to the protocol + `SessionStore`**

In `SessionStore.swift`, extend the protocol:

```swift
public protocol SessionProviding: Sendable {
    func current() async -> Session?
    func updateClaim(_ claim: String) async
    func updateMID(_ mid: String) async
}
```

Add to the `SessionStore` actor (next to `updateClaim`):

```swift
    public func updateMID(_ mid: String) {
        guard var session = current(), session.device.mid != mid else { return }
        session.device.mid = mid
        try? save(session)
    }
```

- [ ] **Step 2: Make `FakeSession` conform**

In `IGWebClientTests.swift`, replace `FakeSession` with the `onMID`-capable version:

```swift
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
```

- [ ] **Step 3: Write the failing test**

Add to `SessionStoreTests`:

```swift
    @Test func updateMIDMutatesDeviceMID() async throws {
        let store = SessionStore(store: InMemorySecureStore())
        try await store.save(sample())
        await store.updateMID("MID_NEW")
        #expect(await store.current()?.device.mid == "MID_NEW")
    }
```

- [ ] **Step 4: Run to verify red→green**

Run: `swift test --filter updateMIDMutatesDeviceMID`
Expected: PASS after Steps 1–2. (Before Step 1, the whole test target fails to build because `FakeSession` would not satisfy the expanded protocol — implement protocol + conformers together.)

- [ ] **Step 5: Checkpoint — full suite green**

Run: `swift test`
Expected: all pass. Suggested commit: `feat(igcore): add SessionProviding.updateMID seam`.

---

## Task 8: Capture `ig-set-x-mid` in `IGWebClient`

**Files:**
- Modify: `Sources/IGCore/Networking/IGWebClient.swift` (`get` captures the MID header)
- Test: `Tests/IGCoreTests/IGWebClientTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `IGWebClientTests` (reuses the existing `ClaimBox` as a generic string box):

```swift
    @Test func capturesMIDFromResponseHeader() async throws {
        let body = try Fixture.data("inbox_real")
        MockURLProtocol.responder = { _ in (200, ["ig-set-x-mid": "MID_FROM_SERVER"], body) }
        let captured = ClaimBox()
        let client = IGWebClient(session: FakeSession(session(), onMID: { captured.value = $0 }),
                                 urlSession: MockURLProtocol.session())
        _ = try await client.inbox()
        #expect(captured.value == "MID_FROM_SERVER")
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter capturesMIDFromResponseHeader`
Expected: FAIL — `captured.value` is `nil` (the client never calls `updateMID` yet).

- [ ] **Step 3: Capture the MID header in `get`**

In `get(...)`, directly after the existing claim-refresh block (`if let newClaim { await self.session.updateClaim(newClaim) }`) and **before** `try Self.checkStatus(...)`, add:

```swift
        // MID bootstrap (§7): the one "set" header that can arrive on a read. Case-insensitive.
        let newMID = http.allHeaderFields.first {
            ($0.key as? String)?.caseInsensitiveCompare("ig-set-x-mid") == .orderedSame
        }?.value as? String
        if let newMID, !newMID.isEmpty {
            await self.session.updateMID(newMID)
        }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter capturesMIDFromResponseHeader`
Expected: PASS.

- [ ] **Step 5: Checkpoint — full suite green**

Run: `swift test`
Expected: all pass. Suggested commit: `feat(igcore): bootstrap X-MID from ig-set-x-mid response header`.

---

## Task 9: Contract `Session` (drop web-era fields) + rewrite `LiveSmokeTests`

**Files:**
- Modify: `Sources/IGCore/Networking/Session.swift` (remove `cookieHeader`, `userAgent`)
- Modify: `Tests/IGCoreTests/IGWebClientTests.swift` (`session()` to final shape)
- Modify: `Tests/IGCoreTests/SessionStoreTests.swift` (`sample()` to final shape)
- Modify: `Tests/IGCoreTests/LiveSmokeTests.swift` (rewrite as live through-the-client smoke)

Contract phase: nothing reads `cookieHeader`/`userAgent` on the read path anymore (the client uses `device.userAgent` + Bearer). Remove them. `csrfToken` stays for the deferred write path.

- [ ] **Step 1: Final `Session` shape**

Replace `Sources/IGCore/Networking/Session.swift`:

```swift
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
```

- [ ] **Step 2: Update the two factories to the final shape**

`IGWebClientTests.session()`:

```swift
    private func session() -> Session {
        Session(sessionid: "fake_session_id", dsUserID: "12345", claim: "0",
                device: device(), csrfToken: "c")
    }
```

`SessionStoreTests.sample()`:

```swift
    private func sample() -> Session {
        Session(sessionid: "fake_session_id", dsUserID: "12345", claim: "0",
                device: device(), csrfToken: "c")
    }
```

- [ ] **Step 3: Rewrite `LiveSmokeTests` as a through-the-client live smoke**

Replace the entire `Tests/IGCoreTests/LiveSmokeTests.swift`:

```swift
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
```

- [ ] **Step 4: Run to verify build + green**

Run: `swift build --build-tests && swift test`
Expected: build succeeds (no remaining references to `cookieHeader`/`userAgent`); all suites pass; `LiveSmokeTests` and `LiveTransportProbeV2` both skip (no env).

- [ ] **Step 5: Checkpoint — full suite green + grep for dead fields**

Run: `swift test && grep -rn "cookieHeader\|\.userAgent" Sources Tests --include="*.swift"`
Expected: tests pass; grep returns nothing (or only `device.userAgent` usages). Suggested commit: `refactor(igcore): drop web-era Session fields; live smoke via mobile client (expand-contract step 2)`.

---

## Confidence basis (rung-2, decided 2026-05-25)

This build proceeds on **rung-2 evidence**: instagrapi's actively-maintained, REST-only `direct.py` (35 `private_request`, 0 GraphQL) + our own validated live `200`s on `i.instagram.com` (`LiveTransportProbeV2`, 2026-05-24). **Rung-3** (a decrypted capture of the genuine app proving it calls these exact REST paths) was attempted via Proxyman on 2026-05-25 but **blocked by Instagram's TLS certificate pinning** — the capture produced only encrypted `CONNECT i.instagram.com:443` tunnels. Reaching rung-3 requires a pinning bypass (jailbroken iOS + SSL Kill Switch, or Android + Frida/objection) and is **deferred** as an optional hardening pass. The iOS device profile and synthetic mobile fixtures (C4) stand unchanged.

## Post-Plan Manual Verification (not a code task)

After Task 9, optionally re-run the live path **through the production client** against the secondary account to confirm the refactored `IGWebClient` (not just the standalone probe) works end-to-end:

```bash
IG_SESSIONID='<raw sessionid>' \
IG_IOS_UA='Instagram 309.0.0.40.113 (iPhone15,3; iOS 17_5_1; en_US; en-US; scale=3.00; 1179x2556; 0) AppleWebKit/605.1.15' \
  swift test --filter LiveSmokeTests
```

Expect `✅ inbox: N raw threads → M mapped conversations` and `✅ thread: …`. **Rotate the sessionid afterward.** A real scrubbed mobile capture (replacing the synthetic `*_mobile.json` fixtures) is a separate manual step if desired.

---

## Self-Review

**Spec coverage (V2 §5.1–§5.4, §7):**
- §5.1 Session shape (sessionid/dsUserID/claim/device/csrfToken; cookieHeader removed) → T1 (expand) + T9 (contract) ✅
- §5.2 DeviceIdentity (7 fields, Keychain round-trip) → T1 ✅
- §5.3 Header tiers A/B/C, Tier D omitted, web headers removed, Android header dropped → T3 ✅
- §5.4 Inbox params + pagination → T5; Thread params + pagination (limit 40→20) → T6; `oldest_cursor` round-trip in DTOs → T4 ✅
- §7 Bearer construction (deterministic, dsUserID trusted) → T2; MID bootstrap (seam + capture) → T7+T8; claim handling → retained as-is in T3; session-death mapping → unchanged ✅
- Security: scrubbed fixtures (`fake_session_id`/`12345`), MockURLProtocol-only, no live in CI → all tasks ✅

**Placeholder scan:** none — every code step shows complete code; every fixture is full JSON.

**Type consistency:** `DeviceIdentity` field names (`deviceID`/`familyDeviceID`/`mid`/`bloksVersionID`/`appVersion`/`capabilities`/`userAgent`) are identical across T1, T3, T9, and `LiveSmokeTests`. `Session.init` label order is consistent within each phase (expand init in T1; final init in T9). `inbox(limit:cursor:)` / `thread(id:limit:cursor:)` signatures match between implementation (T5/T6) and call sites (T8 tests, T9 LiveSmoke). `oldestCursor` (camelCase property ↔ `oldest_cursor` JSON) consistent across T4 DTOs, fixtures, and tests. `updateMID` consistent across protocol/actor/FakeSession (T7) and the capture call (T8).

**Known platform caveat carried into the plan:** `Authorization` visibility under `MockURLProtocol` (Task 3 note) and reserved-header non-assertion (C5) — both handled.
