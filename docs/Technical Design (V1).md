---
title: Minimal Instagram — Technical Design (V1)
date: 2026-05-22
status: draft — pending review
related: "[[High-Level Product Design (V2)]]"
---

# Minimal Instagram — Technical Design (V1)

> **Last session (2026-05-23):** Built + merged the IGCore firewall core
> (domain models, lenient DTOs, pure `DomainMapper`) to `develop`; 11 tests green,
> confirmed against a sanitized real `direct_v2` capture. Found media_share nests
> under `direct_media_share.media` (fixed), and that the web UI now uses GraphQL
> while REST `/api/v1/direct_v2/` still works (see §3, §9). Next: `IGWebClient`
> (transport) test-first, then `Repository`/`SessionStore`.

> Companion to [[High-Level Product Design (V2)]]. That doc defines *what/why*
> (a relationship-first communication layer over Instagram, with an "attention
> firewall"). This doc defines *how* V1 is built.

---

## 0. V1 scope

In:
- Read DM threads (calm inbox: Unread / Pinned / Recent)
- Send text replies in-app
- Watch reels that were **shared into a DM** (no autoplay, no "next")

Out (deferred / YAGNI for V1):
- Intent-based search (inbox + threads cover the V1 loop)
- Reactions, media/photo sending, voice, calls
- Multi-user / distribution (V1 is single-user, the author's own account)

Success = "I only open it when people message me; I don't get stuck; it feels
like iMessage, not social media."

---

## 1. Key decisions & rationale

| Decision | Choice | Why |
|---|---|---|
| Audience | **Just me** (single account) | Max freedom on data access; ban risk is mine alone; no auth-at-scale or store review |
| Platform | **iPhone** (SwiftUI) | Daily phone use is the point |
| Data access | **On-device, B2: WebView-auth + IG web API** | No home-server dependency; residential phone IP; *and* the WebView offloads login/2FA/checkpoint so we don't reimplement IG's auth or mobile request-signing |
| Auth | Hidden `WKWebView` → IG's real login page | IG handles password/2FA/checkpoint; we never store a password |
| Firewall | Whitelist mapping + capability-based navigation | Forbidden surfaces are *never represented*, not hidden |

**Approaches considered and rejected:**
- *A — Client + home backend (Python/`instagrapi`) over Tailscale.* Best maintainability and credentials-off-phone, but introduces a home-host uptime dependency. Rejected in favor of a fully standalone app.
- *B1 — Native mobile private API in Swift.* Cleanest reel access, but requires reimplementing request-signing + login/2FA/checkpoint in Swift, with no maintained library. Rejected after the spike showed the web path suffices.
- *C — Full WebView DOM-scrape.* Fastest to prototype but weakest exactly where V1 needs strength (reels-in-DM) and most fragile. Rejected.

---

## 2. Spike evidence (2026-05-22)

A read-only spike against the author's own inbox, using a browser-captured web
session (cookie + `X-IG-App-ID` + `X-IG-WWW-Claim`), confirmed B2 end-to-end:

- `GET /api/v1/direct_v2/inbox/` → **HTTP 200**, 20 threads (web auth works).
- A thread returned **6 playable `video_versions` URLs**; sample was a plain
  `*.cdninstagram.com` link.

Findings that shaped the design:
- The web API needs `X-IG-App-ID: 936619743392459` and `X-IG-WWW-Claim`.
- **Reel video bytes live on an unauthenticated CDN; only the metadata call needs
  the session.** → two networking lanes (authed JSON vs. dumb media GET).

---

## 3. Constraints & risks

- **Account ban risk (respect this).** Unofficial access to the *main* account
  risks action up to disable; no burner mitigates it because the real DMs are on
  the main account. Mitigations baked into the design: log in once + reuse a
  persisted session; one consistent device/User-Agent; residential IP (the phone
  itself); human-paced fetches (on open, no tight polling); a few sends, not bulk.
- **ToS.** This is unofficial use of Instagram's private interface for the
  author's own data/personal use. Accepted knowingly for a single-user tool.
- **iOS install.** Personal install means a free 7-day re-signing cert, or a paid
  Apple Developer account ($99/yr) for 1-year provisioning / TestFlight-to-self.
- **Breakage.** IG changes its web API often. Containment: all churn lives in
  `IGWebClient` + `DomainMapper` (Section 5); nothing above `Repository` notices.
- **GraphQL migration (latent, confirmed 2026-05-23).** The instagram.com *web UI*
  has migrated DMs to `/api/graphql` (persisted-query `doc_id`s; reels arrive as
  nested "XMA" attachments). The legacy REST `/api/v1/direct_v2/` endpoints this
  design uses **still return 200** when called directly — our client is a separate
  consumer, not the web UI — but they are the surface most likely to be retired.
  If/when REST breaks, the swap is contained to `IGWebClient` (new transport) +
  the `Raw*DTO` layer (new shapes); domain models, mapper logic, and UI are
  unaffected. YAGNI: not building GraphQL until REST actually breaks.

---

## 4. Architecture & data flow

```
┌─────────────────────────── iPhone (SwiftUI app) ───────────────────────────┐
│  [Calm UI]      Inbox · Thread · Reel viewer  — renders only allowed objects │
│       │                                                                       │
│  [Firewall / DomainMapper]  anti-corruption boundary; drops feed/explore/    │
│       │                     suggestions; enforces "no next reel"             │
│  [Repository]   single data entry point; client → mapper → cache             │
│       │                                                                       │
│  [IGWebClient]  URLSession → instagram.com/api/v1/... (session + headers)    │
│  [SessionStore] cookies/claim captured once via hidden WKWebView (Keychain)  │
│  [MediaFetcher] plain GET → *.cdninstagram.com (no auth) for reel video      │
└──────────────────────────────────────────────────────────────────────────────┘
   auth (rare): WKWebView → IG login | JSON (on open): /api/v1 | video: CDN
```

**Flow:** Log in once via hidden WebView (IG handles pwd/2FA/checkpoint) →
capture cookies + claim → Keychain. Afterward, opening the app makes authed JSON
calls for inbox/threads; reel videos are fetched as unauthenticated CDN GETs. The
Firewall layer between network and UI structurally enforces "no feed/explore/
next-reel" by never producing those objects.

---

## 5. Components

Dependency direction is one-way: UI → Repository → {IGWebClient, DomainMapper};
nothing reaches back up. `DomainMapper` is pure (no I/O).

| Component | Responsibility | Interface (sketch) | Depends on |
|---|---|---|---|
| **SessionStore** | Persist session (cookies, `X-IG-WWW-Claim`, csrf, `ds_user_id`) in Keychain; report logged-in state | `current() -> Session?` · `save(_)` · `clear()` | Keychain |
| **AuthCoordinator** | Drive hidden `WKWebView` login; capture cookies + claim | `login() async throws -> Session` | WKWebView, SessionStore |
| **IGWebClient** | Pure transport: build headers, call `/api/v1/...`, return raw DTOs | `inbox(limit:)` · `thread(id:limit:)` · `sendText(threadId:text:)` | URLSession, SessionStore |
| **DomainMapper** (Firewall) | Map raw DTOs → clean models, **dropping** non-allowed objects (whitelist) | `mapInbox(_) -> [Conversation]` · `mapThread(_) -> ThreadDetail` | nothing (pure) |
| **Repository** | Single data entry point; client → mapper → cache last results | `loadInbox()` · `loadThread(id:)` · `send(threadId:text:)` | IGWebClient, DomainMapper, cache |
| **MediaFetcher** | Unauthenticated CDN fetch of reel video for `AVPlayer` | `playerItem(for: SharedReel)` | URLSession (no auth), AVFoundation |
| **UI (SwiftUI)** | Render domain models only; completion states; reel viewer with no "next" | views + view models | Repository, MediaFetcher |

Domain models: `Conversation`, `Message`, `SharedReel`, `ThreadDetail`, `Session`.

---

## 6. Firewall enforcement (whitelist, defense-in-depth)

Forbidden surfaces are **never represented anywhere in the system.** Three
independent layers each prevent leakage:

| Forbidden (from product spec) | Layer that makes it impossible |
|---|---|
| Feed / Explore / Reels feed | **Fetch:** app only ever calls `inbox`, `thread`, `sendText`. Can't render what's never requested. |
| Suggested users / "reels you might like" / in-thread ads | **Mapper:** whitelists known item types (`text`, `media_share`/`clip`, `reply`); unknown items have no mapping → dropped. |
| "Next reel" / autoplay chain | **Navigation:** reel viewer takes a single `SharedReel` — no cursor, no list, no `advance()` exists. |
| Infinite scroll | Inbox & thread are finite paginated lists ending in a completion state. |

**Allowed path** `person → conversation → shared media → return` maps 1:1 to the
nav graph Inbox → Thread → Reel viewer; the reel viewer's only exits are "back to
conversation" or "close."

**Completion states (first-class):** Inbox → "You're all caught up" · Thread →
"Nothing new here" · Reel end → "End of shared content."

---

## 7. Auth & session lifecycle

**① Cold start (no session):** WebView → `instagram.com/accounts/login` → IG
handles pwd/2FA/checkpoint → observe `WKHTTPCookieStore` until `sessionid`
appears → harvest claim → build `Session` → Keychain.

**② Warm start (session in Keychain):** skip login, straight to Inbox. *Log in
once, reuse for weeks* — the ban-risk and convenience win.

**③ Session death** (`401/403` or `login_required`/`checkpoint_required`):
Repository surfaces `.needsLogin` (no crash, no retry-storm) → UI calmly routes
back to the WebView (user clears any checkpoint on IG's page).

**`X-IG-WWW-Claim` handling:** it is a *response* header, not a cookie. First
post-login call goes out with `X-IG-WWW-Claim: 0`; `IGWebClient` reads
`x-ig-set-www-claim` off every response and updates `SessionStore` when it
changes. Self-refreshing.

**Security:** whole `Session` in Keychain (encrypted, per-app), never logged.
Password never seen by our code — only IG's WebView. One consistent User-Agent
across WebView and `URLSession`.

---

## 8. Testing strategy

Constraint: **tests must not hammer Instagram.** Strategy = fixtures (real
responses captured once, sanitized, replayed offline).

| Layer | How tested | Hits IG? |
|---|---|---|
| **DomainMapper** | Unit tests vs. JSON fixtures: allowed → models; ads/suggestions → **dropped**; reel → `SharedReel` w/ URL; malformed → ignored | No |
| **Firewall invariant** | Golden test: any payload → output contains only allowed types | No |
| **IGWebClient** | Mocked `URLProtocol`: header/URL build; decode fixtures; claim refresh; `login_required` → `.needsLogin` | No |
| **Repository** | Fake client: caching (offline → last cached); error → `.needsLogin` | No |
| **SessionStore** | Keychain round-trip | No |
| **AuthCoordinator / MediaFetcher** | Protocol seam + a couple smoke checks | No (unit) |
| **Manual smoke** | Sparingly, residential IP, never CI/looped: cold login → warm relaunch → open thread → play reel → send text | Yes (rare) |

**Fixture capture:** dev-only "capture mode" dumps one real response; sanitize
names/IDs/session before committing. **TDD fit:** Mapper, Repository, Client
decoding are test-first; WebView/AVPlayer edges are behind protocols + smoke only.

---

## 9. Open questions (for implementation, not blocking)

- ~~Confirm shared-reel item `type` (`clip` vs `media_share`)~~ **Resolved
  2026-05-23 (real capture):** shared reels arrive as *both* `clip` and
  `media_share`. The mapper allow-lists both, video-gated (a `SharedReel` is
  emitted only when a `video_versions[].url` exists). Real nesting:
  `clip.clip.video_versions` and `direct_media_share.media.video_versions`
  (note: the media_share payload key is `direct_media_share`, **not**
  `media_share`). Real junk seen and dropped: `raven_media`, `action_log`,
  photo-only shares.
- Exact send-text endpoint + required CSRF on POST (spike was read-only).
- Cache store choice: simple on-disk JSON vs. SwiftData.
- Pagination depth / "Recent" cutoff for the inbox.
