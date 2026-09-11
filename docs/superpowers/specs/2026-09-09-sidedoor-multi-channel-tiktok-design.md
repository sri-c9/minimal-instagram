---
title: Sidedoor — Multi-Channel Firewall and TikTok Channel — Design Spec
date: 2026-09-09
status: approved 2026-09-10
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

Two smaller features ride along, both decided during review of the first draft: the channel switch is a bottom tab bar with every channel's page kept alive (§6.3, §6.7), and each channel can offer an opt-in **unread-only** view implemented purely as channel CSS (§6.11), written from a measured DOM shape.

The lesson that shapes the design: a URL-based firewall is not sufficient on its own. Instagram mounts its reels feed inline inside a DM thread with no URL change, so the route policy was never consulted. The fix was DOM-level, plus a JS→Swift bridge so the shell knows it is showing media. Every channel therefore gets two enforcement layers, a route classifier and an optional DOM hook, and the shell treats both as first-class inputs.

## 2. Name and rename inventory

The product is **Sidedoor**: you come in through the side door straight to your friends and never walk through the lobby. App Store search on 2026-09-09 found no social or messaging app by that name. "Just DMs" was rejected because "Only DMs" is an existing App Store app with the same premise.

| Thing | Was | Becomes |
|---|---|---|
| Home-screen name | MinimalInstagram (no display name is set today) | Sidedoor, via `INFOPLIST_KEY_CFBundleDisplayName` |
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
| README title, layout, build command, manual checks | Minimal Instagram / IGCore / MinimalInstagram.xcodeproj | Sidedoor / SidedoorCore / Sidedoor.xcodeproj |
| Module version enum and its smoke test | `IGCore.version` | `SidedoorCore.version` |
| `#Preview` blocks in the root and screen views | construct the old root | construct a store and model per §6 |
| Stale generated project on disk | MinimalInstagram.xcodeproj (gitignored) | deleted after `xcodegen generate` |

Left as is, on purpose: the Keychain service string in the paused transport code (`com.sri.minimalinstagram.session`), which nothing in the app flow uses.

Repo hygiene folded into the rename: `Signing.xcconfig` is committed with a team ID although `project.yml` describes it as gitignored, and the `Signing.xcconfig.example` it points to does not exist. Increment 1 adds the file to `.gitignore`, untracks it, and adds the example, so "installs fresh" works on a clean clone.

Out of scope for the rename: the historical documents under `docs/` other than this one and the README (they record the Instagram-era design and stay as written), the repository folder name, and the GitHub remote.

Effect on device: the new bundle ID is a fresh install, and it happens once, at increment 2b (§14), when the per-channel data stores land. The old app can be deleted. Nothing migrates from the old WebKit data store, and the user logs into Instagram again once.

## 3. Hard boundaries, for every channel

These are the 2026-06-30 §3 boundaries, restated once so they apply to any channel, not just Instagram.

The app will not, for any channel:

- Call private or mobile APIs.
- Extract, copy, decode, store, or export cookies or session tokens.
- Spoof app headers, device identity, or hand-set a user-agent string.
- Use a backend, proxy, or bridge.
- Poll the network in the background. The in-page presence timer (§5.5) reads element geometry only, runs only while a locked surface exists, and makes no requests. An inactive channel's page keeps running like any background tab in Safari; the app adds no work to it.
- Automate clicks, scrolling, sending, liking, watching, or navigation.
- Scrape, parse, store, upload, or analyze DM content.
- Store usernames, thread IDs, message text, or media URLs.
- Share anything between channels: no shared login, no linking, no shared cookie jar.

The app does, for every channel:

- Load the channel's official web UI in an app-owned `WKWebView`, in a WebKit data store private to that channel, with content mode pinned to `.mobile` on every device (§6.10).
- Let the channel handle login, 2FA, checkpoints, captchas, DMs, sending, and media.
- Enforce a local route firewall that blocks by default.
- Neutralize inline feed surfaces with a small, channel-specific DOM hook when a channel needs one.
- Show native chrome, blocker, settings, per-channel logout, loading, and error states.
- Optionally hide already-read threads with a channel-supplied stylesheet the user toggles (§6.11). It selects on element structure, never on text, and nothing leaves the page.

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
| Root, tab bar, unread toggle, settings, blocker, media banner, error view | WebKit data store identifier |
| `WKWebViewConfiguration` media settings | Unread-filter CSS, optional |
| | Nothing else |

A channel with no inline-feed quirk supplies no hook, and the shell installs no `MutationObserver` for it. No channel pays for another channel's workaround.

Why one protocol and not one package per channel: what differs per channel is one classifier, one CSS block, and at most one DOM hook of roughly a hundred lines. There are no per-channel dependencies, fixtures, or shipping units. Separate packages would buy only a build-system guarantee that channels do not import each other, which review catches for free.

Why not data-only channels (a plist of hosts and path prefixes): DOM hooks are code, and if, as inferred in §7.2, TikTok's media pages live under the same prefix as profiles, prefix matching is not enough either. It would grow into a DSL.

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
public enum ChannelID: String, CaseIterable, Sendable {
    case instagram
    // case tiktok — added in increment 4, together with TikTokChannel

    /// The registry. Every case resolves to exactly one stateless conformance.
    public var channel: any Channel { get }

    /// Fixed, committed UUID for this channel's WKWebsiteDataStore. Foundation only.
    public var webStoreIdentifier: UUID { get }
}

public enum RouteKind: Hashable, CaseIterable, Sendable {
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
    /// CSS that hides every read thread row when the unread filter is on (see §6.11). It is installed
    /// in its own `<style>` and toggled with the element's `disabled` flag, so the rules need no
    /// scoping prefix. `nil` when the channel has no measured unread marker; the toggle is then not shown.
    public let unreadFilterCSS: String?
}

public protocol Channel: Sendable {
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
- The protocol carries no `id`; `ChannelID` owns the mapping. That keeps the protocol free of a redundant field and lets tests build throwaway conformances (a hookless channel, a channel with hostile CSS) without lying about identity.
- Conformances hold `hosts` and `homeURL` as `static let` constants and build `homeURL` with the existing `preconditionFailure` pattern, never a force unwrap (the lint rule is on).
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

`init(channel: ChannelID)`. Every `RouteFirewall.isDirectURL(x)` becomes `routeFirewall.kind(of: x) == .dm` and every `isAllowedAuthURL(x)` becomes `== .auth`. `reset()` keeps the channel. The guard inside the `.allow` case of `decide` is removed rather than translated: `RouteFirewall` returns `.allow` only for auth and DM, so the guard is always true today. No transition changes. The existing tests change in two places only: construction, and the `RouteFirewall.inboxURL` references, which move to the fixture (§13.1).

### 5.5 `FirewallScript`

```swift
public enum FirewallScript {
    public static let routeMessageName = "routeChanged"
    public static let mediaSurfaceMessageName = "mediaSurfaceChanged"
    public static func compose(for channel: any Channel) -> String
    /// The JS expression the shell evaluates to toggle the unread filter: `window.__sidedoor.setUnreadFilter(true)`.
    public static func setUnreadFilterExpression(_ on: Bool) -> String
}
```

The composed user script is one IIFE in four parts:

1. **Prelude.** Install guard on `window.__sidedoorInstalled`. Creates a `<style data-sidedoor="true">` whose `textContent` is the channel CSS, embedded as a JS string literal produced by an internal `FirewallScript.jsStringLiteral(_:)` (JSON encoding of the string, so backticks, backslashes, and `${` in CSS cannot break the script). `</script>` and U+2028/2029 are non-issues here: this is a `WKUserScript`, not inline HTML, and modern JS string literals accept those code points. Appends it to `documentElement`. Adds the shared `body { overscroll-behavior: contain !important; }` rule. When `unreadFilterCSS` is non-nil, also creates a second `<style data-sidedoor-unread="true">` with that CSS, appended with `disabled = true`, and exposes exactly one function to the shell, `window.__sidedoor.setUnreadFilter(on)`, which flips `disabled`. When it is nil, the function is still defined and does nothing, so the shell's call can never throw. This is the only Swift→JS call in the app.
2. **Hook.** The channel's `inlineMediaHook` verbatim, or, when it is `nil`, the defaults:
   ```js
   function lockInlineMedia() {}
   function inlineMediaState() { return 'absent'; }
   ```
3. **Bridge.** `postRoute()` first calls `scheduleSurfaceCheck()` (as `notifyRouteChanged` does today), then posts `location.href` to `routeChanged`. `scheduleSurfaceCheck()` coalesces into one `requestAnimationFrame`, then calls `lockInlineMedia()`, then `inlineMediaState()`, then acts on the result:
   - `'absent'`: stop the presence timer, report `false`.
   - `'present'`: report `true`.
   - `'hidden'`: report `false`.
   - The 500 ms presence timer runs whenever the state is not `'absent'`, so a surface locked while collapsed is watched from its first pass, exactly as today where the timer runs whenever a locked element exists.

   Reports are deduplicated; only a change posts to `mediaSurfaceChanged`. Each pass is wrapped in `try/catch`; a throw skips the rest of that pass with no state change, no timer change, and no deduplication update, so the next mutation or timer tick simply retries (today's behavior, where an uncaught rAF exception leaves the interval running). The timer exists because a surface that is hidden without being unmounted changes no child list, so the observer alone cannot see it leave or return.
4. **Epilogue.** Wraps `history.pushState` and `history.replaceState`, listens to `popstate`, posts the initial route on a zero timeout (which is also the first surface pass), and, **only when the channel supplied a hook**, observes `document.body` for `childList` and `subtree` mutations with `scheduleSurfaceCheck`. The observer-install snippet is a named constant in `FirewallScript` so the tests assert its presence structurally rather than by hand-typed substring.

Hook contract, which each channel's `inlineMediaHook` must satisfy:

- `lockInlineMedia()`: idempotent. Finds any inline feed scroller now in the DOM and removes its ability to scroll, without touching scroll position. Marks what it locked so it does not do the work twice.
- `inlineMediaState()`: returns `'absent'` when nothing locked is in the document, `'present'` when **any** locked surface in the document has a non-zero bounding rect, `'hidden'` when locked surfaces exist and all are collapsed. "Any", not "the first": today's `querySelector` reports the first match, and a stale collapsed container ahead of a live one would hide a feed the user can see.
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
- `unreadFilterCSS`: `nil` in increment 2a. Written in increment 2c from the measured inbox DOM (§6.11).
- `inlineMediaHook`: the current `lockReelFeedScrollers` (walk up from every `<video>`; lock the first ancestor whose computed `scroll-snap-type` starts with `y` and whose `overflow-y` is `scroll` or `auto`; set `overflow-y: hidden` and `scroll-snap-type: none` with `!important`; mark with `data-sidedoor-feed-locked`) as `lockInlineMedia()`, and the presence check over `querySelectorAll` of the marker (any non-zero rect → `'present'`; some marked, all zero → `'hidden'`; none → `'absent'`) as `inlineMediaState()`.

## 6. App target: `Sidedoor`

### 6.1 Files

```text
App/Sources/
  SidedoorApp.swift                    was MinimalInstagramApp.swift
  RootView.swift                       hosts ChannelRootView
  WebFirewall/
    ChannelRootView.swift              new: active channel + store
    ChannelStore.swift                 new: one FirewallViewModel per channel
    ChannelScreen.swift                was WebFirewallRootView.swift
    FirewallWebView.swift
    FirewallViewModel.swift
    BlockedContentView.swift
    SettingsView.swift
```

### 6.2 `ChannelRootView` and `ChannelStore`

- `@AppStorage("activeChannel")` holds the raw `ChannelID` string. An unknown or missing value resolves to `.instagram`.
- `ChannelStore` is a `@MainActor ObservableObject` with `func model(for: ChannelID) -> FirewallViewModel`, creating lazily and keeping every created model for the life of the process. Its cache is a plain dictionary, not `@Published`: `model(for:)` is called from `body`, and publishing from there is a SwiftUI runtime warning.
- Body, when `ChannelID.allCases.count == 1`: `ChannelScreen(model: store.model(for: active))` and nothing else, so increment 2b ships without a one-item tab bar. Otherwise a `TabView(selection: $active)` with one `ChannelScreen` per `ChannelID.allCases`, each tagged with its ID and given a `tabItem` of `Label(displayName, systemImage:)`. The SF Symbol per channel lives in a private exhaustive `switch` on `ChannelID` in this file (`camera` for Instagram, `music.note` for TikTok), so adding a channel fails to compile until it has an icon; the core package stays free of UI concerns. `ChannelScreen` holds the injected model as `@ObservedObject`, not `@StateObject` as the current root does.
- `.onChange(of: active) { previous, _ in store.model(for: previous).pauseMedia() }` so audio from the outgoing channel stops. Nothing else happens on a switch: no reload, no resume, no state reset (§6.7).

### 6.3 `ChannelScreen`

The current `WebFirewallRootView` layout, per channel: top bar, divider, web content, blocker overlay, settings sheet.

The title is the channel's display name as static text, with the existing status caption beneath. The **channel switch is the system tab bar** owned by the `TabView` in §6.2, one tab per channel: one tap, always visible, no menu. A title menu was the first draft and was rejected in review for costing two taps and offering nowhere to signal that the other channel has something new.

While this channel's screen is `.blocked`, `ChannelScreen` applies `.toolbarVisibility(.hidden, for: .tabBar)` so the blocked screen still offers exactly one action, Back to DMs. Letting the user switch away from a block was considered and not taken; the rule from the 2026-06-30 spec stands. That the selected tab's preference is the one the tab bar honors is expected SwiftUI behavior and is verified on device in increment 4, the first build with two tabs.

Between the title and the gear sits the **Unread** toggle (§6.11), shown only when the channel supplies `unreadFilterCSS` and the screen is `.web`. Nothing in `ChannelScreen` ignores the bottom safe area, so the web content ends above the tab bar rather than running under it; this is checked in the increment 4 manual pass.

> **Amended 2026-09-10 (UI pass after increment 3).** The bar is one row: the
> title (or Back to DMs, in media and blocked states), the media caption, the
> Unread toggle, and the gear. The status caption and the floating media banner
> are gone; `FirewallScreenState.caption` supplies the one line media mode still
> needs. The blocker covers the page edge to edge instead of dimming it, and its
> copy is "Not part of your DMs". Loading is a two-point progress bar along the
> top of the page fed by `estimatedProgress`, the spinner is gone, the page
> pulls to refresh, and `FirewallScreenState.feedbackCue(from:to:)` maps a block
> and a return to haptics. §6.9 rows for the status captions, media banner, and
> blocker headline are superseded accordingly.

### 6.4 `FirewallViewModel`

- `init(channel: ChannelID)`; stores `channel`; `surface = FirewallSurface(channel: channel)`.
- `homeURL` is the channel's home URL.
- `scriptSource` is `FirewallScript.compose(for: channel.channel)`, computed once.
- `dataStore` is `WKWebsiteDataStore(forIdentifier: channel.webStoreIdentifier)`.
- `var resumeURL: URL`, read-only: `surface.backToDMsURL()`. `makeUIView` loads it, so a channel's WebView starts at its last DM route or its home the first time it is built and again after a logout bumps the reload token. Reading it mutates nothing. A channel switch never reads it, because a switch never rebuilds the WebView (§6.7).
- `weak var webView: WKWebView?`, set by `makeUIView` and cleared by `dismantleUIView`. `func pauseMedia()` calls `pauseAllMediaPlayback()` on it, the public WebKit API for exactly this. Called by the root when the channel stops being active.
- `@Published var isUnreadFilterOn: Bool`, backed by `UserDefaults` under `unreadFilter.<channel raw value>`, default off. `func setUnreadFilter(_:)` stores it and evaluates `FirewallScript.setUnreadFilterExpression` on the WebView; `didFinish` re-applies it because a full navigation reinstalls the user script with the style disabled.
- `reloadHome()` replaces `reloadInstagram()`.
- `logout()` is the current implementation against `dataStore` instead of `.default()`.

### 6.5 `FirewallWebView`

- `websiteDataStore`, the user script, and the two handler names come from the model and `FirewallScript`.
- `makeUIView` loads `model.resumeURL`. The reload-token branch in `updateUIView` is deleted: the view is already keyed by `.id(model.reloadToken)`, so a token change always goes through `makeUIView` and that branch is dead today. After a logout the model's surface is reset, so `resumeURL` is the home URL and the login shows.
- `configuration.defaultWebpagePreferences.preferredContentMode = .mobile` (§6.10).
- Coordinator, delegate methods, and `dismantleUIView` are unchanged.

### 6.6 Data stores

`ChannelID.webStoreIdentifier` (in the core package, Foundation only) maps each channel to a fixed `UUID` constant, generated once and committed. Every channel uses `WKWebsiteDataStore(forIdentifier:)`; nothing uses `.default()`. The identifiers are not derived from anything user-specific. WebKit traps on the all-zero UUID, and §13.1 asserts the constants are distinct and non-zero.

One-time cleanup: on first launch after increment 2b, the app calls `removeData` for all types on `WKWebsiteDataStore.default()` and records that it did in `UserDefaults`. This covers the case where increment 1 was installed on a device and logged in, leaving a session in the default store that per-channel logout could never clear. It is harmless on a fresh install.

### 6.7 Switching semantics

- **Every channel's `WKWebView` stays alive once built.** A switch shows the other tab's existing page exactly where the user left it: same route, same scroll position, same screen state. Nothing reloads and no state is reset. The point is that switching feels instant, which is most of what a merged inbox would have felt like and all of it that the posture allows.
- The mechanism is the `TabView` in §6.2, which keeps each tab's view hierarchy, including the `UIViewRepresentable`'s `WKWebView`, once it has been created. Whether it creates unselected tabs eagerly at launch or on first selection is not verified and either is acceptable: eager costs one page load in the background at launch. What must hold, and is checked on device in increment 4: switching back does not call `makeUIView` again, and the page is where it was. If that turns out not to hold, the fallback is a `ZStack` that keeps every `ChannelScreen` mounted with inactive ones hidden and hit-testing off, under a custom bottom bar.
- On a switch the outgoing channel gets `pauseMedia()` (§6.4), so a video playing in a DM does not keep its audio going under the other channel. That is the only thing the app does to an inactive page.
- An inactive channel's page keeps running its own JavaScript, and the injected script keeps working: route posts still update that channel's model, the presence timer still ticks while a locked surface exists, reading geometry only. So a channel can become blocked while inactive if its page navigates to a blocked route on its own; on return the user sees the blocker with Back to DMs, and the tab bar is hidden until they take it (§6.3).
- Switching mid-load leaves the load running; that channel's coordinator keeps receiving its callbacks.
- Two data stores mean two web content processes. That is the price of instant switching and is fine at two channels; §15 re-opens it before a third.
- The reload token stays per model.

### 6.8 Settings

- Account section: one destructive row per `ChannelID.allCases`, "Log Out of \(displayName)", each with its own confirmation dialog naming the channel, calling `store.model(for:).logout()`. Logging out of an inactive channel resets its model in place; its next visit loads home, and the channel shows its login.
- Privacy text, channel-neutral: "Each network handles login and DMs inside its own web page. Sidedoor blocks routes locally and does not read messages, extract cookies, or store content."
- About text: "Sidedoor loads a network's web DMs and blocks distracting routes locally."

### 6.9 Strings

| Where | Text |
|---|---|
| Top bar title | channel display name, static |
| Tab item | channel display name + the §6.2 symbol |
| Unread toggle | "Unread"; accessibility label "Show unread only", value On/Off |
| Loading indicator accessibility | "Loading \(displayName)" |
| Error headline / body | "Couldn't load \(displayName)" / "Check your connection, then reload \(displayName) DMs." |
| Blocker headline / body | "This \(displayName) route is blocked" / "Sidedoor keeps this view focused on DMs and media opened from DMs." |
| Media banner | unchanged |
| Status captions | unchanged (`DMs`, `Media`, `Blocked`, `Offline`) |

### 6.10 WebView configuration

Shared for every channel until measurement says otherwise: `allowsInlineMediaPlayback = false`, `allowsAirPlayForMediaPlayback = true`, `mediaTypesRequiringUserActionForPlayback = []`, back-forward gestures off, `contentInsetAdjustmentBehavior = .never`, `isInspectable = true` under `#if DEBUG` only. A per-channel media override is deferred (§15).

New: `defaultWebpagePreferences.preferredContentMode = .mobile`. WebKit's `.recommended` default means mobile on iPhone and iPad mini but desktop on other iPads, and `project.yml` declares iPad orientations, so today an iPad already gets Instagram's desktop web, where the measured feed signature has not been checked. Pinning `.mobile` makes every device show the surface that was measured and makes D1 (§8.4) a real opt-in rather than something that already happens on some devices.

### 6.11 Unread-only view

The ask: see only threads with something new, on both networks. A merged or filtered list built by the app is scraping and is out (§3). The route taken is the same one the nav-hiding CSS already takes: a stylesheet that hides rows.

- Each channel may supply `unreadFilterCSS` (§5.2): rules that hide every thread row that does **not** contain that network's unread marker, of the form `<row selector>:not(:has(<marker selector>)) { display: none !important; }`. `:has()` has shipped in WebKit since iOS 15.4. The selectors come from measurement, never from a guess, and prefer structural or computed-style signatures over hashed class names, as the feed lock does.
- The prelude installs the rules disabled; the shell enables them through the one exported function (§5.5). Off by default; the user's choice is remembered per channel (§6.4).
- Content-blind: the rules select on the presence of an element, never on text. Nothing is read back. The shell learns nothing about which threads are hidden.
- Known limits, accepted: a thread you have just read disappears from the view until you toggle back; when nothing is unread the list is simply empty, with no explanation from the site, because the rows are hidden rather than gone; and the selectors are the site's markup, so a redesign silently breaks the filter (it fails open: rows reappear). The toggle is the escape hatch in every case.
- If a network's own inbox turns out to offer a native unread filter or URL parameter, that is recorded and the CSS is still written, because the native control lives inside the page and the toggle in the top bar is the one place that behaves the same on every channel.

## 7. TikTok: what is known

### 7.1 Measured

Nothing. No TikTok probing has been done. Every statement in §7.2 is inference and is replaced by the findings from §8 before any TikTok policy is written.

### 7.2 Inferred, unverified

- DMs exist on TikTok's desktop web at `/messages`. Mobile web pushes to the native app and may not expose messaging at all.
- Video pages live under the profile prefix, something like `/@user/video/<id>` beside `/@user` for the profile. If so, media needs a pattern, not a prefix.
- The open thread may be client state rather than part of the URL, in which case Back to DMs can only return to the inbox.
- On the video page, moving to the next video updates the URL, which the existing "second media navigation from media mode is blocked" rule would already stop. If it is client state only, that is the Instagram inline hole again and needs a hook.
- The DM view may embed a shared video in a scroller with no route change.
- TikTok's anti-bot layer may raise a captcha or verification on a fresh WebKit store, possibly on a route of its own that must classify as `.auth`.
- `WKWebView`'s default user agent differs from mobile Safari's, so Safari on the phone is a coarse first check, not the measurement.

## 8. TikTok probe

### 8.1 Setup

- **A secondary TikTok account, not the user's main one.** The probe logs into a fresh WebKit store with a permissive classifier and expects to meet the anti-bot layer; D5's "stop and report" may come after a flag has landed. The repo's live-transport probes already follow this rule.
- A scratch branch `probe/tiktok-dm-surface` off `develop`, after increment 2b has merged.
- A throwaway `TikTokChannel` plus `ChannelID.tiktok`: hosts `tiktok.com`, `www.tiktok.com`, `m.tiktok.com`; home `https://www.tiktok.com/messages`; `classify` returns `.dm` for every path; empty CSS; no hook; no unread filter. It is permissive on purpose and never merges. With two cases the tab bar renders (§6.2), which is how the probe build reaches TikTok.
- A DEBUG build on the connected iPhone with Safari Web Inspector attached from the Mac. The recon doc records whether the TikTok native app is installed on that device, because that changes Universal Link and "open in app" behavior.
- Before the app: mobile Safari on the phone at `https://www.tiktok.com/messages`, logged out and then logged in with the same secondary account. This is a coarse check of what the site serves to mobile WebKit at all; the app measurement is the one that counts.

### 8.2 What to record

1. What mobile Safari shows at `/messages`: a DM UI, a login wall, an app interstitial, or a redirect, and to where.
2. The same in the app's `WKWebView`.
3. Routes, as path shapes and query shapes (`?<param>=<opaque id>`, never values): inbox, an open thread, login, signup, captcha, verification, logout, and any redirect applied on first load. A thread identifier in a query value is exactly what §11 forbids recording.
4. A shared video in a DM: tapping it navigates (to what path), mounts inline, or opens a modal. Whether moving to the next video changes the URL.
5. Any full-bleed video container: computed `overflow-y` and `scroll-snap-type` on the ancestors of `<video>`, and whether items carry a permalink.
6. Interstitials and overlays: "Open in app" prompts, their DOM shape for CSS, and whether they block interaction.
7. Media playback under the shared configuration: does video play, with audio.
8. Anti-bot: whether a captcha appears, when, and whether it recurs on relaunch.
9. If mobile web shows no DM surface: repeat 1 through 8 with `defaultWebpagePreferences.preferredContentMode = .desktop`, and record the user-agent string the page observes (`navigator.userAgent`) under both modes.
10. Unread marker (§6.11): the DOM shape of an inbox row and of the unread indicator inside it, as element structure, attributes, and computed style, never text; whether the inbox offers its own unread filter or a URL parameter for one.
11. Unread signal outside the DOM: what `document.title` contains on the inbox and in a thread, with any unread count present and absent, recorded as a shape (`"(N) …"`) not a value. This gates D7.

### 8.3 Output

`docs/TikTok Web DM Surface — Recon Findings (<date>).md`, dated the day the probe runs, with sections **Measured**, **Inferred**, and **Open**, plus device model, iOS version, app build, and date. It contains no usernames, thread IDs, message text, or media URLs. Only this file merges from the scratch branch.

### 8.4 Decisions gated on the findings

- **D1, content mode.** If mobile web exposes DMs, content mode stays `.mobile` and nothing changes. If it does not, the user decides whether to adopt `.desktop` for TikTok. If adopted: `Channel` gains `var contentMode: ChannelContentMode` (`.mobile`, `.desktop`), `FirewallWebView` applies it through `configuration.defaultWebpagePreferences` (one WebView per channel, so the per-navigation delegate variant is unnecessary), and the README posture states it. What changes, stated plainly: WebKit presents the page a desktop Safari user-agent and desktop platform values, which the page can observe. The working read is that this is the public equivalent of Safari's "Request Desktop Website" and not the hand-set user-agent or app-header spoofing §3 forbids, and that it carries low incremental risk; that read is inference, and the decision is the user's. If not adopted, TikTok is not shipped.
- **D2, return route.** If the open thread is not in the URL, Back to DMs returns to the inbox and nothing changes. If it is in a query parameter: `Channel` gains `func returnRouteURL(for url: URL) -> URL` with a default of `RouteFirewall.routeURL(for:)`, and every site that remembers a DM route switches to it: the `RouteFirewall` initializer, the media return URL in `decision`, `rememberIfDM`, and `currentDirectURL` in `FirewallSurface.observeCommittedURL`. TikTok's override keeps only the identifying parameter. The fixture's `expectedRememberedURL` (§13.1) makes the query-stripping test channel-aware.
- **D3, feed containment.** URL per video: the existing rule blocks the second media navigation and no hook is needed. Client state only: a hook written from the measured style signature.
- **D4, auth routes.** Whatever is measured, including captcha and verification routes.
- **D5, viability.** Login loops, a recurring captcha, or an un-dismissable app push mean the channel cannot ship under §3. Stop and report. No user-agent strings and no automation to get past it.
- **D6, unread filter.** If item 10 yields a marker with a stable structural or style signature, `TikTokChannel.unreadFilterCSS` is written from it. If not, it stays `nil` and TikTok ships without the toggle.
- **D7, unread badge on the tab.** Deferred (§15) until item 11 for both channels says whether the page title carries an unread count. If it does, the design is: observe `WKWebView.title` through public KVO, keep only whether it starts with a parenthesized number, never log or store the title, and show a dot on the tab. Not in scope for increment 4 either way.

## 9. TikTok channel, increment 4

Written from the recon document:

- `ChannelID.tiktok` and `TikTokChannel`: measured hosts and home URL; a classify table with the concrete `.auth`, `.dm`, and `.media` paths (media expected to need a pattern like `/@<user>/video/<id>`, kept inside the channel file); CSS hiding navigation, For You, Explore, Search, profile, and app-push affordances; a hook only if D3 requires one.
- The same media-from-DM rule as Instagram, through the shared `RouteFirewall`.
- Tests per §13.
- `unreadFilterCSS` per D6, or nil.
- The tab bar and its verification, per-channel logout, the README posture subsection, and the manual checklist.

## 10. Account-safety posture

README's posture section is restructured into a shared statement (§3 here, in README's words) and one subsection per network:

- **Instagram**: the current text, unchanged.
- **TikTok**: the current Terms of Service URL and the section listing prohibited uses (at the time of writing, "Your Access to and Use of Our Services"; verify the section name when writing the README), the same gray-area statement about local CSS/JS, the same list of what is out of scope, the expectation of new-device notifications on first `WKWebView` login, and the D1 statement if desktop content mode is adopted.
- **Precedent**: "Only DMs" is listed in the App Store (found by App Store search on 2026-09-09; its listing describes a Safari extension that strips Instagram to DMs over the official web UI). That is evidence that stripping a network's web UI to DMs is a shipped product idea. It is not evidence about embedded-`WKWebView` posture: a Safari extension runs inside the user's own Safari session under Apple-reviewed extension APIs, while this app's sessions are labelled "Mobile Safari WebView" by Instagram.

## 11. Content-blind rule, additions

- The new persisted preferences are `activeChannel`, a channel name, and one boolean per channel for the unread toggle.
- The unread filter is a stylesheet. It selects on the presence of an element and reads nothing back. The one Swift→JS call flips its `disabled` flag and returns nothing.
- Recon documents follow the same redaction rule as diagnostics: route category, DOM shape, status, and app version only.
- Data store identifiers are constants, not derived from anything user-specific.
- DOM hooks inspect element structure and computed style only.

## 12. Error handling

- Load failure: the existing error view, with Reload going to the channel's home and Back to DMs to its last DM route.
- Channel switch during a load: the load continues in the background and that channel's model keeps receiving its callbacks. Nothing is dismantled.
- Unread toggle when the page has no `__sidedoor` object yet (evaluated before the user script ran): the evaluation errors, the stored preference is kept, and `didFinish` re-applies it.
- Logout failure: unchanged from today (the data-store call has no error path; the reload still runs).
- A hook that throws: the prelude skips the rest of that pass with no state, timer, or deduplication change, and the next mutation or timer tick retries (§5.5). The route firewall remains in force throughout.
- A captcha or verification that is a modal on an allowed route: nothing to do. One that is a route: `.auth`.
- An unknown `activeChannel` value: `.instagram`.

## 13. Testing

### 13.1 Core, `swift test`

- `InstagramChannelTests`: the §5.6 table, including boundaries (`/direct` vs `/directory`, `/p` vs `/profile`).
- `TikTokChannelTests` (increment 4): the measured table, same shape.
- `ChannelURLs` per channel (named to avoid the existing `Fixture` helper): `inboxURL`, `threadURL`, `threadURLWithQueryAndFragment`, `expectedRememberedURL`, `mediaURL`, `authURL`, `blockedURLs`, `externalURL`, `otherChannelURL`. Instagram's is today's URL set.
- `RouteFirewallTests`, parametrized over `ChannelID.allCases` with `ChannelURLs`: DM allowed and remembered; auth allowed; media only from a DM; second media navigation blocked; blocked routes; non-channel hosts, http, credentials, and non-443 ports blocked; a remembered route equals `expectedRememberedURL` (query and fragment stripped unless D2 says otherwise for that channel); fallback to home; another channel's host is blocked, which pins the "nothing shared" boundary.
- `FirewallSurfaceTests`, parametrized the same way: every current test, plus "reset keeps the channel".
- `ChannelInvariantTests`, over `ChannelID.allCases`: home URL is https, on a listed host, and classifies as `.dm`; hosts are non-empty and lowercase; `webStoreIdentifier` values are distinct and none is the all-zero UUID; the composed script contains the channel CSS as the literal `jsStringLiteral` produces; a non-nil `unreadFilterCSS` is non-empty and contains `:has(`.
- `FirewallScriptTests`, using throwaway `Channel` conformances (the protocol has no identity requirement, so a hookless test channel and a hostile-CSS test channel are legitimate): with a hook, the composed script contains the hook text and the observer-install constant; without one, it contains the no-op defaults and not the observer constant; with `unreadFilterCSS`, the script contains the second style element with that CSS as the literal `jsStringLiteral` produces and a `setUnreadFilter` that flips it; without, no second style element and a `setUnreadFilter` that is defined and empty; `setUnreadFilterExpression` produces the exact call for both values; `jsStringLiteral` round-trips CSS containing backticks, backslashes, `${`, and U+2028 (tested directly on the helper, not by locating it inside the composed script).
- The paused transport tests are untouched apart from the module name and the version constant.

### 13.2 App, manual, per channel

The README checklist runs once per channel: opens to the channel's DM home; login and verification flows work; DM read and send work; media from a DM opens media mode; Back to DMs returns to the originating thread or inbox; feed, explore, search, profile, and discovery routes show the blocker; logout clears only that channel and returns it to login. Plus: switching channels shows each page exactly where it was, with no reload; audio from a playing video stops on switch; the tab bar disappears while a channel is blocked and returns after Back to DMs; the web content ends above the tab bar; the Unread toggle hides read threads, survives a relaunch, and turning it off restores every row; logging out of one channel leaves the other signed in.

### 13.3 Gates

Every increment: `swift test` green, `swiftlint` clean, simulator build succeeds.

## 14. Increments

1. **Rename.** Everything in §2, including the signing-file hygiene. Done when the simulator build succeeds, `swiftlint` is clean, and all tests pass under the new module name. No device install is required here; installing and logging in at this point is allowed but pointless, because 2b replaces the data store and the one-time cleanup in §6.6 clears what this login leaves behind.
2. **Channel abstraction, Instagram only**, in two halves so the pure work is gated by `swift test` before any device-visible change.
   - **2a, core.** §5: `Channel`, `ChannelID` (with `webStoreIdentifier`), `RouteKind`, `ChannelWebScript`, `InstagramChannel`, the `RouteFirewall` and `FirewallSurface` generalization, `FirewallScript` in the package, and every §13.1 suite except TikTok's. The app target compiles against it with minimal edits. Done when `swift test` and lint are green.
   - **2b, app.** §6: `ChannelStore`, `ChannelRootView` with the single-channel gate (no tab bar yet), `ChannelScreen`, per-channel data store, one-time default-store cleanup, `.mobile` content mode, `pauseMedia`, per-channel logout, strings. The unread toggle is wired but hidden, because Instagram's `unreadFilterCSS` is still nil. The fresh device install and the single Instagram re-login happen here. Done when the manual checklist passes identically to before.
   - **2c, Instagram unread filter.** Measure first: with the 2b build and Web Inspector, record the inbox row and unread-marker DOM shape (§8.2 item 10 applied to Instagram) and the title shape (item 11) in `docs/Instagram Web Inbox — Unread Marker (<date>).md` under the §8.3 redaction rule. This is read-only inspection of the user's own logged-in inbox and needs no secondary account. Then write `InstagramChannel.unreadFilterCSS` from it, the toggle appears, and §13.2's unread checks pass. If no stable signature exists, record that and leave it nil.
3. **TikTok probe.** §8 on the scratch branch, with a secondary account. Done when the recon document is merged and D1 through D5 are recorded in it.
4. **TikTok channel.** §9, plus the first build with two tabs: the tab bar, the two on-device checks §6.7 and §6.3 defer to here (no `makeUIView` on switch back; tab bar hidden while blocked), and D6. Done when both channels pass §13.2 and the README posture and checklist are updated.

## 15. Deferred

- Per-channel `WKWebViewConfiguration` media settings, unless the probe requires them.
- Desktop content mode, unless D1 adopts it. Scoping the app to iPhone only is the alternative to pinning `.mobile` on iPad (§6.10) and is not taken here.
- The unread badge on the tab, pending D7 from both channels' item 11.
- More channels. Each one is another live web process (§6.7); re-check memory before a third.
- Removing the paused private-API transport from the package.
- External link handling, multi-account, App Store strategy, diagnostics: unchanged from 2026-06-30 §14.
