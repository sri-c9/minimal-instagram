---
title: Minimal Instagram — Mobile API Transport Recon Findings
date: 2026-05-23
status: complete — input to Technical Design (V2) + IGWebClient refactor plan
related: "[[Technical Design (V1)]], [[High-Level Product Design (V2)]]"
supersedes: "Technical Design (V1) §1 (data-access decision), §2 (spike), §3 (GraphQL risk framing), §5 (IGWebClient), §7 (claim handling)"
---

# Mobile API Transport — Recon Findings (2026-05-23)

> **TL;DR — the pivot.** Reads do **not** work against the web host
> (`www.instagram.com`) from `URLSession`: that host serves the HTML SPA shell to
> any non-browser client (TLS/HTTP2 fingerprinting). They **do** work against the
> **mobile private host `i.instagram.com`**, which has no web page to serve and
> returns JSON to a plain client. Same `/api/v1/direct_v2/` paths, same DTOs — only
> the **host**, **auth shape** (Cookie → `Bearer IGT:2:`), and **device profile**
> (web → iOS) change. Login still happens in a WebView; we reuse that *web* session
> cross-surface. The entire change is contained to `IGWebClient` + `Session`.

---

## 1. What changed vs. Technical Design (V1)

| Aspect | V1 decision | V2 (this recon) | Why it changed |
|---|---|---|---|
| Host | `www.instagram.com` (web API) | **`i.instagram.com`** (mobile private API) | `www` returns the HTML app shell to `URLSession` (TLS fingerprint gate); `i` returns JSON |
| `X-IG-App-ID` | `936619743392459` (web) | **`567067343352427`** (app) | Confirmed 200 on the mobile host |
| Auth on requests | Cookie header | **`Authorization: Bearer IGT:2:<b64>`** | Mobile host authenticates by header; cookie-on-`www` gets the shell |
| Device profile | Web (browser UA) | **iOS app** (real-device UA) | Coherent with the real iPhone; built from `UIDevice`/`UIScreen` |
| Login | WebView → web session | **Unchanged** — WebView → web session | We reuse the web `sessionid` cross-surface (no mobile login) |

**V1's rejection of "B1 — native mobile private API" no longer holds.** It was
rejected for two reasons, both falsified here:

- *"requires reimplementing request-signing"* → `generate_signature` is a constant
  `signed_body=SIGNATURE.<json>` prefix (real HMAC dropped years ago) and is applied
  **only to POSTs**. Our read path is GET-only → **no signing at all**.
- *"requires reimplementing login/2FA/checkpoint"* → `login_by_sessionid` proves a
  web `sessionid` is convertible to a mobile `Bearer` with **no mobile login**. 2FA/
  checkpoint stay in the WebView, exactly as V1 wanted.

---

## 2. Decisions locked (the cascade)

| # | Decision | Choice | One-line rationale |
|---|---|---|---|
| D1 | API surface | Mobile private REST (`i.instagram.com/api/v1/direct_v2/`) | Only host that returns JSON to a plain client |
| D2 | Delivery model | **Fetch-on-open** (pull-to-refresh; no MQTT, no polling) | Calmest product *and* lowest detection *and* least RE — all the same path |
| D3 | Transport | `URLSession` (keep `IGWebClient`/firewall/tests) | Real iPhone = genuine Apple TLS + residential IP, free |
| D4 | Auth | WebView web login → cookies → `Bearer IGT:2:` (Auth-A) | Lowest RE; 2FA/captcha handled by the real web form |
| D5 | Device profile | iOS, values read from the real device | Most coherent fingerprint; nothing fabricated |
| D6 | Reference | instagrapi (REST + device emulation); ignore its realtime | Battle-tested; we are a fetch-style client like it |
| D7 | Send (write) | Deferred (POST + `signed_body`, separate increment) | V1 already deferred; recon confirms it's a different shape |

---

## 3. Confirmed transport facts (empirical)

Two live probes against the author's secondary account (web session → mobile host):

- **Probe 1** (Android UA): `GET i.instagram.com/api/v1/direct_v2/inbox/` → **HTTP 200** JSON.
- **Probe 2** (iOS UA, app-id `567067343352427`, `X-IG-Capabilities: 3brTv10=`) →
  **HTTP 200**; top-level keys `[inbox, viewer, seq_id, snapshot_at_ms, …, status]`;
  `inbox` keys `[threads, pinned_threads, unseen_count, prev_cursor, has_older,
  oldest_cursor, next_cursor, …]`.

**Endpoints & params** (from instagrapi `direct.py`):

- Inbox `GET direct_v2/inbox/` — initial: `limit=20`, `thread_message_limit=10`,
  `persistentBadging=true`, `visual_message_return_type=unseen`,
  `fetch_reason=initial_snapshot`. Page older: add
  `cursor=<oldest_cursor>` + `direction=older` + `fetch_reason=page_scroll`.
  (`oldest_cursor` is a JSON **string**; `prev/next_cursor` are objects.)
- Thread `GET direct_v2/threads/{id}/` — `limit=20`, `direction=older`, `seq_id`,
  plus `cursor=<cursor>` to page older.

**Auth header** (from `auth.py`):
```
authorization_data = {"ds_user_id": "<id>", "sessionid": "<sid>", "should_use_header_over_cookies": true}
Authorization: Bearer IGT:2:<base64(json(authorization_data))>
```
`ds_user_id` = leading digits of the `sessionid`. No signing on GET.

**Refresh headers:** this inbox read returned **no** `ig-set-authorization` /
`x-ig-set-www-claim` / `ig-u-*` headers — they are issued at *login*, not on reads.
Implication: the Bearer does **not** rotate mid-session; the V1 self-refreshing-claim
logic (§7) is inert-but-harmless for reads. (Keep it defensively; confirm live during dev.)

**DTO compatibility:** `inbox.threads` is exactly where `RawInboxResponse` expects it;
extra mobile keys (`seq_id`, `viewer`, …) are ignored by `Decodable`. Existing DTOs
should decode mobile responses unchanged — to be verified against a scrubbed fixture.

---

## 4. Fingerprint & anti-detection plan

**Header tiers** (from instagrapi `base_headers`):

- **Stable device identity** (minted once, persisted, never regenerated):
  `X-IG-Device-ID` (UUID), `X-IG-Family-Device-ID`, `X-Bloks-Version-Id`,
  `X-IG-Capabilities` (`3brTv10=`), `X-IG-App-ID` (`567067343352427`), `User-Agent`.
- **Per-request noise** (randomized each call, like the app):
  `X-Pigeon-Session-Id`, `X-Pigeon-Rawclienttime`, `X-IG-Bandwidth-*`.
- **Server-issued** (do **not** fabricate): `IG-U-RUR`/`IG-U-SHBID`/`IG-U-SHBTS` —
  instagrapi hardcodes fake HMAC suffixes here; we omit them and let IG issue them,
  which is more coherent than the reference.

**iOS UA — built from real device APIs (nothing faked):**
```
Instagram <app_ver> (<model>; iOS <ver>; <locale>; <lang>; scale=<scale>; <WxH>) AppleWebKit/605.1.15
  model  ← sysctl hw.machine (e.g. iPhone15,3)
  ver    ← UIDevice.current.systemVersion (dots → underscores)
  scale  ← UIScreen.main.scale
  WxH    ← UIScreen.main.nativeBounds
  locale ← Locale.current (en_US / en-US)
  app_ver← pinned (the one value we choose, not read)
```

**Operational rules (instagrapi guides):** device identity is sacred — generate once,
Keychain-persist, load *before* login, never regenerate (regeneration = "new device" =
re-login/flag). Serialize requests (one in-flight per session). Pin one IP per account.

**What we get free on-device:** residential mobile IP; genuine Apple TLS fingerprint;
one consistent physical device; human-paced by construction (fetch-on-open). The
`SessionStore` actor already serializes access (built for claim safety; doubles as the
"one in-flight request" rule).

---

## 5. Impact on components

| Component | Change |
|---|---|
| `IGWebClient` | Host `www`→`i`; auth Cookie→`Bearer IGT:2:`; app-id→`567067343352427`; full iOS header set; add optional `cursor:` to `inbox`/`thread`; **remove** dead Sec-Fetch/AJAX experimental headers |
| `Session` | Add `sessionid` (for the Bearer) + a persisted `DeviceIdentity` (UUIDs, app version, capabilities, bloks id) |
| `AuthCoordinator` | Unchanged in principle: WebView web login mints the session; also mints/loads `DeviceIdentity` *before* login |
| Fixtures/tests | Recapture **scrubbed** mobile inbox+thread fixtures; update header assertions (Bearer + mobile app-id) |
| `DomainMapper`, domain models, UI | **No change** (anti-corruption boundary holds) |

---

## 6. Deferred / open (non-blocking)

- **Auth longevity** — does a web `sessionid` survive long-term on the mobile host?
  Empirical; measure on the secondary account. Upgrade path = native-session bootstrap
  via `ig_sso_users` (Auth-C) if web sessions get checkpointed too often.
- **Pinned iOS app version** — choose a current value at build time.
- **`X-IG-Capabilities` exact iOS value** — `3brTv10=` returned 200; refine if needed.
- **Thread endpoint** — not separately probed; shares host+auth+path with inbox.
  Confirm with the first scrubbed thread fixture.
- **Send-text** — POST + `signed_body=SIGNATURE.<json>` + CSRF; its own future increment.

---

## 7. Security & safety

- Testing on a **secondary account** (decided) to age the device identity / absorb ban risk.
- **Rotate the session** used during recon (a live one entered the dev conversation history).
- `sessionid` is password-grade — Keychain only, never logged, never committed.
- Tests use scrubbed fixtures only; scrub name/username/`pk`/`thread_id`/profile URLs/
  message text before anything enters git. No real session/CSRF/claim strings in fixtures.
