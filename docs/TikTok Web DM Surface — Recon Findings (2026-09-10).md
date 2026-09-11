---
title: Sidedoor — TikTok Web DM Surface Recon Findings
date: 2026-09-10
status: measurement complete — D1 decided 2026-09-10, TikTok deferred (spec §8.4, plan Task 8)
related: "[[Technical Design (V2)]], docs/superpowers/specs/2026-09-09-sidedoor-multi-channel-tiktok-design.md"
---

# TikTok Web DM Surface — Recon Findings (2026-09-10)

> **TL;DR.** On iPhone, TikTok does not serve a DM surface to `WKWebView`.
> `/messages` server-redirects to `/foryou` whether the WebKit store is logged
> out or signed in as the secondary account, in mobile Safari as well as in the
> app, and the mobile `/inbox` page is the activity inbox (All / Likes /
> Comments / Mentions / Followers) with zero anchors to `/messages`. The spec's
> D1 escape hatch — `preferredContentMode = .desktop` — was applied through both
> public paths (`configuration.defaultWebpagePreferences` and the per-navigation
> `WKWebpagePreferences`) and the page still saw a mobile user agent, so the
> desktop DM app (confirmed real from a Mac capture) is unreachable without a
> hand-set user agent, which §3 forbids. D5 found no login loop, no captcha, and
> only a dismissable app push. Whether TikTok ships at all is now D1, and it is
> the user's call.

**Setup.** iPhone 15 Pro, iOS 26.6; macOS 26.4, Safari 26.4, Xcode 26.6.
Scratch branch `probe/tiktok-dm-surface` on top of `8253b10` (the branch also
carries the throwaway `TikTokChannel`, a `tiktok` case in `ChannelID`, and
probe-only console logging in `FirewallWebView`; none of that merges). Secondary
TikTok account only (§8.1). Content-blind rule (§8.3): path shapes and query
*keys* only; no text, usernames, ids, message content, or hrefs beyond the path
shape. In shapes below, `N` is a run of digits, `@~` is any `@user` segment, `~`
is any other segment.

Route shapes come from a probe-only `print` in `FirewallWebView` on every
committed main-frame URL and every blocked navigation (already redacted at the
print site), captured with `devicectl … --console`. DOM shapes come from a
console probe pasted through Safari Web Inspector (Appendix).

---

## Measured

### 1. Route trail (app WebView, per-channel store, mobile content mode)

Order as observed across launches. "commit" is `didCommit`; "block" is a
firewall cancel. Query shown as key names.

| # | Trigger | Result |
|---|---|---|
| 1 | Launch; store empty; load home `/messages` | server redirect → commit `/foryou` `[lang]` (`/messages` never commits) |
| 2 | Tap **Profile** in TikTok's bottom bar, logged out | navigation to `/@~` `[lang]` |
| 3 | Tap **Inbox** in TikTok's bottom bar, logged out | navigation to `/inbox` `[lang]` |
| 4 | `/inbox` while logged out | commit `/login` `[enter_method, enter_from, launch_type, lang, redirect_url]` |
| 5 | Complete login (secondary account) | commit `/inbox` `[lang]` — the `redirect_url` target |
| 6 | Relaunch, store now signed in; load home `/messages` | server redirect → commit `/foryou` `[lang]` |
| 7 | Same as 6 with `.desktop` content mode (see §5) | server redirect → commit `/foryou` `[lang]` |

Only the final URL of each navigation commits, so the `/messages → /foryou`
redirect happens before any document is created: it is a server-side (or
pre-commit) redirect, not client-side routing.

### 2. Logged-out `/foryou` (item 5, item 1)

Full For You feed mounted with a playing video, an "Open app" pill at the top,
a "Get Coins" pill, TikTok's bottom bar (Home / Discover / + / Inbox /
Profile), and a modal "Get the full app experience" with **Open TikTok** and
**Not now** plus a close control. The modal dismisses with Not now and did not
return during the session. The native TikTok app: not recorded (see Open).

Mobile Safari on the same phone (Step 1, secondary account): `/messages`
redirected to the For You page as well. Recorded from the user's report, not
from a probe.

### 3. Login (items 3, 7, 8 — D4, D5 inputs)

- Entry: `/inbox` while logged out → `/login` with the five query keys above.
  `/login` is a real route on mobile web.
- The login form completed inside the WebView with the secondary account. No
  captcha, no slider, no phone/email verification step, no loop was hit in this
  session (one login, one session). Post-login redirect went to `/inbox`.
- The login page's own route shape for sub-steps (e.g. phone vs email) was not
  captured: only one commit (`/login`) was logged, so any sub-step is
  client-side routing under `/login`.

### 4. Signed-in mobile `/inbox` (item 2 — what the mobile DM entry actually is)

Console probe on the app's page, secondary account signed in:

- Path shape `/inbox`, query keys `[lang]`. Viewport 393×646, DPR 3, body
  width 393. `nav` elements: 0.
- `data-e2e` values matching `nav|inbox|message|login|profile|sidebar|tab`:
  `inbox-header, all-tab, likes-tab, commnets-tab, mentions-tab, followers-tab,
  inbox-list, inbox-list-item, inbox-title, inbox-content, profile-icon`
  (`commnets-tab` is TikTok's spelling).
- Anchors whose path is `/messages` or under it: **0**.
- Distinct anchor path shapes on the page: `/@~`, `/@~/video/N`, `/`,
  `/discover`, `/inbox`.
- `<video>` elements: 0. Logged-in hint (`a[href*="/@"] img` or
  `[data-e2e*="profile"] img`): true.

So the mobile inbox is the activity inbox (likes / comments / mentions /
followers). It contains no DM tab and links to no DM route.

### 5. Desktop content mode (item 9 — D1 input)

Applied for the TikTok WebView only, two ways, both public API:

1. `configuration.defaultWebpagePreferences.preferredContentMode = .desktop`
   in `makeUIView`.
2. `webView(_:decidePolicyFor:preferences:decisionHandler:)` setting
   `preferences.preferredContentMode = .desktop` on every main-frame
   navigation; the delegate logged `desktop=true` for both the `/messages`
   request and its redirect.

Result: `/messages` still redirected to `/foryou` (trail row 7), and
`navigator.userAgent` evaluated from Swift in `didFinish` on the resulting page
was, verbatim:

```
Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko, like Chrome/136.) Mobile/15E148
```

The same string was seen with the `.mobile` build. `window.__sidedoor` was an
object on that page, so the firewall user script did mount. The `like
Chrome/136.` token is recorded as seen and not interpreted.

### 6. Desktop `/messages` exists (Mac Safari capture, URL shapes only)

The user captured a HAR of desktop Safari on the Mac at `/messages` (account
not recorded — see Open). The file was read by a script that emitted only
method, host, path shape, query keys, status, and MIME type; headers, cookies,
and bodies were never printed, and the HAR is not part of the repo. 100
entries, all status 200/204. Shapes that identify the surface:

- `POST im-api.tiktok.com /v1/message/~` and `/v2/message/~`
  (`application/x-protobuf`) — the messaging API.
- `GET www.tiktok.com /api/im/~/~` and `/api/inbox/~`.
- `POST mcs.tiktokv.us /v1/list`, `mcs-ttp2.tiktokv.us /v1/list`,
  `mcs.tiktokw.us /v1/list` (23 of the 100 entries) — a streaming/event feed.
- `POST verification.tiktokw.us /~/setting` and `POST mssdk-ttp2.tiktokw.us
  /web/report`, with signed query keys `X-Bogus`, `X-Dynosaur`, `X-Gnarly`,
  `msToken` on most `www.tiktok.com/api/…` calls — the page's own anti-bot
  and client-signing layer, active on the DM surface.

So a DM web app exists and works in a desktop browser; the app never reached it.

### 7. Firewall behavior discovered along the way

- **Bug fixed (`8253b10`, on this branch, cherry-pick to `develop`):** a
  server redirect into a blocked route is cancelled in `decidePolicyFor`, and
  WebKit reports that as `WebKitErrorDomain` code 102 "Frame load
  interrupted". `FirewallViewModel` compared against `WKErrorDomain`, so the
  cancellation showed the Offline screen ("Couldn't load TikTok … Frame load
  interrupted") instead of the blocker. Instagram never triggered it because
  its logged-out redirect is an auth route. The rule now lives in
  `SidedoorCore.NavigationFailure` with tests.
- With the restriction shape "`/messages` = DM, `/login|/signup` = auth, else
  blocked", a logged-out TikTok tab loops: Back to DMs → `/messages` →
  `/foryou` → blocker. Measured, not a bug in the firewall: the home URL itself
  redirects into a blocked route.
- **§6.3 check passed:** the tab bar was hidden on the blocked screen and
  returned after Back to DMs.
- **§6.7 check passed:** across the session, `makeUIView` was logged exactly
  once per channel per process; switching tabs back and forth never logged it
  again.

### 8. Not reached

Items 4 (shared video in a DM), 6 (media playback with audio under the shared
config), 10 (unread marker), 11 (`document.title` shape in inbox and thread),
and D2/D3 inputs: **not measured**, because no DM surface loaded. Item 11 is
recorded only for the pages that did load: `document.title` was not captured
on them.

## Inferred

- The `/messages → /foryou` redirect is keyed on the client being mobile
  (user agent or equivalent), not on login state, since it happens identically
  logged out and signed in. It could additionally depend on the account's DM
  eligibility; the Mac capture's account was not recorded, so that is not
  excluded (Open).
- `WKWebView` on this iPhone does not honor `preferredContentMode = .desktop`
  through either public path. That is the measured outcome on one device and
  OS; the mechanism (a WebKit policy for iPhone-class devices vs. something
  specific to this configuration) is not established.
- Spec D1 assumed `.desktop` would present a desktop user agent. On iPhone that
  assumption is false, so the "adopt `.desktop`" branch of D1 does not exist as
  written; the only remaining route to the desktop surface is
  `customUserAgent`, which §3 rules out.
- If the D1 outcome is "not on iPhone", TikTok could still be a candidate on
  iPad, where WebKit's `.recommended` mode is desktop for most iPads — but the
  app currently pins `.mobile` for the measured Instagram surface (§6.10), and
  nothing about TikTok on iPad has been measured.

## Open

- Native TikTok app installed on the probe phone: not recorded. It bears on
  whether the "Open TikTok" button and the "Open app" pill deep-link or go to
  the App Store; the modal was dismissable either way.
- Mac HAR account: main or secondary? If main, an account-eligibility cause for
  the redirect is not excluded. Cheapest disambiguation: sign in on the Mac as
  the secondary and open `/messages` directly.
- Instagram tab showed `/accounts/login` `[next]` during the session. Whether
  the user had logged out, or the per-channel store dropped the session, was
  not established. If the latter, it is a bug in `ChannelStore`/data-store
  setup and needs its own check.
- Whether `.desktop` is honored on iPad, and what TikTok serves there.
- Everything in §8 "Not reached".

## Decisions (§8.4)

- **D5, viability.** No login loop, no captcha, no verification step, one
  dismissable app-push modal. Nothing measured here blocks shipping under §3 —
  the blocker is D1, not D5. The desktop surface does run an anti-bot layer
  (`verification.tiktokw.us`, signed API queries); Sidedoor would not interact
  with it, but it is present.
- **D1, content mode.** Mobile web exposes no DMs (measured, §1 and §4).
  `.desktop` via public API does not change the user agent on iPhone (measured,
  §5). Options, for the user: (a) do not ship TikTok; (b) ship TikTok for iPad
  only after an iPad probe, keeping `.mobile` for Instagram; (c) relax §3 to
  allow `customUserAgent` for TikTok — a posture change, not a build task. No
  option is recommended here beyond noting that (c) is the one §3 currently
  forbids. **Decision (user, 2026-09-10): (a) for now — TikTok is off.** No
  TikTok channel ships and no increment 4 plan is written. The `ChannelID`
  identifier `7075CEAF-…` stays reserved, the scratch branch stays local, and
  (b) or (c) can reopen this from the measurements above without re-probing
  the iPhone surface.
- **D2, return route.** Not measurable — no thread route was reached.
- **D3, feed containment.** Not measurable — no shared video was reached. The
  logged-out `/foryou` feed is the surface the blocker must catch if TikTok
  ever ships; its route shape is `/foryou` and its outbound anchors are
  `/following`, `/foryou`, `/search`, `/@~`, `/music/~`, `/tag/~`, `/`,
  `/discover`, `/inbox`.
- **D4, auth routes.** `/login` (with query keys `enter_method, enter_from,
  launch_type, lang, redirect_url`) is the measured auth route; sub-steps are
  client-side under it. `/signup` was not seen. No captcha or verification
  route was seen.
- **D6, unread filter.** Not measurable.
- **D7, unread badge.** Not measurable; `document.title` was not captured.

## Appendix — probes

Route logging (probe branch only): `print` in `FirewallWebView` on `didCommit`
and on each firewall cancel, emitting `PROBE <event> <channel> <host> /<shape>
query=[keys]` with digits → `N`, `@name` → `@~`; and `navigator.userAgent`
evaluated in `didFinish`. Console captured with
`xcrun devicectl device process launch --console`.

DOM probe (paste in Web Inspector on the app's TikTok page):

```js
(function () {
  const ALLOW = /^(messages|login|signup|foryou|explore|following|friends|search|video|discover|upload|live|tag|music|notifications|inbox|setting|settings|passport|profile|business|legal|about|embed|share|t)$/;
  const seg = s => ALLOW.test(s) ? s : (s === '@' ? '@' : (/^@/.test(s) ? '@~' : (/^\d+$/.test(s) ? 'N' : '~')));
  const shape = p => '/' + p.split('/').filter(Boolean).map(seg).join('/');
  const R = {
    urlShape: shape(location.pathname), queryKeys: [...new URLSearchParams(location.search).keys()],
    ua: navigator.userAgent, viewport: { w: innerWidth, h: innerHeight, dpr: devicePixelRatio },
    bodyWidth: document.body.scrollWidth,
    hasSidebar: !!document.querySelector('[data-e2e*="nav"], nav, aside'),
    navCount: document.querySelectorAll('nav').length,
    dataE2ENav: [...new Set([...document.querySelectorAll('[data-e2e]')].map(e => e.getAttribute('data-e2e')).filter(v => /nav|inbox|message|login|profile|sidebar|tab/i.test(v)))].slice(0, 30),
    messagesAnchors: document.querySelectorAll('a[href*="/messages"]').length,
    anchorPathShapes: [...new Set([...document.querySelectorAll('a[href]')].map(a => { try { return shape(new URL(a.href, location.href).pathname); } catch (e) { return '?'; } }))].slice(0, 30),
    videos: document.querySelectorAll('video').length,
    loggedInHint: !!document.querySelector('a[href*="/@"] img, [data-e2e*="profile"] img')
  };
  const out = JSON.stringify(R, null, 1); console.log(out); try { copy(out); } catch (e) {}
})();
```

HAR reduction: a local script that prints, per entry, method, host, redacted
path shape, sorted query key names, status, and MIME type — nothing else. Not
committed; the HAR stays outside the repo.
