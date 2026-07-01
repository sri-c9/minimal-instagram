---
title: WebView Firewall — Design Spec
date: 2026-06-30
status: approved — input to implementation plan
related:
  - docs/High-Level Product Design (V2).md
  - docs/Technical Design (V2).md
  - docs/superpowers/specs/2026-06-28-auth-minting-design.md
supersedes_for_next_increment: Auth-minting/private-API app flow is paused in favor of this lower-risk WebView firewall direction.
---

# WebView Firewall — Design Spec

## 1. Goal

Build Minimal Instagram as an **iOS WebView-based Instagram attention firewall** instead of a native private-API Instagram client.

The app loads Instagram's official web DM surface in a `WKWebView`, lets Instagram own authentication and messaging behavior, and locally blocks distracting Instagram surfaces. The product goal remains: Instagram DMs and DM-shared media without feed, Explore, Reels browsing, recommendations, or profile rabbit holes.

V1 is designed for sideload/TestFlight-style distribution first. Public App Store distribution is a later product/legal/review question and is not assumed here.

## 2. Explicit pivot from previous design

The previous path was:

```text
Web login/cookie capture
→ extract sessionid
→ mint IGCore Session
→ build mobile Bearer auth
→ call i.instagram.com private API
→ render native DMs
```

That path is paused because account-risk anecdotes around third-party Instagram clients/bridges make private API auth less attractive.

The new path is:

```text
WKWebView loads https://www.instagram.com/direct/inbox/
→ Instagram handles login, 2FA, checkpoint, DMs, sending, and media rendering
→ app applies local route firewall + minimal visual cleanup
→ app never extracts cookies or calls Instagram private APIs
```

## 3. Hard boundaries

V1 will not:

- Call Instagram private/mobile APIs.
- Extract, copy, decode, store, or export `sessionid`.
- Build `Authorization: Bearer IGT:2:`.
- Spoof Instagram mobile app headers or device identity.
- Use a backend bridge or proxy.
- Poll in the background.
- Automate clicks, scrolling, sending, liking, watching, or navigation.
- Scrape, parse, store, upload, or analyze DM content.
- Store usernames, thread IDs, message text, or media URLs.
- Register as a system-wide Instagram link handler in V1.

V1 does:

- Load Instagram web in an app-owned `WKWebView`.
- Persist Instagram web cookies only in the app's local WebKit data store.
- Enforce a local URL route firewall.
- Hide obvious distracting local UI affordances with limited CSS/JS.
- Show native app chrome, blocker, settings, logout, loading, and error states.

## 4. Product behavior

The app opens to Instagram DMs:

```text
https://www.instagram.com/direct/inbox/
```

If the user is not logged in, Instagram redirects to its own login/checkpoint flow inside the WebView. The app allows those auth routes and does not inspect credentials or cookies.

After login, the user can:

- Read DMs through Instagram's web UI.
- Send/reply/react through Instagram's web UI.
- Open reels/posts/stories only when they are launched from a DM.
- Return from DM-shared media to the originating thread if known, otherwise to the inbox.
- Log out, which clears this app's Instagram WebKit cookies and website data.

The user cannot use the app to browse:

- Feed/home.
- Explore.
- Reels tab/infinite reels.
- Search.
- Profiles as browsing destinations.
- Hashtags/locations.
- Suggested/recommended surfaces.
- External Instagram links opened from outside the app.

Blocked destinations show a native blocker screen with only one action: **Back to DMs**. There is no override and no "open anyway" in V1.

## 5. UI strategy

V1 uses a **native SwiftUI shell** around a persistent `WKWebView`.

The native shell owns:

- App title/top bar.
- Loading/progress state.
- Blocked-content screen.
- Settings/logout.
- Native **Back to DMs** control.
- Media-mode controls.
- Error/retry states.

The WebView owns:

- Instagram login.
- Instagram DM list/thread UI.
- Typing and sending messages.
- Instagram media rendering/playback.

Inside the WebView, V1 allows a limited **Minimal CSS/JS layer**:

- Hide obvious global navigation, sidebar, search, Reels, Explore, and Home/feed affordances.
- Make DM/media pages fit better inside the native shell.
- Hide obvious recommendation panels where practical.
- Observe SPA route changes so the native route firewall can react when Instagram changes URL without a full page load.

V1 avoids aggressive DOM rewriting. It will not rebuild message rows, message bubbles, inbox cells, profile headers, media viewers, or the message composer. The app should feel like **Minimal Instagram wrapping a constrained official Instagram web surface**, not a cloned Instagram UI.

This choice is intentionally reversible. If later testing shows specific distractions that URL blocking and light CSS cannot solve, targeted DOM augmentation can be considered as a later design increment.

## 6. Route firewall

The route firewall is the primary enforcement mechanism. DOM/CSS cleanup is secondary and best-effort.

### 6.1 Always allowed routes

Allowed on `www.instagram.com`:

```text
/accounts/login/*
/accounts/onetap/*
/challenge/*
/direct/*
```

The implementation may also need to allow required Instagram/Meta/CDN subresources that load inside the page. Those are resource-load concerns, not user-navigation destinations.

### 6.2 Media routes allowed only from DM context

Allowed only when navigation originates from a current `/direct/*` route:

```text
/reel/*
/p/*
/stories/*
```

When allowed, the app enters **media mode**:

```text
current route is /direct/*
target route is /reel/*, /p/*, or /stories/*
→ allow navigation
→ remember return route = current DM thread/inbox
→ show native Back to DMs control
```

Back to DMs returns to the exact thread if the app knows it; otherwise it returns to `/direct/inbox/`.

### 6.3 Blocked routes

Blocked by default:

```text
/
/explore/*
/reels/*
/search/*
/<username>/ profile routes
/explore/tags/*
/explore/locations/*
unknown Instagram routes
non-Instagram navigation destinations
external Instagram links opened from outside the app
```

Blocked routes show native blocked content UI, not an Instagram page.

## 7. Auth, session, and logout

Auth is Instagram web auth only:

```text
WKWebView loads /direct/inbox/
Instagram redirects to login if needed
user logs in / completes 2FA / checkpoint inside Instagram web
Instagram stores cookies in the app's persistent WebKit data store
app does not read or export those cookies
```

Use `WKWebsiteDataStore.default()` for the app's WebView so reauth is smoother and the user's Instagram web session is stable across launches.

Logout clears this app's Instagram WebKit state:

```text
Logout
→ clear Instagram/Meta cookies and website data from the app's WebKit data store
→ reset/recreate WebView
→ load /direct/inbox/
→ Instagram shows login again
```

No Keychain `Session` is needed for V1 because the app does not make private API calls.

## 8. Content-blind privacy rule

V1 is content-blind.

Allowed inspection:

- Current URL/path.
- Navigation source/target.
- Route category: login, direct, media, blocked.
- Load/error status.

Disallowed inspection/storage:

- DM text.
- Usernames/profile names.
- Thread IDs as persisted app data.
- Media URLs as persisted app data.
- Message timestamps/content.
- Scraped DOM content for native rendering.

If diagnostics are added later, they must be opt-in and redacted to route category, status/error category, and app version only. No cookies, DM content, usernames, thread IDs, media URLs, or full URLs.

## 9. Risk posture

This design intentionally avoids higher-risk third-party client patterns:

- No private API use.
- No reconstructed auth.
- No copied sessions.
- No fake mobile device profile.
- No shared backend/proxy traffic pattern.
- No automated request behavior.

Remaining risks:

- Instagram may detect or dislike embedded WebView usage.
- Login/checkpoint behavior may vary by account.
- Instagram web DOM/routes may change.
- Some distracting UI may briefly appear before CSS applies.
- CSS selectors may need maintenance.
- App Store review may require a separate product/legal strategy.

The strategy is not to hide or evade detection. The strategy is to avoid suspicious behavior by using Instagram's normal web surface and only applying local, user-facing distraction blocking.

## 10. Components

### `FirewallWebView`

SwiftUI/UIKit bridge around `WKWebView`.

Responsibilities:

- Create a persistent `WKWebView`.
- Load `https://www.instagram.com/direct/inbox/`.
- Install navigation delegate.
- Install script message handler for route changes.
- Inject minimal CSS/JS.
- Report state changes to the SwiftUI coordinator.
- Reset/recreate the WebView on logout.

### `RouteFirewall`

Pure Swift URL classifier and state helper.

Responsibilities:

- Classify URLs as allowed login/auth, allowed DM, media-from-DM, blocked, or external.
- Decide whether media navigation is allowed based on current DM context.
- Preserve last DM return route.
- Default unknown destinations to block.

This component should be unit-tested independently of WebKit.

### `MinimalStyleInjector`

Small CSS/JS injection source.

Responsibilities:

- Hide obvious global nav/sidebar/search/reels/explore/home affordances.
- Hide obvious recommendation panels where practical.
- Fit the web content into the native shell.
- Observe History API / SPA route changes and notify native code.

Constraints:

- No DM content scraping.
- No custom rendering of Instagram messages.
- No aggressive DOM restructuring in V1.

### `BlockedContentView`

Native SwiftUI blocker.

Responsibilities:

- Explain that the current Instagram surface is blocked.
- Offer only **Back to DMs**.
- Avoid shamey/addictive language; keep it calm and neutral.

### `SettingsView`

Native SwiftUI settings.

Responsibilities:

- Logout.
- Version/about.
- Later: non-affiliation note and diagnostics preferences if needed.

## 11. App state

Suggested high-level state:

```text
loading
loginOrDMWeb
mediaMode(returnRoute)
blocked(returnRoute)
error(message)
```

`loginOrDMWeb` uses the same WebView because Instagram decides whether it needs login. The app should not build its own login screen beyond optional native framing/instructions.

## 12. Error handling

- WebView load failure: show native retry state.
- Instagram login/checkpoint: allow; Instagram handles it.
- Unknown route: block by default.
- Blocked route: show blocker; Back to DMs returns to last DM route or `/direct/inbox/`.
- CSS injection failure: log locally in debug; WebView remains usable under route firewall.
- Logout data-clear failure: show error and retry; do not pretend logout succeeded.

## 13. Testing

### Unit tests

Test `RouteFirewall` without WebKit:

- `/direct/*` allowed.
- `/accounts/login/*`, `/accounts/onetap/*`, `/challenge/*` allowed.
- `/reel/*`, `/p/*`, `/stories/*` allowed only from DM context.
- Feed/home blocked.
- Explore blocked.
- Reels tab blocked.
- Search blocked.
- Profile routes blocked.
- Hashtag/location routes blocked.
- Unknown routes blocked.
- Non-Instagram hosts blocked as user navigation destinations.
- Last DM return route is preserved.
- Back to DMs falls back to `/direct/inbox/` when no thread is known.

### Manual app tests

- Fresh login works.
- 2FA/checkpoint flow remains usable.
- Relaunch stays logged in.
- Logout clears app WebView data and returns to login.
- DM read works.
- DM send/reply works through Instagram web UI.
- Friend-sent reel opens in media mode.
- Friend-sent post opens in media mode.
- Friend-sent story opens in media mode if Instagram web supports it.
- Back to DMs returns to the originating thread.
- Home/feed attempts show blocker.
- Explore/search/profile/reels-tab attempts show blocker.
- External Instagram link handling is absent in V1.

## 14. Deferred decisions

Deferred until after V1 validation:

- More aggressive DOM augmentation.
- Fully native DM rendering.
- Private API read path revival.
- Safari extension/content blocker variant.
- External Instagram link handling.
- Public App Store strategy.
- Optional redacted diagnostics.
- Multi-account support.

## 15. Implementation note

The existing IGCore private-API transport code can remain in the repository for now, but it is not part of this V1 app flow. The implementation plan should focus on replacing the current static `RootView` with the WebView firewall shell and pure route-policy tests.
