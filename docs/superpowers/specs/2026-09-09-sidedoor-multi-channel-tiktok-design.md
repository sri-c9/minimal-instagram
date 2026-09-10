---
title: Sidedoor — Multi-Channel Firewall and TikTok Channel — Design Spec
date: 2026-09-09
status: draft — awaiting review
related:
  - docs/superpowers/specs/2026-06-30-webview-firewall-design.md
  - README.md
extends: The 2026-06-30 WebView Firewall spec. Everything there still holds unless this spec says otherwise.
---

# Sidedoor — Multi-Channel Firewall and TikTok Channel — Design Spec

## 1. Goal

Generalize the Instagram-only WebView firewall into a per-channel design, rename the product to **Sidedoor**, and add **TikTok** as the second channel with the same treatment Instagram gets today: DMs, media opened from a DM, nothing else.

Two deliverables, in this order:

1. The channel abstraction, with Instagram as the only channel and **no behavior change**.
2. TikTok, written from on-device measurement rather than assumption.

The lesson that shapes the design: a URL-based firewall is not sufficient on its own. Instagram mounts its reels feed inline inside a DM thread with no URL change, so the route policy was never consulted. The fix was DOM-level, plus a JS→Swift bridge so the shell knows it is showing media. Every channel therefore gets two enforcement layers, a route classifier and an optional DOM hook, and the shell treats both as first-class inputs.

## 2. Name and rename inventory

The product is **Sidedoor**: you come in through the side door straight to your friends and never walk through the lobby. App Store search on 2026-09-09 found no social or messaging app by that name. "Just DMs" was rejected because "Only DMs" is an existing App Store app with the same premise.

| Thing | Was | Becomes |
|---|---|---|
| Display name | Minimal Instagram | Sidedoor |
| App target and scheme | MinimalInstagram | Sidedoor |
| Bundle ID | com.srichandramouli.MinimalInstagram | com.srichandramouli.Sidedoor |
| Xcode project (generated) | MinimalInstagram.xcodeproj | Sidedoor.xcodeproj |
| App entry file | MinimalInstagramApp.swift | SidedoorApp.swift |
| Package directory | Packages/IGCore | Packages/SidedoorCore |
| Package, library, target | IGCore | SidedoorCore |
| Test target | IGCoreTests | SidedoorCoreTests |
| Module doc file | IGCore.swift | SidedoorCore.swift |
| All imports | `import IGCore` | `import SidedoorCore` |
| SwiftLint `included` paths | Packages/IGCore/… | Packages/SidedoorCore/… |
| project.yml `name`, target, package ref | MinimalInstagram / IGCore | Sidedoor / SidedoorCore |
| JS install guard | `window.__minimalInstagramFirewallInstalled` | `window.__sidedoorInstalled` |
| Injected `<style>` marker | `data-minimal-instagram` | `data-sidedoor` |
| Instagram feed-lock attribute | `data-minimal-instagram-feed-locked` | `data-sidedoor-feed-locked` |
| README title and layout section | Minimal Instagram / IGCore | Sidedoor / SidedoorCore |

Out of scope for the rename: the historical documents under `docs/` other than this one and the README (they record the Instagram-era design and stay as written), the repository folder name, and the GitHub remote.

Effect on device: the new bundle ID is a fresh install. The old app can be deleted. Nothing migrates from the old WebKit data store, and the user logs into Instagram again once.

## 3. Hard boundaries, for every channel

These are the 2026-06-30 §3 boundaries, restated once so they apply to any channel, not just Instagram.

The app will not, for any channel:

- Call private or mobile APIs.
- Extract, copy, decode, store, or export cookies or session tokens.
- Spoof app headers, device identity, or hand-set a user-agent string.
- Use a backend, proxy, or bridge.
- Poll in the background.
- Automate clicks, scrolling, sending, liking, watching, or navigation.
- Scrape, parse, store, upload, or analyze DM content.
- Store usernames, thread IDs, message text, or media URLs.
- Share anything between channels: no shared login, no linking, no shared cookie jar.

The app does, for every channel:

- Load the channel's official web UI in an app-owned `WKWebView`, in a WebKit data store private to that channel.
- Let the channel handle login, 2FA, checkpoints, captchas, DMs, sending, and media.
- Enforce a local route firewall that blocks by default.
- Neutralize inline feed surfaces with a small, channel-specific DOM hook when a channel needs one.
- Show native chrome, blocker, settings, per-channel logout, loading, and error states.

Blocked screens offer exactly one action, **Back to DMs**. There is no override.

One TikTok-specific posture question, desktop content mode, is deferred to §8.4. It is a decision to be written down after measurement, never a silent default.

## 4. Architecture

Dependency direction is unchanged: the `Sidedoor` app target depends on the `SidedoorCore` package. The package never imports SwiftUI, UIKit, or WebKit. JavaScript and CSS live in the package as plain strings; that keeps a channel in one place and lets script composition be unit-tested.

| Shared (one implementation, one test suite) | Per channel |
|---|---|
| `RouteFirewall`: the stateful rule (remember last DM, media only from a DM, block a second media navigation, default block) | Hosts, home URL, `classify(path:)` |
| `FirewallSurface`, `FirewallScreenState` | Display name |
| Script prelude and epilogue: install guard, style injection, history hooks, `routeChanged` post, deduplicated `mediaSurfaceChanged` post, scheduler, presence timer | CSS |
| `FirewallWebView`, its coordinator, the two message handlers | Inline-media hook, optional |
| Root, switcher, settings, blocker, media banner, error view | WebKit data store identifier |
| `WKWebViewConfiguration` media settings | Nothing else |

A channel with no inline-feed quirk supplies no hook, and the shell installs no `MutationObserver` for it. No channel pays for another channel's workaround.

Why one protocol and not one package per channel: what differs per channel is one classifier, one CSS block, and at most one DOM hook of roughly a hundred lines. There are no per-channel dependencies, fixtures, or shipping units. Separate packages would buy only a build-system guarantee that channels do not import each other, which review catches for free.

Why not data-only channels (a plist of hosts and path prefixes): TikTok media is `/@user/video/<id>` while `/@user` is a profile, so prefix matching is not enough, and DOM hooks are code. It would grow into a DSL.

## 5. Core package: `SidedoorCore`

### 5.1 Files

```text
Packages/SidedoorCore/Sources/SidedoorCore/
  SidedoorCore.swift                 module doc + version (was IGCore.swift)
  Channel/
    ChannelID.swift
    Channel.swift
    RouteKind.swift
    ChannelWebScript.swift
    Channels/
      InstagramChannel.swift
      TikTokChannel.swift            increment 4
  WebFirewall/
    RouteFirewall.swift
    FirewallSurface.swift
    FirewallScreenState.swift        unchanged
    FirewallScript.swift
  Mapper/  Models/  Networking/      paused private-API transport; untouched except the module name
```

### 5.2 Types

```swift
public enum ChannelID: String, CaseIterable, Codable, Sendable {
    case instagram
    // case tiktok — added in increment 4, together with TikTokChannel

    /// The registry. Every case resolves to exactly one stateless conformance.
    public var channel: any Channel { get }
}

public enum RouteKind: Equatable, Sendable {
    case auth    // login, one-tap, challenge, captcha, verification
    case dm      // inbox and threads
    case media   // a single post/reel/story/video page
    case other   // everything else: blocked
}

public struct ChannelWebScript: Equatable, Sendable {
    public let css: String
    /// JS defining `lockInlineMedia()` and `inlineMediaState()` (see §5.5). `nil` when the
    /// channel has no inline feed surface.
    public let inlineMediaHook: String?
}

public protocol Channel: Sendable {
    var id: ChannelID { get }
    var displayName: String { get }
    /// Lowercase hostnames, matched exactly. Scheme, port, and credentials are checked by RouteFirewall.
    var hosts: Set<String> { get }
    /// https, on a listed host, and must classify as `.dm`.
    var homeURL: URL { get }
    /// Receives the normalized path only: `"/"` for empty, no host, no query, no fragment.
    func classify(path: String) -> RouteKind
    var webScript: ChannelWebScript { get }
}
```

Rules:

- Exactly one kind per path. Conformances use exact-or-prefix matching (`path == "/x" || path.hasPrefix("/x/")`). A channel that needs a pattern (TikTok media) keeps the pattern inside its own file.
- Channels are stateless value types. The state machines hold a `ChannelID`, not the existential, so `RouteFirewall` and `FirewallSurface` keep their synthesized `Equatable` and the tests keep comparing whole values.
- `classify` never sees the host. If a channel ever needs host-dependent classification, that is a new requirement on the protocol, not a special case in the firewall.

### 5.3 `RouteFirewall`

```swift
public struct RouteFirewall: Equatable, Sendable {
    public let channelID: ChannelID
    public init(channel: ChannelID, lastDMURL: URL? = nil)

    public var homeURL: URL                                     // channel.homeURL
    public mutating func decision(for targetURL: URL, currentURL: URL?) -> RouteDecision
    public mutating func rememberIfDM(_ url: URL)
    public func backToDMsURL() -> URL                           // lastDMURL ?? homeURL
    /// nil when the URL is not this channel's web surface (scheme, host, credentials, or port fail).
    public func kind(of url: URL) -> RouteKind?
    public static func routeURL(for url: URL) -> URL            // unchanged normalization
}
```

`decision(for:currentURL:)` is the current procedure with the Instagram predicates replaced by `kind(of:)`:

1. Not a channel web URL (scheme not https, host not listed, credentials present, or a non-443 port) → `.block(returnURL: backToDMsURL())`.
2. `.auth` → `.allow`.
3. `.dm` → remember it as the last DM, `.allow`.
4. `.media` and `currentURL` is `.dm` → remember the current DM, `.allowMedia(returnURL: current DM route)`.
5. Anything else, including `.media` from a media or blocked page → `.block(returnURL: backToDMsURL())`.

The static `inboxURL`, `isAllowedAuthURL`, `isDirectURL`, `isMediaURL`, and `isInstagramWebURL` are removed. `RouteDecision` is unchanged.

### 5.4 `FirewallSurface`

`init(channel: ChannelID)`. Every `RouteFirewall.isDirectURL(x)` becomes `routeFirewall.kind(of: x) == .dm` and every `isAllowedAuthURL(x)` becomes `== .auth`. `reset()` keeps the channel. No transition changes; the existing tests pass with only their construction updated.

### 5.5 `FirewallScript`

```swift
public enum FirewallScript {
    public static let routeMessageName = "routeChanged"
    public static let mediaSurfaceMessageName = "mediaSurfaceChanged"
    public static func compose(for channel: any Channel) -> String
}
```

The composed user script is one IIFE in four parts:

1. **Prelude.** Install guard on `window.__sidedoorInstalled`. Creates a `<style data-sidedoor="true">` whose `textContent` is the channel CSS, embedded as a JSON string literal (so backticks, backslashes, and `${` in CSS cannot break the script). Appends it to `documentElement`. Adds the shared `body { overscroll-behavior: contain !important; }` rule.
2. **Hook.** The channel's `inlineMediaHook` verbatim, or, when it is `nil`, the defaults:
   ```js
   function lockInlineMedia() {}
   function inlineMediaState() { return 'absent'; }
   ```
3. **Bridge.** `postRoute()` posts `location.href` to `routeChanged`. `scheduleSurfaceCheck()` coalesces into one `requestAnimationFrame`, then calls `lockInlineMedia()`, then `inlineMediaState()`, then acts on the result:
   - `'absent'`: stop the presence timer, report `false`.
   - `'present'`: start the 500 ms presence timer if not running, report `true`.
   - `'hidden'`: keep the timer running, report `false`.

   Reports are deduplicated; only a change posts to `mediaSurfaceChanged`. Each hook call is wrapped in `try/catch`; a throw is treated as `'absent'` and that pass posts nothing. The timer exists because a surface that is hidden without being unmounted changes no child list, so the observer alone cannot see it leave or return.
4. **Epilogue.** Wraps `history.pushState` and `history.replaceState`, listens to `popstate`, posts the initial route on a zero timeout, and, **only when the channel supplied a hook**, observes `document.body` for `childList` and `subtree` mutations with `scheduleSurfaceCheck`.

Hook contract, which each channel's `inlineMediaHook` must satisfy:

- `lockInlineMedia()`: idempotent. Finds any inline feed scroller now in the DOM and removes its ability to scroll, without touching scroll position. Marks what it locked so it does not do the work twice.
- `inlineMediaState()`: returns `'absent'` when nothing locked is in the document, `'present'` when a locked surface is in the document and has a non-zero bounding rect, `'hidden'` when it is in the document but collapsed.
- Neither function reads message text, usernames, or media URLs. They inspect element structure and computed style only.

### 5.6 `InstagramChannel`

Behavior-identical to today.

| `classify(path:)` | Paths |
|---|---|
| `.auth` | `/accounts/login`, `/accounts/login/*`, `/accounts/onetap`, `/accounts/onetap/*`, `/challenge`, `/challenge/*` |
| `.dm` | `/direct`, `/direct/*` |
| `.media` | `/reel`, `/reel/*`, `/p`, `/p/*`, `/stories`, `/stories/*` |
| `.other` | everything else |

- `hosts`: `instagram.com`, `www.instagram.com`.
- `homeURL`: `https://www.instagram.com/direct/inbox/`.
- `css`: the current selector list, minus the `body { overscroll-behavior }` rule, which moves to the shared prelude.
- `inlineMediaHook`: the current `lockReelFeedScrollers` (walk up from every `<video>`; lock the first ancestor whose computed `scroll-snap-type` starts with `y` and whose `overflow-y` is `scroll` or `auto`; set `overflow-y: hidden` and `scroll-snap-type: none` with `!important`; mark with `data-sidedoor-feed-locked`) as `lockInlineMedia()`, and the current presence check (locked element in document → bounding rect non-zero means `'present'`, zero means `'hidden'`; none → `'absent'`) as `inlineMediaState()`.

## 6. App target: `Sidedoor`

### 6.1 Files

```text
App/Sources/
  SidedoorApp.swift                    was MinimalInstagramApp.swift
  RootView.swift                       hosts ChannelRootView
  WebFirewall/
    ChannelRootView.swift              new: active channel + store
    ChannelStore.swift                 new: one FirewallViewModel per channel
    ChannelWebStore.swift              new: ChannelID → WKWebsiteDataStore identifier
    ChannelScreen.swift                was WebFirewallRootView.swift
    FirewallWebView.swift
    FirewallViewModel.swift
    BlockedContentView.swift
    SettingsView.swift
```

### 6.2 `ChannelRootView` and `ChannelStore`

- `@AppStorage("activeChannel")` holds the raw `ChannelID` string. An unknown or missing value resolves to `.instagram`.
- `ChannelStore` is a `@MainActor ObservableObject` with `func model(for: ChannelID) -> FirewallViewModel`, creating lazily and keeping every created model for the life of the process.
- Body: `ChannelScreen(model: store.model(for: active), activeChannel: $active).id(active)`. The `.id` makes a switch rebuild the whole screen, including the WebView.
- `.onChange(of: active)` calls `store.model(for: active).prepareResume()`. That runs outside the body evaluation, so the model's published state is never mutated during a view update.

### 6.3 `ChannelScreen`

The current `WebFirewallRootView` layout, per channel: top bar, divider, web content, blocker overlay, settings sheet.

The title becomes the **channel switcher** in increment 4 (a static display name until then): a `Menu` whose label is the display name with a `chevron.up.chevron.down` glyph and the existing status caption beneath, and whose content is one button per `ChannelID.allCases` with a checkmark on the active one. Selecting sets the binding. Accessibility label: "Switch channel, currently \(displayName)". Nothing else in the top bar moves.

### 6.4 `FirewallViewModel`

- `init(channel: ChannelID)`; stores `channel`; `surface = FirewallSurface(channel: channel)`.
- `homeURL` is the channel's home URL.
- `scriptSource` is `FirewallScript.compose(for: channel.channel)`, computed once.
- `dataStore` is `WKWebsiteDataStore(forIdentifier: channel.webStoreIdentifier)`.
- `var resumeURL: URL`, read-only: `surface.backToDMsURL()`. `makeUIView` loads it, so a channel resumes at its last DM route or its home. Reading it mutates nothing.
- `func prepareResume()`: `surface.prepareLoad()`. Called by the root on a switch (§6.2) to clear a stale blocked or media screen before the first frame. The load itself also self-heals: a DM navigation puts the screen back to `.web` and a commit clears the inline flag, so a missed call costs at most a brief flash of the old overlay.
- `reloadHome()` replaces `reloadInstagram()`.
- `logout()` is the current implementation against `dataStore` instead of `.default()`.

### 6.5 `FirewallWebView`

- `websiteDataStore`, the user script, and the two handler names come from the model and `FirewallScript`.
- `makeUIView` loads `model.resumeURL`; the reload-token path still loads `model.homeURL`.
- Coordinator, delegate methods, and `dismantleUIView` are unchanged.

### 6.6 Data stores

`ChannelWebStore.swift` maps each `ChannelID` to a fixed `UUID` constant, generated once and committed. Every channel uses `WKWebsiteDataStore(forIdentifier:)`; nothing uses `.default()`. The identifiers are not derived from anything user-specific.

### 6.7 Switching semantics

- One live `WKWebView` at a time. Switching dismantles the current one (handlers removed, delegate cleared) and builds the other channel's, which loads that channel's resume URL.
- The outgoing model keeps its `FirewallSurface`. Its screen state is not displayed while inactive. On return, `prepareResume()` resets the screen to `.web` and the load goes to `resumeURL`, so a channel left on a blocked or media screen comes back on its DM route.
- Switching mid-load drops the navigation with the WebView; the old coordinator receives no further callbacks.
- The reload token stays per model.

### 6.8 Settings

- Account section: one destructive row per `ChannelID.allCases`, "Log Out of \(displayName)", each with its own confirmation dialog naming the channel, calling `store.model(for:).logout()`. Logging out of an inactive channel resets its model in place; its next visit loads home, and the channel shows its login.
- Privacy text, channel-neutral: "Each network handles login and DMs inside its own web page. Sidedoor blocks routes locally and does not read messages, extract cookies, or store content."
- About text: "Sidedoor loads a network's web DMs and blocks distracting routes locally."

### 6.9 Strings

| Where | Text |
|---|---|
| Top bar title | channel display name (switcher label in increment 4) |
| Loading indicator accessibility | "Loading \(displayName)" |
| Error headline / body | "Couldn't load \(displayName)" / "Check your connection, then reload \(displayName) DMs." |
| Blocker headline / body | "This \(displayName) route is blocked" / "Sidedoor keeps this view focused on DMs and media opened from DMs." |
| Media banner | unchanged |
| Status captions | unchanged (`DMs`, `Media`, `Blocked`, `Offline`) |

### 6.10 WebView configuration

Shared for every channel until measurement says otherwise: `allowsInlineMediaPlayback = false`, `allowsAirPlayForMediaPlayback = true`, `mediaTypesRequiringUserActionForPlayback = []`, back-forward gestures off, `contentInsetAdjustmentBehavior = .never`, `isInspectable = true` under `#if DEBUG` only. A per-channel media override is deferred (§15).

## 7. TikTok: what is known

### 7.1 Measured

Nothing. No TikTok probing has been done. Every statement in §7.2 is inference and is replaced by the findings from §8 before any TikTok policy is written.

### 7.2 Inferred, unverified

- DMs exist on TikTok's desktop web at `/messages`. Mobile web pushes to the native app and may not expose messaging at all.
- The open thread may be client state rather than part of the URL, in which case Back to DMs can only return to the inbox.
- On the video page, moving to the next video updates the URL, which the existing "second media navigation from media mode is blocked" rule would already stop. If it is client state only, that is the Instagram inline hole again and needs a hook.
- The DM view may embed a shared video in a scroller with no route change.
- TikTok's anti-bot layer may raise a captcha or verification on a fresh WebKit store, possibly on a route of its own that must classify as `.auth`.
- `WKWebView`'s default user agent differs from mobile Safari's, so Safari on the phone is a coarse first check, not the measurement.

## 8. TikTok probe

### 8.1 Setup

- A scratch branch `probe/tiktok-dm-surface` off `develop`, after increment 2 has merged.
- A throwaway `TikTokChannel`: hosts `tiktok.com`, `www.tiktok.com`, `m.tiktok.com`; home `https://www.tiktok.com/messages`; `classify` returns `.dm` for every path; empty CSS; no hook. It is permissive on purpose and never merges.
- A DEBUG build on the connected iPhone with Safari Web Inspector attached from the Mac.
- Before the app: mobile Safari on the phone at `https://www.tiktok.com/messages`, logged out and then logged in.

### 8.2 What to record

1. What mobile Safari shows at `/messages`: a DM UI, a login wall, an app interstitial, or a redirect, and to where.
2. The same in the app's `WKWebView`.
3. Routes, as paths and query: inbox, an open thread, login, signup, captcha, verification, logout, and any redirect applied on first load.
4. A shared video in a DM: tapping it navigates (to what path), mounts inline, or opens a modal. Whether moving to the next video changes the URL.
5. Any full-bleed video container: computed `overflow-y` and `scroll-snap-type` on the ancestors of `<video>`, and whether items carry a permalink.
6. Interstitials and overlays: "Open in app" prompts, their DOM shape for CSS, and whether they block interaction.
7. Media playback under the shared configuration: does video play, with audio.
8. Anti-bot: whether a captcha appears, when, and whether it recurs on relaunch.
9. If mobile web shows no DM surface: repeat 1 through 8 with `WKWebpagePreferences.preferredContentMode = .desktop` applied to main-frame navigations on channel hosts.

### 8.3 Output

`docs/TikTok Web DM Surface — Recon Findings (<date>).md`, dated the day the probe runs, with sections **Measured**, **Inferred**, and **Open**, plus device model, iOS version, app build, and date. It contains no usernames, thread IDs, message text, or media URLs. Only this file merges from the scratch branch.

### 8.4 Decisions gated on the findings

- **D1, content mode.** If mobile web exposes DMs, content mode stays `.recommended` and nothing changes. If it does not, the user decides whether to adopt `.desktop`. If adopted: `Channel` gains `var contentMode: ChannelContentMode` (`.recommended`, `.desktop`), the coordinator applies it in `decidePolicyFor navigationAction, preferences:` for main-frame navigations on channel hosts, and the README posture states it. The working read is that this is the public equivalent of Safari's "Request Desktop Website", not the header spoofing §3 forbids, and carries low incremental risk; that read is inference, and the decision is the user's. If not adopted, TikTok is not shipped.
- **D2, return route.** If the open thread is not in the URL, Back to DMs returns to the inbox and nothing changes. If it is in a query parameter: `Channel` gains `func returnRouteURL(for url: URL) -> URL` with a default of `RouteFirewall.routeURL(for:)`, `RouteFirewall` uses it to remember the last DM, and TikTok's override keeps only the identifying parameter. Covered by tests.
- **D3, feed containment.** URL per video: the existing rule blocks the second media navigation and no hook is needed. Client state only: a hook written from the measured style signature.
- **D4, auth routes.** Whatever is measured, including captcha and verification routes.
- **D5, viability.** Login loops, a recurring captcha, or an un-dismissable app push mean the channel cannot ship under §3. Stop and report. No user-agent strings and no automation to get past it.

## 9. TikTok channel, increment 4

Written from the recon document:

- `ChannelID.tiktok` and `TikTokChannel`: measured hosts and home URL; a classify table with the concrete `.auth`, `.dm`, and `.media` paths (media expected to need a pattern like `/@<user>/video/<id>`, kept inside the channel file); CSS hiding navigation, For You, Explore, Search, profile, and app-push affordances; a hook only if D3 requires one.
- The same media-from-DM rule as Instagram, through the shared `RouteFirewall`.
- Tests per §13.
- The switcher, per-channel logout, the README posture subsection, and the manual checklist.

## 10. Account-safety posture

README's posture section is restructured into a shared statement (§3 here, in README's words) and one subsection per network:

- **Instagram**: the current text, unchanged.
- **TikTok**: the current Terms of Service URL and the section listing prohibited uses (at the time of writing, "Your Access to and Use of Our Services"; verify the section name when writing the README), the same gray-area statement about local CSS/JS, the same list of what is out of scope, the expectation of new-device notifications on first `WKWebView` login, and the D1 statement if desktop content mode is adopted.
- **Precedent**: "Only DMs" ships in the App Store as a Safari extension that strips Instagram to DMs over the official web UI. That is evidence the web-UI-plus-local-CSS approach is an established category, not evidence about any platform's enforcement.

## 11. Content-blind rule, additions

- The only new persisted preference is `activeChannel`, a channel name.
- Recon documents follow the same redaction rule as diagnostics: route category, DOM shape, status, and app version only.
- Data store identifiers are constants, not derived from anything user-specific.
- DOM hooks inspect element structure and computed style only.

## 12. Error handling

- Load failure: the existing error view, with Reload going to the channel's home and Back to DMs to its last DM route.
- Channel switch during a load: the outgoing WebView is dismantled; the incoming one starts fresh from its resume URL.
- Logout failure: unchanged from today (the data-store call has no error path; the reload still runs).
- A hook that throws: the prelude wraps each hook call in `try/catch`, treats a throw as `'absent'`, and never posts a media surface from a failed pass. The route firewall remains in force.
- A captcha or verification that is a modal on an allowed route: nothing to do. One that is a route: `.auth`.
- An unknown `activeChannel` value: `.instagram`.

## 13. Testing

### 13.1 Core, `swift test`

- `InstagramChannelTests`: the §5.6 table, including boundaries (`/direct` vs `/directory`, `/p` vs `/profile`).
- `TikTokChannelTests` (increment 4): the measured table, same shape.
- `ChannelFixture` per channel: `inboxURL`, `threadURL`, `mediaURL`, `authURL`, `blockedURLs`, `externalURL`. Instagram's is today's URL set.
- `RouteFirewallTests`, parametrized over `ChannelID.allCases` with the fixture: DM allowed and remembered; auth allowed; media only from a DM; second media navigation blocked; blocked routes; non-channel hosts, http, credentials, and non-443 ports blocked; query and fragment stripped from remembered routes; fallback to home.
- `FirewallSurfaceTests`, parametrized the same way: every current test, plus "reset keeps the channel".
- `ChannelInvariantTests`: every channel's home URL is https, on a listed host, and classifies as `.dm`; hosts are non-empty and lowercase; a composed script contains the channel CSS as a JSON literal, contains the hook text when one is supplied, contains the no-op defaults when not, and contains `new MutationObserver` only when a hook is supplied.
- `FirewallScriptTests`: CSS containing backticks, backslashes, and `${` composes without breaking the string literal (asserted by decoding the embedded JSON literal back to the input).
- The paused transport tests are untouched apart from the module name.

### 13.2 App, manual, per channel

The README checklist runs once per channel: opens to the channel's DM home; login and verification flows work; DM read and send work; media from a DM opens media mode; Back to DMs returns to the originating thread or inbox; feed, explore, search, profile, and discovery routes show the blocker; logout clears only that channel and returns it to login. Plus: switching channels resumes each at its last DM route; logging out of one channel leaves the other signed in.

### 13.3 Gates

Every increment: `swift test` green, `swiftlint` clean, simulator build succeeds.

## 14. Increments

1. **Rename.** Everything in §2. Done when the app builds, installs fresh, logs into Instagram, and all tests pass under the new module name.
2. **Channel abstraction, Instagram only.** §5 and §6 without the switcher and without `ChannelID.tiktok`. Per-channel data store, `ChannelStore`, resume-on-load, and per-channel logout are included. Done when the manual checklist passes identically to before and every §13.1 suite except TikTok's exists and passes.
3. **TikTok probe.** §8 on the scratch branch. Done when the recon document is merged and D1 through D5 are recorded in it.
4. **TikTok channel.** §9. Done when both channels pass §13.2 and the README posture and checklist are updated.

## 15. Deferred

- Per-channel `WKWebViewConfiguration` media settings, unless the probe requires them.
- Desktop content mode, unless D1 adopts it.
- Keeping both WebViews alive across switches.
- More channels.
- Removing the paused private-API transport from the package.
- External link handling, multi-account, App Store strategy, diagnostics: unchanged from 2026-06-30 §14.
