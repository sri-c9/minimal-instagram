---
title: Auth-Minting — Design Spec
date: 2026-06-28
status: approved — input to the auth-minting implementation plan
related: "[[Technical Design (V2)]] §5.1–§5.2, §7; [[Mobile API Transport — Recon Findings (2026-05-23)]] §4"
---

# Auth-Minting — Design Spec

**Goal.** Obtain an authenticated `Session` *in the app* instead of injecting one through tests/env. The user logs in through Instagram's real web form in a `WKWebView`; we extract the resulting cookies, mint a `Session` (with a stable `DeviceIdentity`), and persist it in the Keychain. After this increment the app shows a signed-in vs. signed-out state and can hand a real `Session` to the existing read path.

**Architecture.** Same anti-corruption discipline as the read path: the correctness-critical, testable logic lives in **IGCore** (pure, host-testable on macOS); the genuinely-untestable UIKit/WebView surface is a **thin App shell**. IGCore must stay UIKit-free (its tests run on the `.macOS(.v13)` host floor).

**Reference:** instagrapi `login_by_sessionid` (web session → mobile Bearer); recon §4 (device-profile recipe); the live-validated `LiveTransportProbeV2`.

---

## 1. Scope

**In scope**
- Mint `DeviceIdentity` once from real device values; persist independently of `Session`; never regenerate.
- `WKWebView` login against IG's web form; capture cookies when the `sessionid` cookie appears.
- Mint `Session` from the captured cookies (sessionid kept **raw**) + the `DeviceIdentity`; persist via `SessionStore`.
- App auth state: signed-out → login WebView; signed-in → minimal confirmation + logout. Logout clears `Session`, keeps `DeviceIdentity`.

**Out of scope (later increments)**
- Wiring the persisted session through `IGWebClient` to render the inbox/thread (own design). A `.needsLogin → signedOut` hook is *designed in* but reads are not wired here.
- Send/write path (POST + `signed_body` + CSRF).
- Confirming the true-iOS `X-IG-Capabilities` value (carried open question; `3brTv10=` is live-validated).

---

## 2. Components

### 2.1 IGCore (pure, unit-tested)

**`DeviceProfile`** — value type of raw device inputs (no UIKit):
```
struct DeviceProfile {
    var model: String          // "iPhone15,3"  (sysctl hw.machine)
    var systemVersion: String  // "17.5.1"      (UIDevice.systemVersion)
    var scale: Double          // 3.0           (UIScreen.scale)
    var screenWidth: Int       // 1179          (UIScreen.nativeBounds px)
    var screenHeight: Int      // 2556
    var locale: String         // "en_US"
    var language: String       // "en-US"
}
```

**`UserAgentRenderer.render(appVersion:profile:)`** — pure; produces the exact iOS UA:
```
Instagram <appVersion> (<model>; iOS <systemVersion '.'→'_'>; <locale>; <language>; scale=<scale 2dp>; <W>x<H>; 0) AppleWebKit/605.1.15
```
e.g. `Instagram 309.0.0.40.113 (iPhone15,3; iOS 17_5_1; en_US; en-US; scale=3.00; 1179x2556; 0) AppleWebKit/605.1.15`.

**`DeviceIdentityFactory.mint(profile:deviceID:familyDeviceID:)`** — assembles `DeviceIdentity`:
- `userAgent` ← `UserAgentRenderer.render`
- `deviceID`, `familyDeviceID` ← injected UUID strings (caller generates once → deterministic tests)
- pinned constants (static, single source of truth): `appVersion="309.0.0.40.113"`, `bloksVersionID=<64 zeros>` (live-validated default), `capabilities="3brTv10="`
- `mid=""` (bootstrapped later from `ig-set-x-mid` on the read path — already implemented)

**`SessionMinter.makeSession(cookies:device:)`** — pure mapping `cookies: [String: String]` → `Session`:
- `sessionid` ← `cookies["sessionid"]` **verbatim, kept raw / URL-encoded** (the rule that caused today's 403 — never decode `%3A`)
- `dsUserID` ← `cookies["ds_user_id"]` (trusted from cookie; not re-derived)
- `csrfToken` ← `cookies["csrftoken"] ?? ""`; `claim="0"`; `device` embedded
- throws `IGClientError.needsLogin` if `sessionid` or `ds_user_id` is absent/empty

### 2.2 IGCore persistence — `DeviceStore` (the one extension to TD V2)

`DeviceIdentity` must exist **before** the first login and **survive logout**, but today it is only persisted *inside* `Session`. This increment adds a small actor parallel to `SessionStore`, over the same `SecureStore` seam:
```
actor DeviceStore {
    init(store: SecureStore = KeychainStore())   // key: "ig.device"
    func loadOrMint(_ mint: () -> DeviceIdentity) -> DeviceIdentity   // mint+persist once; reuse thereafter
    func current() -> DeviceIdentity?
}
```
Mint-once / never-regenerate is enforced here: `loadOrMint` persists on first call and returns the stored identity on every subsequent call. Logout (`SessionStore.clear()`) does **not** touch `DeviceStore`.

### 2.3 App (thin shell, manually verified)

- **`DeviceProfileReader`** — reads real values (`sysctl hw.machine`, `UIDevice.current.systemVersion`, `UIScreen.main.scale`, `UIScreen.main.nativeBounds`, `Locale.current`) → `DeviceProfile`.
- **`LoginWebView`** (`UIViewRepresentable`) — `WKWebView` loading `https://www.instagram.com/accounts/login/` on a **`.nonPersistent()`** `WKWebsiteDataStore` (so the only durable copy of `sessionid` is our Keychain). A `WKHTTPCookieStoreObserver` fires on cookie change; when a `sessionid` cookie for `instagram.com` is present, it reads all IG cookies into `[String: String]` (**values verbatim — must round-trip to a 200; verify on device that the captured `sessionid` retains its `%3A` form**) and calls back.
- **`AuthState`** (`@Observable`) — coordinator (§3).
- **`RootView`** — switches on `AuthState`: `signedOut → LoginWebView`, `signedIn → SignedInView` ("Signed in as <dsUserID>" + Logout), `error → message + retry`.

---

## 3. Data flow & auth state machine

```
launch
  → DeviceProfileReader.read()
  → DeviceIdentityFactory.mint(profile:, newUUIDs)
  → DeviceStore.loadOrMint{ … }              // device ready before login
  → SessionStore.current()
       some → state = .signedIn(dsUserID)
       none → state = .signedOut
signedOut → LoginWebView
  → cookie store: sessionid appears
  → SessionMinter.makeSession(cookies, device)
  → SessionStore.save(session)
  → state = .signedIn(dsUserID)
signedIn → SignedInView; Logout → SessionStore.clear() (device kept) → .signedOut
(future) read throws .needsLogin → .signedOut     // hook only; reads not wired this increment
```

States: `.loading` (brief, at launch) · `.signedOut` · `.signedIn(dsUserID)` · `.error(String)`.

---

## 4. Error handling

- **Cookies change, no `sessionid` yet** → keep waiting; this is normal mid-login / 2FA / checkpoint (resolved inside IG's web form). Not an error.
- **`SessionMinter` missing required cookies** (only when invoked) → `.needsLogin`; UI returns to the WebView calmly.
- **Keychain write / mint failure** → `.error(message)` + retry; never crash.
- **WebView load failure (offline)** → in-WebView error + retry; `AuthState` stays `.signedOut`.
- **Session death (future reads)** → `.signedOut`.

---

## 5. Testing

**IGCore (TDD, macOS host, `MockURLProtocol`/no network):**
- `UserAgentRenderer`: exact-string for a known `DeviceProfile` + appVersion (dots→underscores, `scale=3.00`, `WxH`); a second profile to guard formatting.
- `SessionMinter`: a cookie dict with a **raw `%3A`-laden `sessionid`** → `Session.sessionid` preserved byte-for-byte (regression test for today's bug); `dsUserID` from cookie; `csrfToken` mapped; `claim=="0"`; missing `sessionid`/`ds_user_id` → throws `.needsLogin`.
- `DeviceStore`: `loadOrMint` mints+persists once; a second `loadOrMint`/`current` returns the **same** identity (never regenerates); identity survives a `SessionStore.clear()`.

**App (manual, on device):** `LoginWebView` real login (incl. a 2FA/checkpoint account), cookie capture, persistence, relaunch-stays-signed-in, logout-returns-to-login, and the **captured-session-round-trips-to-200** check (reuses `LiveSmokeTests`/probe expectations). No unit tests for `WKWebView`/`DeviceProfileReader` (device-bound APIs).

---

## 6. Security

- `sessionid` is password-grade: **Keychain only** (`SessionStore`/`KeychainStore`), never logged, never committed; kept **raw**.
- WebView uses a **non-persistent** data store → no durable `sessionid` copy in WebKit storage.
- 2FA/checkpoint handled entirely by IG's web form; we never see or store the password.
- `DeviceIdentity` persisted in Keychain (`DeviceStore`); not secret, but co-located and stable.
- No test hits live Instagram; fixtures stay scrubbed.

---

## 7. Proposed file structure (refined in the plan)

**IGCore — create:** `Auth/DeviceProfile.swift`, `Auth/UserAgentRenderer.swift`, `Auth/DeviceIdentityFactory.swift`, `Auth/SessionMinter.swift`, `Networking/DeviceStore.swift`.
**IGCore tests — create:** `UserAgentRendererTests.swift`, `SessionMinterTests.swift`, `DeviceStoreTests.swift`.
**App — create:** `Auth/AuthState.swift`, `Auth/LoginWebView.swift`, `Auth/DeviceProfileReader.swift`, `SignedInView.swift`; **modify** `RootView.swift`.

**Out of scope / unchanged:** `IGWebClient`, DTOs, `DomainMapper`, domain models, the read-path tests.
