---
title: Minimal Instagram — Technical Design (V2)
date: 2026-05-23
status: draft — pending review
supersedes: "Technical Design (V1) §1 (key decisions), §2 (spike), §3 (constraints/risks), §5 (components), §7 (auth/session lifecycle)"
based_on: "[[Mobile API Transport — Recon Findings (2026-05-23)]], [[Technical Design (V1)]]"
related: "[[High-Level Product Design (V2)]]"
---

# Minimal Instagram — Technical Design (V2)

> **What changed in one line.** Reads do not work against `www.instagram.com`
> from `URLSession` (that host serves the HTML SPA shell to any non-browser
> client). They *do* work against the mobile private host **`i.instagram.com`** —
> same `/api/v1/direct_v2/` paths and same DTOs, but a different **host**,
> **auth shape** (`Cookie` → `Authorization: Bearer IGT:2:`), and **device
> profile** (web → iOS app). The change is contained to `IGWebClient` + `Session`.

> **Relationship to V1.** This doc **supersedes V1 §1, §2, §3, §5, §7**. The
> remaining V1 sections stay in force: **§0** scope, **§4** architecture/data
> flow (with the host string updated `www`→`i`), **§6** firewall enforcement,
> **§8** testing strategy, **§9** open questions. Where a carried-over section
> needs a small consequential edit, it is called out inline below.

---

## 0′. Increment scope (this refactor)

V1 §0 still defines the product scope. This refactor narrows what we *build now*:

- **In:** read path only — `inbox` (with pagination) and `thread` (with
  pagination), against `i.instagram.com`, authed by Bearer.
- **Deferred:** **send/write** (POST + `signed_body=SIGNATURE.<json>` + CSRF; its
  own increment — recon D7) and **auth minting** (the WebView login that mints
  `Session` + `DeviceIdentity`). For this increment **`Session` is treated as
  given** — populated by tests and fakes, never minted in code yet.
- **Unchanged:** `DomainMapper`, all domain models, the firewall, and the UI.
  The anti-corruption boundary holds.

---

## 1. Key decisions & rationale  *(supersedes V1 §1)*

| Decision | V2 choice | Why |
|---|---|---|
| Data access | **On-device, mobile private API** (`i.instagram.com/api/v1/direct_v2/`) | Only host that returns JSON to a plain `URLSession`; `www` gates on TLS/HTTP2 fingerprint and serves the HTML shell |
| Host | **`i.instagram.com`** | No web page to serve → JSON to a plain client |
| `X-IG-App-ID` | **`567067343352427`** (the iOS app id) | Confirmed HTTP 200 on the mobile host (web id `936619743392459` is for `www`) |
| Auth on requests | **`Authorization: Bearer IGT:2:<b64>`**, no `Cookie` header | Mobile host authenticates by header; cookie-on-`www` gets the shell |
| Login | **WebView web login → cookies → `login_by_sessionid`** converts the web `sessionid` to a mobile Bearer | IG's real web form handles password/2FA/checkpoint; we never reimplement them, and we reuse the web session cross-surface (no separate mobile login) |
| Device profile | **iOS, values read from the real device** (`UIDevice`/`UIScreen`/`sysctl hw.machine`) | Most coherent fingerprint; nothing fabricated |
| Delivery | **Fetch-on-open** (pull-to-refresh; no MQTT, no polling) | Calmest product, lowest detection, least RE — all the same path |
| Reference | **instagrapi** (REST + device emulation); ignore its realtime/MQTT | Battle-tested; we are a fetch-style client like it |
| Send (write) | **Deferred** (separate increment) | Different shape (POST + `signed_body` + CSRF); read path stands alone |

**V1's rejection of "B1 — native mobile private API" no longer holds.** Both
stated reasons were falsified by recon:

- *"requires reimplementing request-signing"* — `generate_signature` is now a
  constant `signed_body=SIGNATURE.<json>` prefix (the real HMAC was dropped years
  ago) and is applied **only to POSTs**. The read path is GET-only → **no signing
  at all**.
- *"requires reimplementing login/2FA/checkpoint"* — `login_by_sessionid` proves
  a web `sessionid` is convertible to a mobile Bearer with **no mobile login**.
  2FA/checkpoint stay in the WebView, exactly as V1 wanted.

---

## 2. Recon evidence  *(supersedes V1 §2 spike)*

Two live probes against the author's **secondary** account (web session → mobile
host), full detail in [[Mobile API Transport — Recon Findings (2026-05-23)]]:

- **Probe 1** (Android UA): `GET i.instagram.com/api/v1/direct_v2/inbox/` →
  **HTTP 200** JSON.
- **Probe 2** (iOS UA, `X-IG-App-ID: 567067343352427`,
  `X-IG-Capabilities: 3brTv10=`) → **HTTP 200**; top-level keys
  `[inbox, viewer, seq_id, snapshot_at_ms, …, status]`; `inbox` keys
  `[threads, pinned_threads, unseen_count, prev_cursor, has_older, oldest_cursor,
  next_cursor, …]`.

Findings that shape this design:

- **DTO compatibility.** `inbox.threads` is exactly where `RawInboxResponse`
  expects it; extra mobile keys (`seq_id`, `viewer`, …) are ignored by
  `Decodable`. Existing DTOs should decode mobile responses **unchanged** — to be
  verified against a scrubbed mobile fixture in Task B.
- **No refresh headers on reads.** The inbox read returned **no**
  `ig-set-authorization` / `x-ig-set-www-claim` / `ig-u-*` headers — those are
  issued at *login*, not on reads. The Bearer does **not** rotate mid-session;
  V1's self-refreshing-claim logic is inert-but-harmless for reads. Keep it
  defensively; confirm live during dev. (One caveat: `ig-set-x-mid` *can* appear
  on the first call — see §7 MID bootstrap.)
- **`oldest_cursor` is a JSON string**; `prev/next_cursor` are objects. Pagination
  pages on `oldest_cursor`.

---

## 3. Constraints & risks  *(supersedes V1 §3)*

- **Account ban risk (respect this).** Unchanged from V1, with one added lever
  from recon: **device identity is sacred.** Generate the `DeviceIdentity` once,
  Keychain-persist it, load it *before* login, and **never regenerate** it —
  regeneration reads as "new device" and invites re-login/flagging. Recon is run
  against a **secondary account** to age the identity and absorb risk; serialize
  requests (one in-flight per session — the `SessionStore` actor already does
  this); pin one IP per account (the phone).
- **ToS.** Unchanged: unofficial use of IG's private interface for the author's
  own data, accepted knowingly for a single-user tool.
- **iOS install.** Unchanged: free 7-day re-sign or paid Developer account.
- **Breakage / GraphQL framing (revised).** V1 worried the legacy *web* REST
  surface would be retired in favor of the web UI's GraphQL. V2 **moves off the
  web surface entirely** onto the **app's own private API** — the surface IG's
  real iOS client uses — which is *more* durable than web REST, not less. Churn
  is still fully contained: any future shape change lands in `IGWebClient` (new
  transport/headers) + the `Raw*DTO` layer (new shapes); domain models, mapper,
  and UI are untouched.
- **Web-session longevity on the mobile host (open).** Does a web `sessionid`
  survive long-term when used as a mobile Bearer? Empirical — measure on the
  secondary account. Upgrade path if it checkpoints too often: native-session
  bootstrap via `ig_sso_users` (Auth-C). Non-blocking for this increment.

---

## 5. Components  *(supersedes V1 §5)*

Dependency direction is unchanged and one-way:
UI → Repository → {IGWebClient, DomainMapper}; `DomainMapper` stays pure.

| Component | V2 change |
|---|---|
| **Session** | Add `sessionid` (for the Bearer) + a persisted **`DeviceIdentity`** sub-struct. Web-era `cookieHeader` is no longer sent on API calls; `csrfToken` is retained only for the deferred POST path. (See §5.1.) |
| **DeviceIdentity** *(new)* | Stable per-install fingerprint: `deviceID`, `familyDeviceID`, `mid`, `bloksVersionID`, `appVersion`, `capabilities`, `userAgent`. Minted once, Keychain-persisted, loaded before login, never regenerated. (See §5.2.) |
| **IGWebClient** | Host `www`→`i`; app id → `567067343352427`; drop `Cookie`/`X-CSRFToken`; **add `Authorization: Bearer IGT:2:`**; instagrapi-derived iOS header set, Android-only headers dropped (§5.3); full inbox/thread param sets (§5.4) with optional `cursor:` pagination that **surfaces the next cursor** (§5.4); remove the dead Sec-Fetch/AJAX/Origin/Referer experimental headers; capture `ig-set-x-mid` on every response (§7). |
| **Raw DTOs** | Add `oldest_cursor` decoding to `RawInboxResponse` / `RawThreadResponse` so pagination can read the next cursor (§5.4). Other DTO shapes unchanged. |
| **SessionStore / SessionProviding** | Add an `updateMID(_:)` seam (parallel to `updateClaim`) that writes the captured `mid` into `Session.device.mid` and re-persists. Test `FakeSession` implements it too. (§7) |
| **AuthCoordinator** *(deferred increment)* | WebView web login mints `Session`; also mints/loads `DeviceIdentity` *before* login. Out of scope for this refactor. |
| **Repository / MediaFetcher / DomainMapper / domain models / UI** | **No change.** |

Domain models unchanged: `Conversation`, `Message`, `SharedReel`, `ThreadDetail`,
`Session` (+ its new `DeviceIdentity`).

### 5.1 `Session` shape (V2)

```
struct Session {
    var sessionid: String        // password-grade; the Bearer is built from this
    var dsUserID: String         // ds_user_id (leading digits of sessionid); IG-INTENDED-USER-ID
    var claim: String = "0"      // X-IG-WWW-Claim; self-refreshes from x-ig-set-www-claim
    var device: DeviceIdentity   // stable fingerprint, incl. rendered userAgent (§5.2)
    // retained for the deferred write path only, NOT sent on reads:
    var csrfToken: String
    // REMOVED from the read path: cookieHeader (Bearer replaces it)
}
```

The rendered iOS `User-Agent` lives in `DeviceIdentity` (§5.2), not on `Session`:
it encodes `appVersion` + real-device values and is equally device-stable, so it
belongs with the rest of the fingerprint and is minted/persisted on the same
lifecycle.

### 5.2 `DeviceIdentity` (new, Keychain-persisted, minted once)

| Field | Type / format | Header it feeds | Source |
|---|---|---|---|
| `deviceID` | UUID | `X-IG-Device-ID` | generated once |
| `familyDeviceID` | UUID | `X-IG-Family-Device-ID` | generated once |
| `mid` | String | `X-MID` | **bootstrapped** from the first `ig-set-x-mid` response header (§7) |
| `bloksVersionID` | String | `X-Bloks-Version-Id` | pinned at build time |
| `appVersion` | String | (renders into `userAgent`) | pinned at build time |
| `capabilities` | String (`3brTv10=`) | `X-IG-Capabilities` | pinned |
| `userAgent` | String | `User-Agent` | rendered once from `appVersion` + real-device values (`sysctl hw.machine`, `UIDevice`, `UIScreen`, `Locale`) |

Lifecycle: **mint once → Keychain → load before login → never regenerate.**
Regeneration = "new device" = re-login/flag.

> **Dropped: `androidDeviceID` / `X-IG-Android-ID`.** This was in the task spec but
> *not* in recon §4's stable-identity list. It is genuinely Android-only — the real
> iOS app does not send it — so pairing it with an iOS `User-Agent` is an incoherent
> fingerprint. Dropping it reconciles V2 with the recon and yields a cleaner iOS
> profile. (`X-IG-Capabilities` is retained: both platforms send it, and `3brTv10=`
> empirically returned 200 with an iOS UA in Probe 2 — see §5.3 and open questions.)

### 5.3 Header set (instagrapi-derived, four tiers)

`IGWebClient` builds every request from these tiers. Tier discipline is the point
— each header belongs to exactly one tier and is sourced accordingly.

**Tier A — Stable device identity** (same on every request, from `DeviceIdentity`):

| Header | Value / source |
|---|---|
| `X-IG-Device-ID` | `device.deviceID` |
| `X-IG-Family-Device-ID` | `device.familyDeviceID` |
| `X-MID` | `device.mid` |
| `X-Bloks-Version-Id` | `device.bloksVersionID` |
| `X-IG-App-ID` | `567067343352427` |
| `X-IG-Capabilities` | `3brTv10=` (Android-origin but returned 200 with iOS UA in Probe 2; true-iOS value is an open question) |
| `User-Agent` | `device.userAgent` |
| `X-IG-App-Startup-Country` | `US` |
| `X-IG-Timezone-Offset` | device timezone offset in **seconds, signed** (US is negative, e.g. `-25200`) |
| `X-IG-Connection-Type` | `WIFI` |
| `X-Bloks-Is-Layout-RTL` | `false` |
| `X-Bloks-Is-Panorama-Enabled` | `true` |
| `X-IG-App-Locale` | `en_US` |
| `X-IG-Device-Locale` | `en_US` |
| `X-IG-Mapped-Locale` | `en_US` |
| `IG-INTENDED-USER-ID` | `session.dsUserID` |
| `X-IG-Nav-Chain` | a plausible nav-chain string (instagrapi ships a constant) |

**Tier B — Per-request noise** (randomized each call, like the real app):

| Header | Value |
|---|---|
| `X-Pigeon-Session-Id` | `UFS-<uuid>-1` |
| `X-Pigeon-Rawclienttime` | current epoch, 3 decimals |
| `X-IG-Bandwidth-Speed-KBPS` | random 2500.0–3000.0 (instagrapi: `randint(2_500_000…3_000_000)/1000`) |
| `X-IG-Bandwidth-TotalBytes-B` | random 5_000_000–90_000_000 |
| `X-IG-Bandwidth-TotalTime-MS` | random 2000–9000 |
| `X-IG-SALT-IDS` | random 1_061_162_222–1_061_262_222 |

**Tier C — Shared infra** (constant transport plumbing):

| Header | Value |
|---|---|
| `Authorization` | `Bearer IGT:2:<b64>` (see §7) |
| `Priority` | `u=3` |
| `Accept-Language` | `en-US` (instagrapi dedups; no `, en` for an `en_US` locale) |
| `Accept-Encoding` | `gzip, deflate` |
| `Host` | `i.instagram.com` |
| `X-FB-HTTP-Engine` | `Tigon/MNS/TCP` |
| `X-Tigon-Is-Retry` | `False` |
| `Connection` | `keep-alive` |
| `X-FB-Client-IP` | `True` |
| `X-FB-Server-Cluster` | `True` |
| `X-IG-WWW-Claim` | `session.claim` (`0` until IG sets it) |
| `X-Zero-Balance` | `INIT` |
| `X-Zero-State` | `unknown` |
| `Zero-HTTP-Network-Interface` | `wifi` |

**Tier D — Server-issued** (do **NOT** fabricate): `IG-U-RUR`, `IG-U-SHBID`,
`IG-U-SHBTS`. instagrapi hardcodes fake HMAC suffixes here; we **omit** them and
let IG issue them, then store + replay on subsequent requests. Omitting is *more*
coherent than the reference — fabricated values contradict what IG actually knows.

**Removed (web-era dead weight):** `Cookie`, `X-CSRFToken`, `X-Requested-With`,
`X-Instagram-AJAX`, `Origin`, `Referer`, `Sec-Fetch-Dest/Mode/Site`, `Accept: */*`.

**Removed (Android-only, for iOS coherence — C7):** `X-IG-Android-ID` (and its
`androidDeviceID` field). The real iOS app does not send it.

### 5.4 Endpoint parameters (full sets, from instagrapi `direct.py`)

**Inbox** — `GET /api/v1/direct_v2/inbox/`, initial fetch:

```
visual_message_return_type=unseen   thread_message_limit=10   persistentBadging=true
limit=20                            is_prefetching=false      fetch_reason=initial_snapshot
include_old_mrs=false               no_pending_badge=true     push_disabled=false
eb_device_id=0                      igd_request_log_tracking_id=<uuid>
```

Pagination (page older) **adds**: `cursor=<oldest_cursor>`, `direction=older`,
`fetch_reason=page_scroll` (overriding `initial_snapshot`).

**Thread** — `GET /api/v1/direct_v2/threads/{id}/`:

```
visual_message_return_type=unseen   direction=older   seq_id=40065   limit=20
```

Pagination (page older) **adds**: `cursor=<cursor>`.

> Note vs. V1: thread `limit` moves from `40` → **`20`** (instagrapi default);
> the V1 test asserting `limit=40` will be updated in Task B.

**Pagination is a round-trip (C2).** Sending `cursor` is only half of it — to fetch
the *next* page the client must read the next cursor back out of the response.
`inbox` pages on `inbox.oldest_cursor` (a JSON **string**, per recon §3); `thread`
pages on `thread.oldest_cursor`. Task B therefore:
- adds `oldest_cursor` to `RawInboxResponse` / `RawThreadResponse` (decoded as an
  optional `String`), and
- surfaces it from `inbox(cursor:)` / `thread(id:cursor:)` (e.g. return the raw DTO
  which now carries the cursor, or a `(dto, nextCursor)` pair — chosen in the plan).
A `nil`/absent `oldest_cursor` is the calm completion signal ("all caught up").

---

## 7. Auth & session lifecycle  *(supersedes V1 §7)*

**Bearer construction.** No `Cookie` header. Build the credential blob and base64
it (instagrapi `authorization` property):

```
authorization_data = {
    "ds_user_id": "<session.dsUserID>",
    "sessionid":  "<session.sessionid>",
    "should_use_header_over_cookies": true
}
Authorization: Bearer IGT:2:<base64(json(authorization_data))>
```

`should_use_header_over_cookies` is what authorizes the header path and lets us
drop the cookie jar.

**Trust `session.dsUserID`, don't re-derive it (C13).** `ds_user_id` *is* the
leading digits of `sessionid` — but that derivation belongs to the deferred
auth-mint step. The read client takes `dsUserID` straight from `Session`. This is
why scrubbed fixtures can pair an unrelated `sessionid=fake_session_id` with
`ds_user_id=12345` safely: nothing on the read path re-parses the sessionid.

**Deterministic Bearer encoding (C6).** `base64(json(...))` is only assertable in
tests if the JSON is byte-stable. `JSONEncoder` does not guarantee key order, so
the client must either use `.outputFormatting = .sortedKeys` or build the JSON
string by hand. Pin one approach so the Bearer is reproducible (tests decode the
base64 and compare the dict, or compare the exact string under a fixed ordering).

**Device-identity lifecycle.** Mint `DeviceIdentity` **once**, persist in Keychain,
**load before login**, **never regenerate**. It is part of the credential surface:
losing/changing it looks like a new device.

**MID bootstrap.** `X-MID` starts empty/unknown. On **every** response, capture
`ig-set-x-mid` (case-insensitive) → write into `Session.device.mid` → persist →
send on subsequent requests. (This is the one "set" header that *can* arrive on a
read, per recon.) Because `mid` is nested in `Session.device`, this needs a new
`SessionProviding.updateMID(_:)` seam (parallel to the existing `updateClaim(_:)`),
implemented on `SessionStore` and on the test `FakeSession`.

**Claim handling (carried from V1, now mostly inert).** First post-login call goes
out with `X-IG-WWW-Claim: 0`; capture `x-ig-set-www-claim` off every response and
update `Session.claim` when it changes. On the mobile read path this rarely fires,
but it is kept defensively and is already implemented.

**Server-issued `IG-U-*` (Tier D).** Omit `IG-U-RUR`/`IG-U-SHBID`/`IG-U-SHBTS`
until IG sends the corresponding `ig-set-*`/`ig-u-*` headers; then store + replay.
Never fabricate.

**Session death** (`401/403`, or `200` body containing `login_required` /
`checkpoint_required`): unchanged — `IGWebClient` throws `.needsLogin`; Repository
surfaces it calmly; UI routes back to the WebView. No crash, no retry-storm.

**Security (non-negotiable, carried from V1 + recon §7).**
- `sessionid` is password-grade: **Keychain only, never logged, never committed.**
- Tests **never** hit live Instagram — `MockURLProtocol` only.
- Fixtures use **scrubbed fake values only** (`sessionid=fake_session_id`,
  `ds_user_id=12345`, scrubbed name/username/`pk`/`thread_id`/profile URLs/message
  text). No real session/CSRF/claim strings anywhere in tests or fixtures.
- The live session used during recon is **rotated** (it entered dev history).

---

## Consequential edits to carried-over V1 sections

- **§4 (architecture/data flow):** the `IGWebClient` lane string changes from
  `instagram.com/api/v1/...` to **`i.instagram.com/api/v1/...`**; auth annotation
  changes from "session + headers" to "Bearer + iOS header set". Diagram shape and
  flow are otherwise unchanged.
- **§8 (testing strategy):** the `IGWebClient` row's header assertions change from
  Cookie/CSRF/web-app-id to **Bearer + mobile app-id + Tier-A/B/C presence**.
  Strategy (fixtures replayed via `MockURLProtocol`, never live) is unchanged, plus
  two practical rules from review:
  - **Assert only custom `X-*` headers + `Authorization` (C5).** `Host`,
    `Connection`, `Accept-Encoding`, and `Content-Length` are managed by the URL
    Loading System; manual values may be dropped and may not even appear in
    `MockURLProtocol`'s captured request. Set them (harmless) but never assert them
    — that would fail for platform reasons, not logic.
  - **Fixtures: hand-author a synthetic *mobile* fixture for the TDD loop (C4).** A
    real scrubbed mobile capture needs a live call, which tests can't make. Recon §3
    says existing DTOs should decode mobile responses unchanged, so author a small
    synthetic mobile inbox+thread fixture (incl. `oldest_cursor`) to drive red→green;
    a real scrubbed capture is a separate, manual verification step.
- **§6 (firewall), §9 (open questions):** unchanged.

---

## Open questions (non-blocking, for implementation)

- Pinned `appVersion` and `bloksVersionID` values — choose current values at build
  time.
- Exact `X-IG-Capabilities` iOS value — `3brTv10=` returned 200; refine if needed.
- Web-session longevity on the mobile host (§3) — measure empirically.
- Thread-endpoint behavior not separately probed — confirm against the first
  scrubbed thread fixture (shares host+auth+path with inbox).
