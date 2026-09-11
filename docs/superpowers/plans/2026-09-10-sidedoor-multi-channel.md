# Sidedoor Multi-Channel Implementation Plan

> **For agentic workers:** Implement this plan task-by-task, in order. Steps use checkbox (`- [ ]`) syntax for tracking. Every task ends with `swift test` green, `swiftlint` clean, and a simulator build, then a commit.

**Spec:** `docs/superpowers/specs/2026-09-09-sidedoor-multi-channel-tiktok-design.md` (approved 2026-09-10). Section numbers below (§) refer to it.

**Goal:** Rename the product to Sidedoor, generalize the Instagram-only firewall into a per-channel design with no behavior change, add the opt-in unread-only view, then probe TikTok on device so its channel can be written from measurement.

**Architecture:** The `Sidedoor` app target depends on the `SidedoorCore` package. Route policy, the screen state machine, channel definitions, and script composition live in the package as pure Swift and are tested with `swift test`. The app target owns `WKWebView`, SwiftUI, and the per-channel data stores.

**Tech Stack:** Swift 6, SwiftUI, WebKit, Swift Testing, XcodeGen, SwiftLint.

**Scope of this plan:** Spec increments 1, 2a, 2b, 2c, and 3 (Tasks 1–8). Increment 4, the TikTok channel, is written from the recon document that Task 8 produces, so its plan is a separate file written after that document exists. Writing TikTok's classifier, CSS, or hook now would be guessing selectors and route shapes, which the spec forbids.

## Global Constraints

- iOS deployment target stays `26.0`; Swift language mode stays 6 for both targets.
- `SidedoorCore` never imports SwiftUI, UIKit, or WebKit.
- Every §3 boundary holds: no private APIs, no cookie or token extraction, no user-agent strings, no background polling, no automation, no scraping, nothing shared between channels.
- Blocked screens offer exactly one action, Back to DMs.
- Content-blind: the app inspects URLs, element structure, and computed style only.
- Where the spec says "measure", the task records the measurement in a doc before any selector is written. No selector or threshold in this plan is invented; the two tasks that need measurement (Tasks 7 and 8) stop at the measurement and say what gets written from it.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Simulator and device

- Simulator build destination: `platform=iOS Simulator,name=iPhone 17`.
- Device for manual checks: "Sri's iPhone" (iPhone 15 Pro), id `52919ACD-52A5-5FD6-B5C8-54F1A3A1191E`.

## One correction to the spec, found while reading the repo

§2 says `Signing.xcconfig` is committed with a team ID and that the `Signing.xcconfig.example` it points to does not exist. Measured in the repo at `801a4cc`: `Signing.xcconfig` is committed with an empty `DEVELOPMENT_TEAM =` and `#include? "Signing.local.xcconfig"`; the team ID lives in `Signing.local.xcconfig`, which `.gitignore` already ignores. The only stale thing is the comment in `project.yml` (and one README line) that still describes the old `.example` scheme. Task 1 fixes the comment and the README line and does not untrack anything.

---

## File Structure

After Task 6 the repo looks like this (paused transport code omitted):

```text
project.yml                                   name Sidedoor, target Sidedoor, package SidedoorCore
.swiftlint.yml                                included paths under Packages/SidedoorCore
App/Sources/
  SidedoorApp.swift                           was MinimalInstagramApp.swift; runs LegacyDataStoreCleanup
  RootView.swift                              hosts ChannelRootView
  WebFirewall/
    ChannelRootView.swift                     new: active channel, single-channel gate, TabView
    ChannelStore.swift                        new: one FirewallViewModel per channel
    ChannelScreen.swift                       was WebFirewallRootView.swift
    LegacyDataStoreCleanup.swift              new: one-time wipe of WKWebsiteDataStore.default()
    FirewallWebView.swift                     per-channel store, script from the package, .mobile
    FirewallViewModel.swift                   init(channel:), resumeURL, pauseMedia, unread filter
    BlockedContentView.swift                  takes displayName
    SettingsView.swift                        one logout row per channel
Packages/SidedoorCore/
  Package.swift
  Sources/SidedoorCore/
    SidedoorCore.swift                        was IGCore.swift
    Channel/
      ChannelID.swift
      Channel.swift                           protocol + path-matching helper
      RouteKind.swift
      ChannelWebScript.swift
      Channels/InstagramChannel.swift
    WebFirewall/
      RouteFirewall.swift                     channel-aware
      FirewallSurface.swift                   channel-aware
      FirewallScreenState.swift               unchanged
      FirewallScript.swift                    was App/.../MinimalStyleInjector.swift, generalized
  Tests/SidedoorCoreTests/
    Support/ChannelURLs.swift                 new fixture
    ChannelInvariantTests.swift               new
    InstagramChannelTests.swift               new
    FirewallScriptTests.swift                 new
    RouteFirewallTests.swift                  parametrized over ChannelID
    FirewallSurfaceTests.swift                parametrized over ChannelID
    SmokeTests.swift                          SidedoorCore.version
```

---

### Task 1: Rename to Sidedoor (increment 1)

**Files:**
- Move: `Packages/IGCore` → `Packages/SidedoorCore`, with `Sources/IGCore` → `Sources/SidedoorCore`, `Tests/IGCoreTests` → `Tests/SidedoorCoreTests`, `IGCore.swift` → `SidedoorCore.swift`
- Move: `App/Sources/MinimalInstagramApp.swift` → `App/Sources/SidedoorApp.swift`
- Modify: `Packages/SidedoorCore/Package.swift`, `.swiftlint.yml`, `project.yml`, `README.md`, every `import IGCore`, `SmokeTests.swift`, `MinimalStyleInjector.swift` (JS markers only), `WebFirewallRootView.swift`, `BlockedContentView.swift`, `SettingsView.swift`

Not touched: anything under `docs/` other than this plan, the paused transport's Keychain service string, the repo folder name, the remote.

- [ ] **Step 1: Move the package and the app entry file**

```bash
git mv Packages/IGCore Packages/SidedoorCore
git mv Packages/SidedoorCore/Sources/IGCore Packages/SidedoorCore/Sources/SidedoorCore
git mv Packages/SidedoorCore/Tests/IGCoreTests Packages/SidedoorCore/Tests/SidedoorCoreTests
git mv Packages/SidedoorCore/Sources/SidedoorCore/IGCore.swift Packages/SidedoorCore/Sources/SidedoorCore/SidedoorCore.swift
git mv App/Sources/MinimalInstagramApp.swift App/Sources/SidedoorApp.swift
rm -rf Packages/SidedoorCore/.build
```

- [ ] **Step 2: Rename the module everywhere it is named**

Replace the whole of `Packages/SidedoorCore/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SidedoorCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v13)   // host floor for `swift test`: enables async URLSession + modern Foundation APIs
    ],
    products: [
        .library(name: "SidedoorCore", targets: ["SidedoorCore"])
    ],
    targets: [
        .target(
            name: "SidedoorCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SidedoorCoreTests",
            dependencies: ["SidedoorCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
```

Replace the whole of `Packages/SidedoorCore/Sources/SidedoorCore/SidedoorCore.swift`:

```swift
/// SidedoorCore — the pure, UI-free logic layer for Sidedoor.
///
/// Everything that can be unit-tested without a simulator lives here: the
/// channel definitions, the route firewall, the screen state machine, the
/// injected script composition, and the paused private-API transport. This
/// module must never import SwiftUI, UIKit, or WebKit — the package boundary
/// is what structurally enforces the "pure logic, one-way dependency" rule.
public enum SidedoorCore {
    /// Marketing version of the core module. Bumped as the package evolves.
    public static let version = "0.0.1"
}
```

Then the mechanical replacements:

```bash
grep -rl "import IGCore" App Packages | xargs sed -i '' 's/import IGCore/import SidedoorCore/'
sed -i '' 's/IGCore\.version/SidedoorCore.version/; s/the IGCore module/the SidedoorCore module/' \
  Packages/SidedoorCore/Tests/SidedoorCoreTests/SmokeTests.swift
sed -i '' 's#Packages/IGCore/#Packages/SidedoorCore/#g' .swiftlint.yml
sed -i '' "s/lives in \`IGCore\`/lives in \`SidedoorCore\`/" App/Sources/WebFirewall/FirewallViewModel.swift
sed -i '' 's/struct MinimalInstagramApp: App/struct SidedoorApp: App/' App/Sources/SidedoorApp.swift
grep -rn "IGCore\|MinimalInstagramApp" App Packages .swiftlint.yml
```

Expected: the final grep prints nothing.

- [ ] **Step 3: Rename the project, target, bundle ID, and display name**

In `project.yml`:

- Line 1: `name: Sidedoor`.
- `packages:` block: `SidedoorCore:` with `path: Packages/SidedoorCore`.
- `targets:` key `MinimalInstagram:` → `Sidedoor:`; its `dependencies` entry → `- package: SidedoorCore`.
- `PRODUCT_BUNDLE_IDENTIFIER: com.srichandramouli.Sidedoor`.
- Directly under it add `INFOPLIST_KEY_CFBundleDisplayName: Sidedoor`.
- Replace the signing comment block (the four lines starting `# Local, gitignored signing settings.`) with:

```yaml
# Signing.xcconfig is committed with an empty team and `#include?`s the
# gitignored Signing.local.xcconfig, which holds DEVELOPMENT_TEAM for device
# builds. The .xcodeproj is generated, so a team picked in Xcode's Signing
# editor is lost on the next `xcodegen generate`; the xcconfig survives it.
```

- [ ] **Step 4: Rename the JS markers and the user-visible product name**

In `App/Sources/WebFirewall/MinimalStyleInjector.swift` (the file itself is replaced in Task 3, so only the markers change here):

```bash
sed -i '' 's/__minimalInstagramFirewallInstalled/__sidedoorInstalled/g; s/data-minimal-instagram-feed-locked/data-sidedoor-feed-locked/; s/data-minimal-instagram/data-sidedoor/' \
  App/Sources/WebFirewall/MinimalStyleInjector.swift
```

In `App/Sources/WebFirewall/WebFirewallRootView.swift` line 50: `Text("Minimal Instagram")` → `Text("Sidedoor")`.

In `App/Sources/WebFirewall/BlockedContentView.swift` line 18: the body text becomes `"Sidedoor keeps this view focused on DMs and media opened from DMs."`.

In `App/Sources/WebFirewall/SettingsView.swift`: the Privacy text becomes `"Instagram handles login and DMs inside its web page. " + "Sidedoor blocks routes locally and does not read messages, " + "extract cookies, or store Instagram content."`; the About text becomes `"Sidedoor loads Instagram web DMs and blocks distracting routes locally."`.

- [ ] **Step 5: Update the README**

In `README.md`:

- Title: `# Sidedoor`. First paragraph: `A relationship-first, "attention firewall" iOS app for social DMs. V1 loads Instagram's official web DM surface in a local WKWebView, ...` (rest unchanged).
- Layout block: `.swiftlint.yml Lint config (governs App + SidedoorCore)`; `Packages/ SidedoorCore/ ... Sources/SidedoorCore/ Tests/SidedoorCoreTests/`.
- The paragraph starting "`IGCore` is a Swift Package": `SidedoorCore` throughout. Delete the "**Intended `IGCore` structure**" paragraph; it describes the paused transport plan and is stale.
- Commands: `cd Packages/SidedoorCore && swift test`; `xcodebuild -project Sidedoor.xcodeproj -scheme Sidedoor -destination 'platform=iOS Simulator,name=iPhone 17' build`.
- Closing paragraph: `Open Sidedoor.xcodeproj ...`; replace `On first device run, select your personal team under Signing & Capabilities.` with `For device builds, put your team ID in Signing.local.xcconfig (gitignored; see the comment in Signing.xcconfig).`

- [ ] **Step 6: Regenerate, verify, commit**

```bash
xcodegen generate
rm -rf MinimalInstagram.xcodeproj
swiftlint --quiet
(cd Packages/SidedoorCore && swift test)
xcodebuild -project Sidedoor.xcodeproj -scheme Sidedoor \
  -destination 'platform=iOS Simulator,name=iPhone 17' build -quiet
git status --short
```

Expected: lint prints nothing; every test passes under the new module name; the build exits 0; `git status` shows only renames and the edited files, no `.xcodeproj`.

```bash
git add -A
git commit -m "Rename Minimal Instagram to Sidedoor

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---
### Task 2: Channel types and `InstagramChannel` (increment 2a, part 1)

**Files:**
- Create: `Packages/SidedoorCore/Sources/SidedoorCore/Channel/RouteKind.swift`
- Create: `Packages/SidedoorCore/Sources/SidedoorCore/Channel/ChannelWebScript.swift`
- Create: `Packages/SidedoorCore/Sources/SidedoorCore/Channel/Channel.swift`
- Create: `Packages/SidedoorCore/Sources/SidedoorCore/Channel/ChannelID.swift`
- Create: `Packages/SidedoorCore/Sources/SidedoorCore/Channel/Channels/InstagramChannel.swift`
- Test: `Packages/SidedoorCore/Tests/SidedoorCoreTests/InstagramChannelTests.swift`
- Test: `Packages/SidedoorCore/Tests/SidedoorCoreTests/ChannelInvariantTests.swift` (the script-related assertions are added in Task 4)

**Interfaces produced:** exactly the §5.2 types. `ChannelID.webStoreIdentifier` values are the two UUIDs generated for this plan on 2026-09-10 (`D36DECBA-…` for Instagram; `7075CEAF-…` is reserved for TikTok and is used by the Task 8 probe channel).

- [ ] **Step 1: Write the failing channel tests**

Create `Packages/SidedoorCore/Tests/SidedoorCoreTests/InstagramChannelTests.swift`:

```swift
import Foundation
import Testing
@testable import SidedoorCore

@Suite struct InstagramChannelTests {
    private let channel = InstagramChannel()

    @Test(arguments: [
        "/accounts/login", "/accounts/login/", "/accounts/login/two_factor/",
        "/accounts/onetap", "/accounts/onetap/",
        "/challenge", "/challenge/action/"
    ])
    func authPaths(path: String) {
        #expect(channel.classify(path: path) == .auth)
    }

    @Test(arguments: ["/direct", "/direct/", "/direct/inbox/", "/direct/t/12345/"])
    func dmPaths(path: String) {
        #expect(channel.classify(path: path) == .dm)
    }

    @Test(arguments: ["/reel", "/reel/ABC123/", "/p", "/p/POST123/", "/stories", "/stories/alice/999/"])
    func mediaPaths(path: String) {
        #expect(channel.classify(path: path) == .media)
    }

    @Test(arguments: [
        "/", "/explore/", "/reels/", "/search/", "/alice/",
        "/explore/tags/surfing/", "/explore/locations/123/place/",
        "/accounts/activity/", "/accounts/", "/directory", "/direct-messages", "/profile", "/pics/", "/story/"
    ])
    func otherPaths(path: String) {
        #expect(channel.classify(path: path) == .other)
    }

    @Test func identity() throws {
        #expect(channel.displayName == "Instagram")
        #expect(channel.hosts == ["instagram.com", "www.instagram.com"])
        #expect(channel.homeURL == (try #require(URL(string: "https://www.instagram.com/direct/inbox/"))))
        #expect(channel.webScript.inlineMediaHook != nil)
        #expect(channel.webScript.unreadFilterCSS == nil)
    }

    @Test func cssHidesNavigationAndDoesNotCarryTheSharedBodyRule() {
        let css = channel.webScript.css
        #expect(css.contains(#"a[href^="/explore"]"#))
        #expect(css.contains(#"a[aria-label="Reels"]"#))
        #expect(!css.contains("overscroll-behavior"))
    }
}
```

Create `Packages/SidedoorCore/Tests/SidedoorCoreTests/ChannelInvariantTests.swift`:

```swift
import Foundation
import Testing
@testable import SidedoorCore

/// Holds for every channel in the registry. Adding a channel adds it to these
/// tests for free through `ChannelID.allCases`.
@Suite struct ChannelInvariantTests {
    @Test(arguments: ChannelID.allCases)
    func homeURLIsAnHTTPSDMRouteOnAListedHost(channelID: ChannelID) throws {
        let channel = channelID.channel
        let home = channel.homeURL

        #expect(home.scheme == "https")
        #expect(channel.hosts.contains(try #require(home.host)))
        #expect(home.user == nil && home.password == nil && home.port == nil)
        #expect(channel.classify(path: home.path.isEmpty ? "/" : home.path) == .dm)
    }

    @Test(arguments: ChannelID.allCases)
    func hostsAreNonEmptyAndLowercase(channelID: ChannelID) {
        let hosts = channelID.channel.hosts
        #expect(!hosts.isEmpty)
        for host in hosts {
            #expect(host == host.lowercased())
            #expect(!host.isEmpty)
        }
    }

    @Test(arguments: ChannelID.allCases)
    func displayNameIsNonEmpty(channelID: ChannelID) {
        #expect(!channelID.channel.displayName.isEmpty)
    }

    @Test func webStoreIdentifiersAreDistinctAndNonZero() {
        let identifiers = ChannelID.allCases.map(\.webStoreIdentifier)
        #expect(Set(identifiers).count == identifiers.count)
        for identifier in identifiers {
            #expect(identifier != UUID(uuid: UUID_NULL))
        }
    }

    @Test(arguments: ChannelID.allCases)
    func unreadFilterCSSWhenPresentIsAHasRule(channelID: ChannelID) {
        guard let css = channelID.channel.webScript.unreadFilterCSS else { return }
        #expect(!css.isEmpty)
        #expect(css.contains(":has("))
    }
}
```

Run: `cd Packages/SidedoorCore && swift test --filter "InstagramChannelTests|ChannelInvariantTests"`. Expected: compile failure, the types do not exist yet.

- [ ] **Step 2: Add the shared types**

Create `Packages/SidedoorCore/Sources/SidedoorCore/Channel/RouteKind.swift`:

```swift
/// What a channel says a path is. Exactly one kind per path; `.other` is blocked.
public enum RouteKind: Hashable, CaseIterable, Sendable {
    /// Login, one-tap, challenge, captcha, verification.
    case auth
    /// The inbox and threads.
    case dm
    /// A single post, reel, story, or video page.
    case media
    /// Everything else.
    case other
}
```

Create `Packages/SidedoorCore/Sources/SidedoorCore/Channel/ChannelWebScript.swift`:

```swift
/// The per-channel pieces of the injected user script. Plain strings so a channel
/// stays in one file and the composed script can be unit-tested.
public struct ChannelWebScript: Equatable, Sendable {
    /// Hides the channel's navigation and discovery affordances. Installed once
    /// per page in a `<style data-sidedoor>` element.
    public let css: String

    /// JavaScript defining `lockInlineMedia()` and `inlineMediaState()`; see
    /// `FirewallScript`. `nil` when the channel has no inline feed surface, in
    /// which case no `MutationObserver` is installed for it.
    public let inlineMediaHook: String?

    /// Hides every read thread row while the unread filter is on. Installed in
    /// its own `<style data-sidedoor-unread>` element, disabled until the shell
    /// enables it, so the rules need no scoping prefix. `nil` when the channel has
    /// no measured unread marker; the toggle is then not shown.
    public let unreadFilterCSS: String?

    public init(css: String, inlineMediaHook: String? = nil, unreadFilterCSS: String? = nil) {
        self.css = css
        self.inlineMediaHook = inlineMediaHook
        self.unreadFilterCSS = unreadFilterCSS
    }
}
```

Create `Packages/SidedoorCore/Sources/SidedoorCore/Channel/Channel.swift`:

```swift
import Foundation

/// One social network's web surface, described statelessly. `ChannelID` owns the
/// mapping from identity to conformance; the protocol carries no `id` so tests can
/// build throwaway conformances.
public protocol Channel: Sendable {
    var displayName: String { get }

    /// Lowercase hostnames, matched exactly. Scheme, port, and credentials are
    /// checked by `RouteFirewall`, not here.
    var hosts: Set<String> { get }

    /// https, on a listed host, and classifies as `.dm`.
    var homeURL: URL { get }

    /// Receives the normalized path only: `"/"` for empty, no host, no query, no
    /// fragment. Never sees the host.
    func classify(path: String) -> RouteKind

    var webScript: ChannelWebScript { get }
}

extension Channel {
    /// Exact-or-prefix matching: `/direct` and `/direct/...`, never `/directory`.
    static func path(_ path: String, isOrUnder route: String) -> Bool {
        path == route || path.hasPrefix(route + "/")
    }

    /// Builds a compile-time-constant URL; a typo is a programmer error, not an optional.
    static func constantURL(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Static channel URL is invalid: \(string)")
        }
        return url
    }
}
```

Create `Packages/SidedoorCore/Sources/SidedoorCore/Channel/ChannelID.swift`:

```swift
import Foundation

/// The channel registry. Every case resolves to exactly one stateless conformance,
/// and the state machines hold this value rather than the existential so they keep
/// their synthesized `Equatable`.
public enum ChannelID: String, CaseIterable, Sendable {
    case instagram

    public var channel: any Channel {
        switch self {
        case .instagram:
            InstagramChannel()
        }
    }

    /// Fixed, committed identifier for this channel's `WKWebsiteDataStore`. Not
    /// derived from anything user-specific. Each channel's cookie jar lives under
    /// its own identifier and nothing is ever shared between them.
    public var webStoreIdentifier: UUID {
        switch self {
        case .instagram:
            Self.constantUUID("D36DECBA-C5F3-4C94-8647-11D599829E5B")
        }
    }

    private static func constantUUID(_ string: String) -> UUID {
        guard let uuid = UUID(uuidString: string) else {
            preconditionFailure("Static data store identifier is invalid: \(string)")
        }
        return uuid
    }
}
```

- [ ] **Step 3: Add `InstagramChannel`**

Create `Packages/SidedoorCore/Sources/SidedoorCore/Channel/Channels/InstagramChannel.swift`. The CSS is today's `MinimalStyleInjector` selector list minus the `body` rule; the hook is today's `lockReelFeedScrollers` and presence check, split into the two functions the contract names (§5.5):

```swift
import Foundation

/// Instagram web, DMs only. Behavior-identical to the pre-channel firewall.
public struct InstagramChannel: Channel {
    public init() {}

    public var displayName: String { "Instagram" }

    public static let hosts: Set<String> = ["instagram.com", "www.instagram.com"]
    public var hosts: Set<String> { Self.hosts }

    public static let homeURL = Self.constantURL("https://www.instagram.com/direct/inbox/")
    public var homeURL: URL { Self.homeURL }

    public func classify(path: String) -> RouteKind {
        if Self.path(path, isOrUnder: "/accounts/login")
            || Self.path(path, isOrUnder: "/accounts/onetap")
            || Self.path(path, isOrUnder: "/challenge") {
            return .auth
        }
        if Self.path(path, isOrUnder: "/direct") {
            return .dm
        }
        if Self.path(path, isOrUnder: "/reel")
            || Self.path(path, isOrUnder: "/p")
            || Self.path(path, isOrUnder: "/stories") {
            return .media
        }
        return .other
    }

    public var webScript: ChannelWebScript {
        ChannelWebScript(css: Self.css, inlineMediaHook: Self.inlineMediaHook, unreadFilterCSS: nil)
    }

    static let css = """
    a[href="/"],
    a[href^="/explore"],
    a[href^="/reels"],
    a[href^="/search"],
    a[href^="/accounts/activity"],
    a[aria-label="Home"],
    a[aria-label="Explore"],
    a[aria-label="Reels"],
    a[aria-label="Search"] {
        display: none !important;
        pointer-events: none !important;
    }

    nav[role="navigation"] a[href="/"],
    nav[role="navigation"] a[href^="/explore"],
    nav[role="navigation"] a[href^="/reels"],
    nav[role="navigation"] a[href^="/search"] {
        display: none !important;
    }
    """

    // A reel shared in a DM never navigates. Instagram mounts its reels feed
    // component inline in the /direct/t/<thread>/ route, so the URL does not change
    // and RouteFirewall is never given a decision to make. Verified on device: the
    // feed is a nested scroller (overflow-y: scroll, scroll-snap-type: y mandatory)
    // holding one full-bleed reel per snap point, with more appended as you scroll,
    // and no per-item permalink anywhere in its markup.
    //
    // Removing that one container's scrollable overflow strands the feed on the
    // shared reel. Scoped to the scroller itself rather than to gestures, so taps,
    // the native fullscreen player, and DM thread scrolling are all untouched.
    static let inlineMediaHook = """
    const FEED_LOCK_ATTRIBUTE = 'data-sidedoor-feed-locked';

    function lockInlineMedia() {
        const videos = document.querySelectorAll('video');
        for (const video of videos) {
            for (let element = video.parentElement;
                 element && element !== document.body;
                 element = element.parentElement) {
                if (element.hasAttribute(FEED_LOCK_ATTRIBUTE)) {
                    break;
                }

                const computed = window.getComputedStyle(element);
                if (!computed.scrollSnapType.startsWith('y')) {
                    continue;
                }
                if (computed.overflowY !== 'scroll' && computed.overflowY !== 'auto') {
                    continue;
                }

                // Scroll position is left alone: Instagram seeds the container on the
                // reel that was actually shared, which is not always the first item.
                element.style.setProperty('overflow-y', 'hidden', 'important');
                element.style.setProperty('scroll-snap-type', 'none', 'important');
                element.setAttribute(FEED_LOCK_ATTRIBUTE, 'true');
                break;
            }
        }
    }

    // 'present' if any locked container has a non-zero rect; 'hidden' when locked
    // containers exist but React has collapsed every one of them rather than
    // unmounting; 'absent' when none is in the document. "Any", not "the first":
    // a stale collapsed container ahead of a live one must not hide a feed the
    // user can see.
    function inlineMediaState() {
        const locked = document.querySelectorAll('[' + FEED_LOCK_ATTRIBUTE + ']');
        if (locked.length === 0) {
            return 'absent';
        }
        for (const element of locked) {
            const rect = element.getBoundingClientRect();
            if (rect.width > 0 && rect.height > 0) {
                return 'present';
            }
        }
        return 'hidden';
    }
    """
}
```

- [ ] **Step 4: Run the new suites, then lint**

```bash
cd Packages/SidedoorCore && swift test --filter "InstagramChannelTests|ChannelInvariantTests"
cd ../.. && swiftlint --quiet
```

Expected: all pass; lint prints nothing. (The rest of the package still builds because nothing existing was touched yet.)

- [ ] **Step 5: Commit**

```bash
git add Packages/SidedoorCore
git commit -m "Add Channel, ChannelID, RouteKind, and InstagramChannel

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---
### Task 3: Channel-aware `RouteFirewall` and `FirewallSurface` (increment 2a, part 2)

**Files:**
- Create: `Packages/SidedoorCore/Tests/SidedoorCoreTests/Support/ChannelURLs.swift`
- Modify: `Packages/SidedoorCore/Sources/SidedoorCore/WebFirewall/RouteFirewall.swift`
- Modify: `Packages/SidedoorCore/Sources/SidedoorCore/WebFirewall/FirewallSurface.swift`
- Modify: `Packages/SidedoorCore/Tests/SidedoorCoreTests/RouteFirewallTests.swift`
- Modify: `Packages/SidedoorCore/Tests/SidedoorCoreTests/FirewallSurfaceTests.swift`
- Modify (compile only): `App/Sources/WebFirewall/FirewallViewModel.swift`

**Interfaces:** §5.3 and §5.4. The static `inboxURL`, `isAllowedAuthURL`, `isDirectURL`, `isMediaURL`, and `isInstagramWebURL` are removed. `RouteDecision` is unchanged.

- [ ] **Step 1: Add the per-channel URL fixture**

Create `Packages/SidedoorCore/Tests/SidedoorCoreTests/Support/ChannelURLs.swift`:

```swift
import Foundation
import Testing
@testable import SidedoorCore

/// One set of representative URLs per channel, so the firewall and surface suites
/// run unchanged over every channel in the registry. Named to avoid the existing
/// `Fixture` JSON helper.
struct ChannelURLs {
    let inboxURL: URL
    let threadURL: URL
    let threadURLWithQueryAndFragment: URL
    /// What the firewall should remember after seeing `threadURLWithQueryAndFragment`.
    let expectedRememberedURL: URL
    let mediaURL: URL
    let secondMediaURL: URL
    let authURLs: [URL]
    let blockedURLs: [URL]
    /// A host no channel owns.
    let externalURL: URL
    /// A DM route on a different channel's host: must be blocked, pinning "nothing shared".
    let otherChannelURL: URL

    static func fixture(for channel: ChannelID) throws -> ChannelURLs {
        switch channel {
        case .instagram:
            try ChannelURLs(
                inboxURL: url("https://www.instagram.com/direct/inbox/"),
                threadURL: url("https://www.instagram.com/direct/t/12345/"),
                threadURLWithQueryAndFragment: url("https://www.instagram.com/direct/t/12345/?igsh=token#frag"),
                expectedRememberedURL: url("https://www.instagram.com/direct/t/12345/"),
                mediaURL: url("https://www.instagram.com/reel/ABC123/"),
                secondMediaURL: url("https://www.instagram.com/reel/SUGGESTED/"),
                authURLs: [
                    url("https://www.instagram.com/accounts/login/"),
                    url("https://www.instagram.com/accounts/onetap/"),
                    url("https://www.instagram.com/challenge/action/")
                ],
                blockedURLs: [
                    url("https://www.instagram.com/"),
                    url("https://www.instagram.com/explore/"),
                    url("https://www.instagram.com/reels/"),
                    url("https://www.instagram.com/search/"),
                    url("https://www.instagram.com/alice/"),
                    url("https://www.instagram.com/explore/tags/surfing/"),
                    url("https://www.instagram.com/explore/locations/123/place/")
                ],
                externalURL: url("https://example.com/direct/inbox/"),
                otherChannelURL: url("https://www.tiktok.com/messages")
            )
        }
    }

    private static func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }
}
```

- [ ] **Step 2: Rewrite the firewall tests over every channel**

Replace the whole of `Packages/SidedoorCore/Tests/SidedoorCoreTests/RouteFirewallTests.swift`:

```swift
import Foundation
import Testing
@testable import SidedoorCore

@Suite struct RouteFirewallTests {
    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    @Test(arguments: ChannelID.allCases)
    func dmRoutesAreAllowedAndRemembered(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var firewall = RouteFirewall(channel: channel)

        #expect(firewall.decision(for: urls.threadURL, currentURL: nil) == .allow)
        #expect(firewall.backToDMsURL() == urls.threadURL)
    }

    @Test(arguments: ChannelID.allCases)
    func authRoutesAreAllowed(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var firewall = RouteFirewall(channel: channel)

        for authURL in urls.authURLs {
            #expect(firewall.decision(for: authURL, currentURL: nil) == .allow)
        }
    }

    @Test(arguments: ChannelID.allCases)
    func mediaRoutesAreAllowedOnlyFromADM(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var firewall = RouteFirewall(channel: channel)

        #expect(firewall.decision(for: urls.mediaURL, currentURL: nil) == .block(returnURL: urls.inboxURL))
        #expect(firewall.decision(for: urls.mediaURL, currentURL: urls.threadURL)
            == .allowMedia(returnURL: urls.threadURL))
    }

    @Test(arguments: ChannelID.allCases)
    func secondMediaNavigationFromMediaModeIsBlocked(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var firewall = RouteFirewall(channel: channel)

        #expect(firewall.decision(for: urls.mediaURL, currentURL: urls.threadURL)
            == .allowMedia(returnURL: urls.threadURL))
        #expect(firewall.decision(for: urls.secondMediaURL, currentURL: urls.mediaURL)
            == .block(returnURL: urls.threadURL))
    }

    @Test(arguments: ChannelID.allCases)
    func distractingRoutesAreBlocked(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var firewall = RouteFirewall(channel: channel)
        _ = firewall.decision(for: urls.threadURL, currentURL: nil)

        for blockedURL in urls.blockedURLs {
            #expect(firewall.decision(for: blockedURL, currentURL: urls.threadURL)
                == .block(returnURL: urls.threadURL))
        }
    }

    @Test(arguments: ChannelID.allCases)
    func foreignHostsAreBlocked(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var firewall = RouteFirewall(channel: channel)

        #expect(firewall.decision(for: urls.externalURL, currentURL: nil) == .block(returnURL: urls.inboxURL))
        #expect(firewall.decision(for: urls.otherChannelURL, currentURL: nil) == .block(returnURL: urls.inboxURL))
        #expect(firewall.kind(of: urls.otherChannelURL) == nil)
    }

    @Test(arguments: ChannelID.allCases)
    func insecureCredentialedAndNonDefaultPortURLsAreBlocked(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var firewall = RouteFirewall(channel: channel)
        var components = try #require(URLComponents(url: urls.inboxURL, resolvingAgainstBaseURL: false))

        components.scheme = "http"
        let httpURL = try #require(components.url)
        components.scheme = "https"
        components.user = "user"
        components.password = "pass"
        let credentialedURL = try #require(components.url)
        components.user = nil
        components.password = nil
        components.port = 8443
        let nonDefaultPortURL = try #require(components.url)

        for badURL in [httpURL, credentialedURL, nonDefaultPortURL] {
            #expect(firewall.decision(for: badURL, currentURL: nil) == .block(returnURL: urls.inboxURL))
            #expect(firewall.kind(of: badURL) == nil)
        }
        #expect(RouteFirewall(channel: channel, lastDMURL: credentialedURL).backToDMsURL() == urls.inboxURL)
    }

    @Test(arguments: ChannelID.allCases)
    func routeMemoryNormalizesTheRememberedURL(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var firewall = RouteFirewall(channel: channel)

        #expect(RouteFirewall(channel: channel, lastDMURL: urls.threadURLWithQueryAndFragment).backToDMsURL()
            == urls.expectedRememberedURL)
        #expect(firewall.decision(for: urls.threadURLWithQueryAndFragment, currentURL: nil) == .allow)
        #expect(firewall.backToDMsURL() == urls.expectedRememberedURL)
        #expect(firewall.decision(for: urls.mediaURL, currentURL: urls.threadURLWithQueryAndFragment)
            == .allowMedia(returnURL: urls.expectedRememberedURL))
    }

    @Test(arguments: ChannelID.allCases)
    func backToDMsFallsBackToHomeWhenNoThreadIsKnown(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        let firewall = RouteFirewall(channel: channel)

        #expect(firewall.backToDMsURL() == urls.inboxURL)
        #expect(firewall.homeURL == urls.inboxURL)
    }

    @Test(arguments: ChannelID.allCases)
    func backToDMsUsesLastRememberedDMRoute(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var firewall = RouteFirewall(channel: channel)

        firewall.rememberIfDM(urls.inboxURL)
        #expect(firewall.backToDMsURL() == urls.inboxURL)

        firewall.rememberIfDM(urls.threadURL)
        #expect(firewall.backToDMsURL() == urls.threadURL)

        firewall.rememberIfDM(urls.mediaURL)
        #expect(firewall.backToDMsURL() == urls.threadURL)
    }

    @Test(arguments: ChannelID.allCases)
    func kindReportsTheChannelClassification(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        let firewall = RouteFirewall(channel: channel)

        #expect(firewall.kind(of: urls.threadURL) == .dm)
        #expect(firewall.kind(of: urls.mediaURL) == .media)
        #expect(firewall.kind(of: urls.blockedURLs[0]) == .other)
        for authURL in urls.authURLs {
            #expect(firewall.kind(of: authURL) == .auth)
        }
    }
}
```

- [ ] **Step 3: Rewrite the surface tests over every channel**

Replace the whole of `Packages/SidedoorCore/Tests/SidedoorCoreTests/FirewallSurfaceTests.swift`. Every existing test is kept; only construction and the fixture change, and "reset keeps the channel" is added:

```swift
import Foundation
import Testing
@testable import SidedoorCore

@Suite struct FirewallSurfaceTests {
    /// Puts the surface in the state the app is in while a DM thread is open.
    private func surfaceOnThread(_ channel: ChannelID, _ urls: ChannelURLs) -> FirewallSurface {
        var surface = FirewallSurface(channel: channel)
        surface.observeCommittedURL(urls.threadURL)
        return surface
    }

    // MARK: - The inline media feed

    @Test(arguments: ChannelID.allCases)
    func inlineFeedInAThreadRaisesMediaMode(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var surface = surfaceOnThread(channel, urls)
        #expect(surface.screen == .web)

        surface.observeInlineMediaSurface(isPresent: true)

        #expect(surface.screen == .media(returnURL: urls.threadURL))
        #expect(surface.showsBackToDMs)
    }

    @Test(arguments: ChannelID.allCases)
    func inlineFeedLeavingRestoresTheThread(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var surface = surfaceOnThread(channel, urls)
        surface.observeInlineMediaSurface(isPresent: true)

        surface.observeInlineMediaSurface(isPresent: false)

        #expect(surface.screen == .web)
        #expect(!surface.showsBackToDMs)
    }

    @Test(arguments: ChannelID.allCases)
    func backFromTheInlineFeedReturnsToTheOriginatingThread(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var surface = surfaceOnThread(channel, urls)
        surface.observeInlineMediaSurface(isPresent: true)

        #expect(surface.backToDMsURL() == urls.threadURL)
    }

    @Test(arguments: ChannelID.allCases)
    func repeatedReportsOfTheSameValueAreNoOps(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var surface = surfaceOnThread(channel, urls)

        surface.observeInlineMediaSurface(isPresent: true)
        let afterFirstReport = surface
        surface.observeInlineMediaSurface(isPresent: true)

        #expect(surface == afterFirstReport)
    }

    @Test(arguments: ChannelID.allCases)
    func aFeedReportOutsideADMThreadIsIgnored(channel: ChannelID) {
        // Nothing has committed, so there is no thread to return to; the route
        // firewall owns whatever is on screen and this must not overwrite it.
        var surface = FirewallSurface(channel: channel)

        surface.observeInlineMediaSurface(isPresent: true)

        #expect(surface.screen == .web)
    }

    // MARK: - Not fighting the route firewall

    @Test(arguments: ChannelID.allCases)
    func losingTheInlineFeedLeavesNavigatedMediaModeAlone(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var surface = surfaceOnThread(channel, urls)
        surface.observeInlineMediaSurface(isPresent: true)

        // A real navigation to a media page takes over the screen...
        surface.decide(for: urls.mediaURL)
        #expect(surface.screen == .media(returnURL: urls.threadURL))

        // ...and a late "the inline feed is gone" report must not clear it.
        surface.observeInlineMediaSurface(isPresent: false)

        #expect(surface.screen == .media(returnURL: urls.threadURL))
    }

    @Test(arguments: ChannelID.allCases)
    func losingTheInlineFeedLeavesTheBlockerAlone(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var surface = surfaceOnThread(channel, urls)
        surface.observeInlineMediaSurface(isPresent: true)

        surface.decide(for: urls.blockedURLs[0])
        #expect(surface.screen == .blocked(returnURL: urls.threadURL))

        surface.observeInlineMediaSurface(isPresent: false)

        #expect(surface.screen == .blocked(returnURL: urls.threadURL))
    }

    @Test(arguments: ChannelID.allCases)
    func aCommittedNavigationRearmsTheInlineReport(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var surface = surfaceOnThread(channel, urls)
        surface.observeInlineMediaSurface(isPresent: true)

        // Re-entering the thread (Back to DMs, or a reload) clears the surface,
        // so opening media again has to raise media mode a second time.
        surface.observeCommittedURL(urls.threadURL)
        #expect(surface.screen == .web)

        surface.observeInlineMediaSurface(isPresent: true)

        #expect(surface.screen == .media(returnURL: urls.threadURL))
    }

    @Test(arguments: ChannelID.allCases)
    func prepareLoadClearsTheInlineFeed(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var surface = surfaceOnThread(channel, urls)
        surface.observeInlineMediaSurface(isPresent: true)

        surface.prepareLoad()

        #expect(surface.screen == .web)
    }

    // MARK: - Route decisions still hold

    @Test(arguments: ChannelID.allCases)
    func dmRoutesShowTheWebSurface(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var surface = FirewallSurface(channel: channel)

        surface.decide(for: urls.threadURL)

        #expect(surface.screen == .web)
    }

    @Test(arguments: ChannelID.allCases)
    func authRoutesShowTheWebSurfaceAfterABlock(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var surface = FirewallSurface(channel: channel)
        surface.decide(for: urls.blockedURLs[0])
        #expect(surface.screen == .blocked(returnURL: urls.inboxURL))

        surface.decide(for: urls.authURLs[0])

        #expect(surface.screen == .web)
    }

    @Test(arguments: ChannelID.allCases)
    func mediaIsBlockedWhenNotOpenedFromADM(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var surface = FirewallSurface(channel: channel)

        surface.decide(for: urls.mediaURL)

        #expect(surface.screen == .blocked(returnURL: urls.inboxURL))
    }

    @Test(arguments: ChannelID.allCases)
    func errorsSurfaceAndDoNotOfferAReturnURL(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var surface = surfaceOnThread(channel, urls)

        surface.fail("offline")

        #expect(surface.screen == .error("offline"))
        #expect(!surface.showsBackToDMs)
        // The last known thread is still where Back to DMs should go.
        #expect(surface.backToDMsURL() == urls.threadURL)
    }

    @Test(arguments: ChannelID.allCases)
    func resetForgetsTheBrowsedThreadAndKeepsTheChannel(channel: ChannelID) throws {
        let urls = try ChannelURLs.fixture(for: channel)
        var surface = surfaceOnThread(channel, urls)
        surface.observeInlineMediaSurface(isPresent: true)

        surface.reset()

        #expect(surface.screen == .web)
        #expect(surface.backToDMsURL() == urls.inboxURL)
        #expect(surface.channelID == channel)
        #expect(surface == FirewallSurface(channel: channel))
    }
}
```

Run: `cd Packages/SidedoorCore && swift test --filter "RouteFirewallTests|FirewallSurfaceTests"`. Expected: compile failure on `RouteFirewall(channel:)`.

- [ ] **Step 4: Rewrite `RouteFirewall`**

Replace the whole of `Packages/SidedoorCore/Sources/SidedoorCore/WebFirewall/RouteFirewall.swift`:

```swift
import Foundation

public enum RouteDecision: Equatable, Sendable {
    case allow
    case allowMedia(returnURL: URL)
    case block(returnURL: URL)
}

/// The stateful route rule, shared by every channel: remember the last DM route,
/// allow media only from a DM, block a second media navigation, block by default.
/// The channel supplies only hosts, home, and the path classifier.
public struct RouteFirewall: Equatable, Sendable {
    public let channelID: ChannelID

    private var lastDMURL: URL?

    public init(channel: ChannelID, lastDMURL: URL? = nil) {
        self.channelID = channel
        if let lastDMURL, kind(of: lastDMURL) == .dm {
            self.lastDMURL = Self.routeURL(for: lastDMURL)
        }
    }

    public var homeURL: URL { channelID.channel.homeURL }

    public mutating func decision(for targetURL: URL, currentURL: URL?) -> RouteDecision {
        guard let targetKind = kind(of: targetURL) else {
            return .block(returnURL: backToDMsURL())
        }

        switch targetKind {
        case .auth:
            return .allow
        case .dm:
            lastDMURL = Self.routeURL(for: targetURL)
            return .allow
        case .media:
            if let currentURL, kind(of: currentURL) == .dm {
                let currentRouteURL = Self.routeURL(for: currentURL)
                lastDMURL = currentRouteURL
                return .allowMedia(returnURL: currentRouteURL)
            }
            return .block(returnURL: backToDMsURL())
        case .other:
            return .block(returnURL: backToDMsURL())
        }
    }

    public mutating func rememberIfDM(_ url: URL) {
        guard kind(of: url) == .dm else { return }
        lastDMURL = Self.routeURL(for: url)
    }

    public func backToDMsURL() -> URL {
        lastDMURL ?? homeURL
    }

    /// `nil` when the URL is not this channel's web surface: scheme not https, host
    /// not listed, credentials present, or a non-443 port.
    public func kind(of url: URL) -> RouteKind? {
        let channel = channelID.channel
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              channel.hosts.contains(host),
              url.user == nil,
              url.password == nil else { return nil }

        if let port = url.port, port != 443 {
            return nil
        }

        return channel.classify(path: Self.normalizedPath(url))
    }

    /// Strips credentials, port, query, and fragment and lowercases scheme and host.
    public static func routeURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.user = nil
        components.password = nil
        components.port = nil
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    private static func normalizedPath(_ url: URL) -> String {
        let path = url.path
        return path.isEmpty ? "/" : path
    }
}
```

- [ ] **Step 5: Rewrite `FirewallSurface`**

In `Packages/SidedoorCore/Sources/SidedoorCore/WebFirewall/FirewallSurface.swift`:

- Replace `private var routeFirewall = RouteFirewall()` with `private var routeFirewall: RouteFirewall`.
- Replace `public init() {}` with:

```swift
    public init(channel: ChannelID) {
        routeFirewall = RouteFirewall(channel: channel)
    }

    public var channelID: ChannelID { routeFirewall.channelID }
```

- In `decide(for:)`, the `.allow` case becomes just `screen = .web` (the guard was always true: `RouteFirewall` returns `.allow` only for auth and DM).
- In `observeCommittedURL`, `RouteFirewall.isDirectURL(url)` → `routeFirewall.kind(of: url) == .dm`, and `RouteFirewall.isAllowedAuthURL(url)` → `routeFirewall.kind(of: url) == .auth`.
- `reset()` becomes `self = FirewallSurface(channel: channelID)`.
- Doc comment: "Instagram mounts that component" → "a channel may mount such a component"; "the inline reels feed" → "an inline media feed". Keep the rest.

- [ ] **Step 6: Keep the app compiling (minimal edits, the rest comes in Task 5)**

In `App/Sources/WebFirewall/FirewallViewModel.swift`:

- `@Published private(set) var surface = FirewallSurface()` → `@Published private(set) var surface = FirewallSurface(channel: .instagram)`.
- `var homeURL: URL { RouteFirewall.inboxURL }` → `var homeURL: URL { surface.channelID.channel.homeURL }`.

- [ ] **Step 7: Run everything, lint, build, commit**

```bash
(cd Packages/SidedoorCore && swift test)
swiftlint --quiet
xcodebuild -project Sidedoor.xcodeproj -scheme Sidedoor \
  -destination 'platform=iOS Simulator,name=iPhone 17' build -quiet
```

Expected: all suites pass (the two rewritten suites now run once per channel); lint prints nothing; build exits 0.

```bash
git add Packages/SidedoorCore App/Sources/WebFirewall/FirewallViewModel.swift
git commit -m "Make RouteFirewall and FirewallSurface channel-aware

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---
### Task 4: `FirewallScript` in the package (increment 2a, part 3)

**Files:**
- Create: `Packages/SidedoorCore/Sources/SidedoorCore/WebFirewall/FirewallScript.swift`
- Test: `Packages/SidedoorCore/Tests/SidedoorCoreTests/FirewallScriptTests.swift`
- Modify: `Packages/SidedoorCore/Tests/SidedoorCoreTests/ChannelInvariantTests.swift`
- Delete: `App/Sources/WebFirewall/MinimalStyleInjector.swift`
- Modify (compile only): `App/Sources/WebFirewall/FirewallWebView.swift`

**Interfaces:** §5.5. `compose(for:)` returns one IIFE in four parts: prelude, hook, bridge, epilogue. `setUnreadFilterExpression(_:)` is the only Swift→JS call. `jsStringLiteral(_:)` and `observerInstall` are internal, visible to tests through `@testable`.

One detail the spec states loosely and this task pins: the unread `<style>` is appended to the document **first** and its `disabled` flag set **after**. Per the HTML standard, setting `disabled` on a style element whose sheet does not exist yet does nothing, and the sheet is created on insertion. Setting it before appending would leave the filter on from the first paint.

- [ ] **Step 1: Write the failing script tests**

Create `Packages/SidedoorCore/Tests/SidedoorCoreTests/FirewallScriptTests.swift`:

```swift
import Foundation
import Testing
@testable import SidedoorCore

/// Throwaway conformances: the protocol carries no identity, so a hookless channel
/// and a hostile-CSS channel are legitimate test doubles.
private struct TestChannel: Channel {
    var displayName = "Test"
    var hosts: Set<String> = ["example.com"]
    var homeURL = Self.constantURL("https://example.com/dm/")
    var webScript: ChannelWebScript
    func classify(path: String) -> RouteKind { .dm }
}

@Suite struct FirewallScriptTests {
    private let hook = """
    function lockInlineMedia() { window.__testLocked = true; }
    function inlineMediaState() { return 'present'; }
    """

    @Test func aHookedChannelGetsItsHookAndTheObserver() {
        let channel = TestChannel(webScript: ChannelWebScript(css: "nav {}", inlineMediaHook: hook))

        let script = FirewallScript.compose(for: channel)

        #expect(script.contains(hook))
        #expect(script.contains(FirewallScript.observerInstall))
        #expect(!script.contains(FirewallScript.defaultHook))
    }

    @Test func aHooklessChannelGetsTheNoOpDefaultsAndNoObserver() {
        let channel = TestChannel(webScript: ChannelWebScript(css: "nav {}"))

        let script = FirewallScript.compose(for: channel)

        #expect(script.contains(FirewallScript.defaultHook))
        #expect(!script.contains(FirewallScript.observerInstall))
        #expect(!script.contains("MutationObserver"))
    }

    @Test func theChannelCSSIsEmbeddedAsAJSStringLiteral() {
        let css = "a[href=\"/explore\"] { display: none !important; }"
        let channel = TestChannel(webScript: ChannelWebScript(css: css))

        let script = FirewallScript.compose(for: channel)

        #expect(script.contains(FirewallScript.jsStringLiteral(css)))
        #expect(script.contains("data-sidedoor"))
        #expect(script.contains("overscroll-behavior: contain"))
        #expect(script.contains("window.__sidedoorInstalled"))
    }

    @Test func sharedPiecesAreAlwaysPresent() {
        let channel = TestChannel(webScript: ChannelWebScript(css: ""))

        let script = FirewallScript.compose(for: channel)

        #expect(script.contains("messageHandlers.\(FirewallScript.routeMessageName).postMessage"))
        #expect(script.contains("messageHandlers.\(FirewallScript.mediaSurfaceMessageName).postMessage"))
        #expect(script.contains("history['pushState']") || script.contains("installHistoryObserver('pushState')"))
        #expect(script.contains("popstate"))
        #expect(script.contains("setInterval(scheduleSurfaceCheck, 500)"))
    }

    @Test func anUnreadFilterInstallsADisabledSecondStyleAndAWorkingToggle() {
        let css = "div[role=\"listitem\"]:not(:has(span[data-unread])) { display: none !important; }"
        let channel = TestChannel(webScript: ChannelWebScript(css: "", unreadFilterCSS: css))

        let script = FirewallScript.compose(for: channel)

        #expect(script.contains("data-sidedoor-unread"))
        #expect(script.contains(FirewallScript.jsStringLiteral(css)))
        #expect(script.contains("unreadStyle.disabled = !on"))
        #expect(!script.contains(FirewallScript.noOpUnreadFilter))
    }

    @Test func noUnreadFilterMeansNoSecondStyleAndANoOpToggle() {
        let channel = TestChannel(webScript: ChannelWebScript(css: ""))

        let script = FirewallScript.compose(for: channel)

        #expect(!script.contains("data-sidedoor-unread"))
        #expect(script.contains(FirewallScript.noOpUnreadFilter))
    }

    @Test func theUnreadFilterExpressionIsExact() {
        #expect(FirewallScript.setUnreadFilterExpression(true) == "window.__sidedoor.setUnreadFilter(true);")
        #expect(FirewallScript.setUnreadFilterExpression(false) == "window.__sidedoor.setUnreadFilter(false);")
    }

    @Test func jsStringLiteralEscapesEverythingThatCouldBreakTheScript() throws {
        let hostile = "a::before { content: \"`${x}` \\ \u{2028} </script>\"; }"

        let literal = FirewallScript.jsStringLiteral(hostile)

        // A JSON string literal is a valid JS string literal; decoding it back
        // proves nothing was lost or left unescaped.
        let decoded = try JSONDecoder().decode(String.self, from: Data(literal.utf8))
        #expect(decoded == hostile)
        #expect(literal.hasPrefix("\""))
        #expect(literal.hasSuffix("\""))
        #expect(!literal.contains("\n"))
    }
}
```

Add to `ChannelInvariantTests`:

```swift
    @Test(arguments: ChannelID.allCases)
    func composedScriptEmbedsTheChannelCSS(channelID: ChannelID) {
        let channel = channelID.channel
        let script = FirewallScript.compose(for: channel)

        #expect(script.contains(FirewallScript.jsStringLiteral(channel.webScript.css)))
        if let hook = channel.webScript.inlineMediaHook {
            #expect(script.contains(hook))
            #expect(script.contains(FirewallScript.observerInstall))
        } else {
            #expect(!script.contains(FirewallScript.observerInstall))
        }
    }
```

Run `swift test --filter FirewallScriptTests`. Expected: compile failure.

- [ ] **Step 2: Add `FirewallScript`**

Create `Packages/SidedoorCore/Sources/SidedoorCore/WebFirewall/FirewallScript.swift`:

```swift
import Foundation

/// Composes the user script the shell injects at document end in the main frame.
/// Shared parts (install guard, style injection, history hooks, the two message
/// posts, the scheduler, the presence timer) are here; the channel supplies CSS,
/// an optional inline-media hook, and an optional unread-filter stylesheet.
public enum FirewallScript {
    public static let routeMessageName = "routeChanged"
    public static let mediaSurfaceMessageName = "mediaSurfaceChanged"

    public static func compose(for channel: any Channel) -> String {
        let script = channel.webScript
        let parts = [
            "(function() {",
            prelude(css: script.css, unreadFilterCSS: script.unreadFilterCSS),
            script.inlineMediaHook ?? defaultHook,
            bridge,
            epilogue(installsObserver: script.inlineMediaHook != nil),
            "})();"
        ]
        return parts.joined(separator: "\n\n")
    }

    /// The one Swift→JS call in the app. Safe to evaluate on any page the script
    /// has run on: `setUnreadFilter` is always defined, as a no-op when the
    /// channel has no unread filter.
    public static func setUnreadFilterExpression(_ on: Bool) -> String {
        "window.__sidedoor.setUnreadFilter(\(on ? "true" : "false"));"
    }

    // MARK: - Parts

    static let defaultHook = """
    function lockInlineMedia() {}
    function inlineMediaState() { return 'absent'; }
    """

    static let noOpUnreadFilter = "window.__sidedoor = { setUnreadFilter: function() {} };"

    static let observerInstall = """
    // The inline feed mounts without a route change, so route notifications
    // alone would never catch it; the observer is what actually arms this.
    if (document.body) {
        new MutationObserver(scheduleSurfaceCheck).observe(document.body, {
            childList: true,
            subtree: true
        });
    }
    """

    /// JSON-encodes the string. A JSON string literal is a valid JS string
    /// literal, so backticks, backslashes, `${`, quotes, and U+2028/2029 in
    /// channel CSS cannot break out of the script.
    static func jsStringLiteral(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed]),
              let literal = String(data: data, encoding: .utf8) else {
            preconditionFailure("A Swift String is always JSON-encodable")
        }
        return literal
    }

    private static func prelude(css: String, unreadFilterCSS: String?) -> String {
        var lines = [
            "if (window.__sidedoorInstalled === true) {",
            "    return;",
            "}",
            "window.__sidedoorInstalled = true;",
            "",
            "const style = document.createElement('style');",
            "style.setAttribute('data-sidedoor', 'true');",
            "style.textContent = \(jsStringLiteral(css))",
            "    + '\\nbody { overscroll-behavior: contain !important; }';",
            "document.documentElement.appendChild(style);"
        ]

        if let unreadFilterCSS {
            lines += [
                "",
                "// Appended first, disabled second: a style element's disabled flag lives",
                "// on its sheet, which only exists once the element is in the document.",
                "const unreadStyle = document.createElement('style');",
                "unreadStyle.setAttribute('data-sidedoor-unread', 'true');",
                "unreadStyle.textContent = \(jsStringLiteral(unreadFilterCSS));",
                "document.documentElement.appendChild(unreadStyle);",
                "unreadStyle.disabled = true;",
                "window.__sidedoor = {",
                "    setUnreadFilter: function(on) {",
                "        unreadStyle.disabled = !on;",
                "    }",
                "};"
            ]
        } else {
            lines += ["", noOpUnreadFilter]
        }

        return lines.joined(separator: "\n")
    }

    private static let bridge = """
    // Presence is re-derived from the DOM on every pass rather than latched: a
    // page may unmount an inline feed, or leave it mounted and hide it, and only
    // one of those trips a childList observer. Hiding changes no child list, so
    // a slow timer covers it, running only while a locked surface exists.
    let lastReportedMediaSurface = null;
    let presenceTimer = null;
    let surfaceCheckScheduled = false;

    function startPresenceTimer() {
        if (presenceTimer !== null) {
            return;
        }
        presenceTimer = window.setInterval(scheduleSurfaceCheck, 500);
    }

    function stopPresenceTimer() {
        if (presenceTimer === null) {
            return;
        }
        window.clearInterval(presenceTimer);
        presenceTimer = null;
    }

    // A throw anywhere here skips the rest of the pass with no state, timer, or
    // deduplication change; the next mutation or tick simply retries.
    function runSurfaceCheck() {
        lockInlineMedia();
        const state = inlineMediaState();
        if (state === 'absent') {
            stopPresenceTimer();
        } else {
            startPresenceTimer();
        }

        const present = state === 'present';
        if (present === lastReportedMediaSurface) {
            return;
        }
        window.webkit.messageHandlers.mediaSurfaceChanged.postMessage(present);
        lastReportedMediaSurface = present;
    }

    function scheduleSurfaceCheck() {
        if (surfaceCheckScheduled) {
            return;
        }
        surfaceCheckScheduled = true;
        window.requestAnimationFrame(function() {
            surfaceCheckScheduled = false;
            try {
                runSurfaceCheck();
            } catch (error) {
                return;
            }
        });
    }

    function postRoute() {
        scheduleSurfaceCheck();
        try {
            window.webkit.messageHandlers.routeChanged.postMessage(window.location.href);
        } catch (error) {
            return;
        }
    }
    """

    private static func epilogue(installsObserver: Bool) -> String {
        let history = """
        function installHistoryObserver(methodName) {
            const original = history[methodName];
            history[methodName] = function() {
                const result = original.apply(this, arguments);
                window.setTimeout(postRoute, 0);
                return result;
            };
        }

        installHistoryObserver('pushState');
        installHistoryObserver('replaceState');
        window.addEventListener('popstate', postRoute);
        window.setTimeout(postRoute, 0);
        """
        return installsObserver ? history + "\n\n" + observerInstall : history
    }
}
```

- [ ] **Step 3: Point the app at the package script and delete the injector**

```bash
git rm App/Sources/WebFirewall/MinimalStyleInjector.swift
sed -i '' 's/MinimalStyleInjector\.routeMessageName/FirewallScript.routeMessageName/g; s/MinimalStyleInjector\.mediaSurfaceMessageName/FirewallScript.mediaSurfaceMessageName/g' \
  App/Sources/WebFirewall/FirewallWebView.swift
```

Then in `FirewallWebView.makeUIView`, replace `WKUserScript(source: MinimalStyleInjector.source,` with `WKUserScript(source: FirewallScript.compose(for: ChannelID.instagram.channel),`. (Task 5 moves this onto the model.)

- [ ] **Step 4: Test, lint, regenerate, build, commit**

```bash
(cd Packages/SidedoorCore && swift test)
swiftlint --quiet
xcodegen generate
xcodebuild -project Sidedoor.xcodeproj -scheme Sidedoor \
  -destination 'platform=iOS Simulator,name=iPhone 17' build -quiet
```

Expected: green, clean, exit 0. `xcodegen generate` is needed because a source file was removed.

Device sanity check (optional but recommended, since this is the first change to the injected JS): install the DEBUG build on the phone, open a DM with a shared reel, confirm the media banner appears and the feed does not scroll, and confirm in Web Inspector's console that `window.__sidedoorInstalled === true` and `typeof window.__sidedoor.setUnreadFilter === 'function'`.

```bash
git add -A
git commit -m "Move script composition into SidedoorCore as FirewallScript

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---
### Task 5: Per-channel app shell (increment 2b)

**Files:**
- Create: `App/Sources/WebFirewall/ChannelStore.swift`
- Create: `App/Sources/WebFirewall/ChannelRootView.swift`
- Create: `App/Sources/WebFirewall/LegacyDataStoreCleanup.swift`
- Move: `App/Sources/WebFirewall/WebFirewallRootView.swift` → `App/Sources/WebFirewall/ChannelScreen.swift`
- Modify: `FirewallViewModel.swift`, `FirewallWebView.swift`, `BlockedContentView.swift`, `SettingsView.swift`, `RootView.swift`, `SidedoorApp.swift`

**Interfaces:** §6.2 through §6.10. With one channel in the registry the root shows `ChannelScreen` alone; the `TabView` branch exists but is not exercised until Task 8's probe build adds a second case. The unread toggle is wired but hidden because Instagram's `unreadFilterCSS` is nil until Task 7.

No package changes, so there is no new `swift test` coverage here; the gate is the build plus the manual checklist in Task 6.

- [ ] **Step 1: `FirewallViewModel`**

Replace the whole of `App/Sources/WebFirewall/FirewallViewModel.swift`:

```swift
import Combine
import Foundation
import SidedoorCore
import WebKit

/// Thin observable wrapper over `FirewallSurface` for one channel. Everything that
/// decides *what* the shell shows lives in `SidedoorCore`; this holds only what
/// needs a main actor and a WebView: loading state, the pending load, the data
/// store, the unread-filter preference, and a weak handle to the WebView so the
/// root can pause media when the channel stops being active.
@MainActor
final class FirewallViewModel: ObservableObject {
    let channel: ChannelID
    let dataStore: WKWebsiteDataStore
    let scriptSource: String

    @Published private(set) var surface: FirewallSurface
    @Published var isLoading = false
    @Published var reloadToken = UUID()
    @Published private(set) var isUnreadFilterOn: Bool

    /// Set by `FirewallWebView.makeUIView`, cleared by `dismantleUIView`.
    weak var webView: WKWebView?

    private var pendingLoadURL: URL?
    private let unreadFilterKey: String

    init(channel: ChannelID) {
        self.channel = channel
        surface = FirewallSurface(channel: channel)
        dataStore = WKWebsiteDataStore(forIdentifier: channel.webStoreIdentifier)
        scriptSource = FirewallScript.compose(for: channel.channel)

        let key = "unreadFilter.\(channel.rawValue)"
        unreadFilterKey = key
        isUnreadFilterOn = UserDefaults.standard.bool(forKey: key)
    }

    var displayName: String { channel.channel.displayName }

    var homeURL: URL { channel.channel.homeURL }

    /// Where a freshly built WebView starts: the last DM route, or home. Read by
    /// `makeUIView` only; a channel switch never rebuilds the WebView.
    var resumeURL: URL { surface.backToDMsURL() }

    var offersUnreadFilter: Bool { channel.channel.webScript.unreadFilterCSS != nil }

    var screen: FirewallScreenState { surface.screen }

    var showsBackToDMs: Bool { surface.showsBackToDMs }

    func decision(for targetURL: URL) -> RouteDecision {
        let decision = surface.decide(for: targetURL)
        if case .block = decision {
            isLoading = false
        }
        return decision
    }

    func observeCommittedURL(_ url: URL) {
        surface.observeCommittedURL(url)
    }

    func observeInlineMediaSurface(isPresent: Bool) {
        surface.observeInlineMediaSurface(isPresent: isPresent)
    }

    func fail(_ error: Error) {
        isLoading = false
        guard !error.isNavigationCancellation else { return }
        surface.fail(error.localizedDescription)
    }

    func backToDMs() {
        load(surface.backToDMsURL())
    }

    func reloadHome() {
        load(homeURL)
    }

    func consumePendingLoadURL() -> URL? {
        let url = pendingLoadURL
        pendingLoadURL = nil
        return url
    }

    /// Stops audio and video in this channel's page. The only thing the app does
    /// to a channel that is no longer the active tab.
    func pauseMedia() {
        webView?.pauseAllMediaPlayback(completionHandler: nil)
    }

    func setUnreadFilter(_ isOn: Bool) {
        isUnreadFilterOn = isOn
        UserDefaults.standard.set(isOn, forKey: unreadFilterKey)
        applyUnreadFilter()
    }

    /// A full navigation reinstalls the user script with the filter off, so the
    /// stored preference is re-applied when the page finishes loading.
    func reapplyUnreadFilterIfOn() {
        guard isUnreadFilterOn else { return }
        applyUnreadFilter()
    }

    func logout() {
        isLoading = true
        dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                             modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                self.pendingLoadURL = nil
                self.surface.reset()
                self.reloadToken = UUID()
            }
        }
    }

    private func applyUnreadFilter() {
        // The only Swift→JS call in the app. An error is ignored on purpose: before
        // the user script has run there is no `__sidedoor` yet, and `didFinish`
        // re-applies the stored preference.
        webView?.evaluateJavaScript(FirewallScript.setUnreadFilterExpression(isUnreadFilterOn),
                                    completionHandler: nil)
    }

    private func load(_ url: URL) {
        pendingLoadURL = url
        isLoading = true
        surface.prepareLoad()
    }
}

private extension Error {
    var isNavigationCancellation: Bool {
        let error = self as NSError
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
            return true
        }

        // WebKit also reports policy-cancelled loads as WebKitErrorDomain code 102.
        return error.domain == WKErrorDomain && error.code == 102
    }
}
```

- [ ] **Step 2: `FirewallWebView`**

In `App/Sources/WebFirewall/FirewallWebView.swift`:

- Remove `let reloadToken: UUID` and the coordinator's `var reloadToken: UUID?`; the view is keyed by `.id(model.reloadToken)` from the screen, so a token change always goes through `makeUIView`.
- `makeUIView`:
  - `configuration.websiteDataStore = model.dataStore`
  - after the media settings: `configuration.defaultWebpagePreferences.preferredContentMode = .mobile` with the comment `// Every device gets the surface that was measured; WebKit's default serves desktop web on most iPads (§6.10).`
  - `WKUserScript(source: model.scriptSource, ...)`
  - after `context.coordinator.webView = webView`: `model.webView = webView`
  - `webView.load(URLRequest(url: model.resumeURL))`
- `updateUIView` keeps only the model refresh and the pending-load branch:

```swift
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.model = model

        if let requestedURL = model.consumePendingLoadURL() {
            webView.load(URLRequest(url: requestedURL))
        }
    }
```

- `dismantleUIView` adds, before the handler removal:

```swift
        // The replacement WebView may already have registered itself.
        if coordinator.model.webView === webView {
            coordinator.model.webView = nil
        }
```

- Coordinator `didFinish` gains, after `observeCommittedURL`: `model.reapplyUnreadFilterIfOn()`.

Everything else in the coordinator is unchanged.

- [ ] **Step 3: `ChannelStore` and `LegacyDataStoreCleanup`**

Create `App/Sources/WebFirewall/ChannelStore.swift`:

```swift
import Combine
import SidedoorCore

/// One `FirewallViewModel` per channel, created lazily and kept for the life of
/// the process so a channel's page is exactly where the user left it. The cache
/// is a plain dictionary on purpose: `model(for:)` is called from `body`, and
/// publishing from there is a SwiftUI runtime warning.
@MainActor
final class ChannelStore: ObservableObject {
    private var models: [ChannelID: FirewallViewModel] = [:]

    func model(for channel: ChannelID) -> FirewallViewModel {
        if let model = models[channel] {
            return model
        }
        let model = FirewallViewModel(channel: channel)
        models[channel] = model
        return model
    }
}
```

Create `App/Sources/WebFirewall/LegacyDataStoreCleanup.swift`:

```swift
import Foundation
import WebKit

/// Before channels had their own stores, the app used `WKWebsiteDataStore.default()`.
/// A session left there by an older build could never be cleared by a per-channel
/// logout, so it is wiped once. Harmless on a fresh install.
enum LegacyDataStoreCleanup {
    private static let completedKey = "didClearDefaultWebsiteDataStore"

    @MainActor
    static func runIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: completedKey) else { return }
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                modifiedSince: .distantPast) {
            UserDefaults.standard.set(true, forKey: completedKey)
        }
    }
}
```

In `App/Sources/SidedoorApp.swift`, add `LegacyDataStoreCleanup.runIfNeeded()` as the first line of `init()`.

- [ ] **Step 4: `ChannelRootView`**

Create `App/Sources/WebFirewall/ChannelRootView.swift`:

```swift
import SidedoorCore
import SwiftUI

/// Owns the active channel and the store. With one channel it shows that
/// channel's screen alone; with more it is a system tab bar, one tab per channel,
/// every tab kept alive so a switch shows the other page where it was.
struct ChannelRootView: View {
    @StateObject private var store = ChannelStore()
    @AppStorage("activeChannel") private var activeChannelRawValue = ChannelID.instagram.rawValue

    private var activeChannel: ChannelID {
        ChannelID(rawValue: activeChannelRawValue) ?? .instagram
    }

    private var selection: Binding<ChannelID> {
        Binding(
            get: { activeChannel },
            set: { activeChannelRawValue = $0.rawValue }
        )
    }

    var body: some View {
        if ChannelID.allCases.count == 1 {
            ChannelScreen(model: store.model(for: activeChannel), logout: logout)
        } else {
            TabView(selection: selection) {
                ForEach(ChannelID.allCases, id: \.self) { channel in
                    ChannelScreen(model: store.model(for: channel), logout: logout)
                        .tabItem {
                            Label(channel.channel.displayName, systemImage: Self.symbolName(for: channel))
                        }
                        .tag(channel)
                }
            }
            .onChange(of: activeChannel) { previous, _ in
                // Audio from the outgoing channel must not keep playing under the
                // other tab. Nothing else happens on a switch (§6.7).
                store.model(for: previous).pauseMedia()
            }
        }
    }

    private func logout(_ channel: ChannelID) {
        store.model(for: channel).logout()
    }

    /// Exhaustive on purpose: a new channel does not compile until it has an icon.
    private static func symbolName(for channel: ChannelID) -> String {
        switch channel {
        case .instagram:
            "camera"
        }
    }
}

#Preview {
    ChannelRootView()
}
```

Replace the body of `App/Sources/RootView.swift` so it returns `ChannelRootView()`.

- [ ] **Step 5: `ChannelScreen`**

```bash
git mv App/Sources/WebFirewall/WebFirewallRootView.swift App/Sources/WebFirewall/ChannelScreen.swift
```

Then edit `ChannelScreen.swift`:

- `import IGCore` is already `import SidedoorCore` from Task 1. Rename the struct to `ChannelScreen`; replace `@StateObject private var model = FirewallViewModel()` with:

```swift
    @ObservedObject var model: FirewallViewModel
    let logout: (ChannelID) -> Void
```

- In `body`, after `.sheet(...)`, add:

```swift
        // While blocked the screen offers exactly one action, Back to DMs; the
        // tab bar would be a second. No-op when there is no tab bar.
        .toolbarVisibility(isBlocked ? .hidden : .automatic, for: .tabBar)
```

  and add `private var isBlocked: Bool { if case .blocked = model.screen { true } else { false } }`.

- The sheet becomes `SettingsView(logout: logout)`.
- In `topBar`: `Text("Sidedoor")` → `Text(model.displayName)`. Between the title `VStack` and the `Spacer()` add nothing; after the `Spacer()` and before the gear button add the toggle:

```swift
            if model.offersUnreadFilter, case .web = model.screen {
                Button {
                    model.setUnreadFilter(!model.isUnreadFilterOn)
                } label: {
                    Label("Unread", systemImage: model.isUnreadFilterOn ? "envelope.badge.fill" : "envelope.badge")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .tint(model.isUnreadFilterOn ? Color.accentColor : Color.secondary)
                .accessibilityLabel("Show unread only")
                .accessibilityValue(model.isUnreadFilterOn ? "On" : "Off")
                .accessibilityAddTraits(.isToggle)
            }
```

- Blocker: `BlockedContentView(displayName: model.displayName) { model.backToDMs() }`.
- Loading: `.accessibilityLabel("Loading \(model.displayName)")`.
- Error view: `Text("Couldn't load \(model.displayName)")`, `Text("Check your connection, then reload \(model.displayName) DMs.")`, and the Reload button calls `model.reloadHome()`.
- Preview: `#Preview { ChannelScreen(model: FirewallViewModel(channel: .instagram), logout: { _ in }) }`.

- [ ] **Step 6: `BlockedContentView` and `SettingsView`**

In `BlockedContentView.swift` add `let displayName: String` above `let backToDMs`, and the headline becomes `Text("This \(displayName) route is blocked")`. The body text from Task 1 stays.

Replace the whole of `App/Sources/WebFirewall/SettingsView.swift`:

```swift
import Foundation
import SidedoorCore
import SwiftUI

struct SettingsView: View {
    let logout: (ChannelID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var channelToLogOut: ChannelID?

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    ForEach(ChannelID.allCases, id: \.self) { channel in
                        Button(role: .destructive) {
                            channelToLogOut = channel
                        } label: {
                            Label("Log Out of \(channel.channel.displayName)",
                                  systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .accessibilityHint("Clears \(channel.channel.displayName) website data stored by this app")
                    }
                }

                Section("Privacy") {
                    Text(
                        "Each network handles login and DMs inside its own web page. "
                            + "Sidedoor blocks routes locally and does not read messages, "
                            + "extract cookies, or store content."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("About") {
                    Text("Sidedoor loads a network's web DMs and blocks distracting routes locally.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    LabeledContent("Version", value: versionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Log out of \(channelToLogOut?.channel.displayName ?? "") in this app?",
                isPresented: Binding(
                    get: { channelToLogOut != nil },
                    set: { if !$0 { channelToLogOut = nil } }
                ),
                titleVisibility: .visible,
                presenting: channelToLogOut
            ) { channel in
                Button("Log Out", role: .destructive) {
                    dismiss()
                    logout(channel)
                }

                Button("Cancel", role: .cancel) {}
            } message: { channel in
                Text("This clears this app's \(channel.channel.displayName) cookies and website data, "
                     + "then returns that channel to login. Other channels are untouched.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}
```

- [ ] **Step 7: Regenerate, lint, build, commit**

```bash
xcodegen generate
swiftlint --quiet
(cd Packages/SidedoorCore && swift test)
xcodebuild -project Sidedoor.xcodeproj -scheme Sidedoor \
  -destination 'platform=iOS Simulator,name=iPhone 17' build -quiet
grep -rn "WebFirewallRootView\|reloadInstagram\|MinimalStyleInjector\|WKWebsiteDataStore.default()" App/Sources
```

Expected: lint clean, tests green, build exits 0, and the grep finds only the one `.default()` call inside `LegacyDataStoreCleanup.swift`.

```bash
git add -A
git commit -m "Per-channel app shell: ChannelStore, ChannelRootView, ChannelScreen

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---
### Task 6: Fresh device install and README for 2b

**Files:**
- Modify: `README.md`

This is the first build with the new bundle ID and per-channel data store, so it is a fresh install and the one Instagram re-login (§2). Nothing migrates.

- [ ] **Step 1: README layout and checklist**

In `README.md`:

- Layout block, `App/Sources/` line: `SwiftUI shell + WKWebView route firewall, one screen per channel (UI/device layer)`. Add under `Packages/SidedoorCore/Sources/SidedoorCore/` two indented lines: `Channel/   Channel protocol, ChannelID registry, InstagramChannel` and `WebFirewall/   RouteFirewall, FirewallSurface, FirewallScript`.
- Replace the "Manual WebView firewall checks" section with:

```markdown
## Manual firewall checks

Run once per channel after launching the app:

1. The app opens the channel's DM home inside the native shell.
2. Login / 2FA / checkpoint flows remain usable inside the WebView.
3. DM read and send work through the network's own web UI.
4. Tapping media from a DM opens media mode.
5. `Back to DMs` returns to the originating thread or inbox.
6. Feed, explore, search, profile, and discovery routes show the local blocker.
7. Settings → Log Out of <network> clears only that channel's WebKit data and
   returns it to login.

With more than one channel installed, also verify:

8. Switching channels shows each page exactly where it was, with no reload.
9. Audio from a playing video stops when you switch away.
10. The tab bar disappears while a channel is blocked and returns after Back to DMs.
11. The web content ends above the tab bar.
12. The Unread toggle hides read threads, survives a relaunch, and turning it off
    restores every row.
13. Logging out of one channel leaves the other signed in.
```

- [ ] **Step 2: Install on the phone and run checks 1–7 for Instagram**

```bash
xcodebuild -project Sidedoor.xcodeproj -scheme Sidedoor \
  -destination 'platform=iOS,id=52919ACD-52A5-5FD6-B5C8-54F1A3A1191E' build -quiet
```

Then run from Xcode on the device (or `xcrun devicectl device install app` with the built `.app`). Delete the old Minimal Instagram app from the home screen. Expected: the home screen shows "Sidedoor"; the Instagram login appears; after login, checks 1–7 pass exactly as before the rename. Record anything that differs in the commit message rather than fixing it silently.

Expected on this first launch: `LegacyDataStoreCleanup` runs and sets its flag. There is nothing visible to check; that is fine.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document per-channel manual checks

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Instagram unread filter, measured first (increment 2c)

**Files:**
- Create: `docs/Instagram Web Inbox — Unread Marker (<date>).md`
- Modify: `Packages/SidedoorCore/Sources/SidedoorCore/Channel/Channels/InstagramChannel.swift`
- Modify: `Packages/SidedoorCore/Tests/SidedoorCoreTests/InstagramChannelTests.swift`

**What is known today:** nothing about the inbox row or unread marker DOM. No selector in this task is written until Step 1 has recorded it. The CSS in Step 3 is a shape, not a value.

- [ ] **Step 1: Measure with Web Inspector**

With the Task 6 DEBUG build on the phone, the inbox open, and at least one unread thread (send yourself a message from another account, or wait for one):

1. Safari on the Mac → Develop → Sri's iPhone → Sidedoor → the instagram.com page.
2. In Elements, select one inbox row that is unread and one that is read. For each, record: the tag and role of the row element; its ancestors up to the list container (tags, roles, `aria-*` attributes, whether class names look hashed); and every child that exists on the unread row but not the read row (tag, role, `aria-label` text shape, computed `background-color`, `width`, `height`). Do not record usernames, thread IDs, message previews, or hrefs beyond their path shape.
3. In the console, confirm the candidate selector matches only unread rows: `document.querySelectorAll('<row>:has(<marker>)').length` against the count you can see, and `document.querySelectorAll('<row>').length` against the visible row count. Record both numbers as counts, nothing else.
4. Mark the unread thread as read inside the page and re-run the counts. Record whether the marker element is removed or hidden (and if hidden, by which computed property).
5. Record `document.title` on the inbox and inside a thread, with the unread count present and absent, as a shape like `"(N) Instagram"`, never the value (§8.2 item 11; gates D7).
6. Record whether the inbox offers a native unread filter or URL parameter (§6.11).

Write `docs/Instagram Web Inbox — Unread Marker (<date>).md` with sections **Measured**, **Inferred**, **Open**, plus device model, iOS version, app build, date. Follow the diagnostics redaction rule: DOM shape, counts, route category, status only.

If Step 1 finds no stable structural or style signature (only hashed class names with nothing else to hang on), record that under Measured, leave `unreadFilterCSS` nil, commit the document alone, and stop this task. The toggle stays hidden.

- [ ] **Step 2: Write the failing test from the measurement**

In `InstagramChannelTests.identity`, change `#expect(channel.webScript.unreadFilterCSS == nil)` to `!= nil`, and add:

```swift
    @Test func unreadFilterHidesRowsWithoutTheMeasuredMarker() throws {
        let css = try #require(channel.webScript.unreadFilterCSS)
        #expect(css.contains(":not(:has("))
        #expect(css.contains("display: none !important"))
    }
```

- [ ] **Step 3: Write the CSS from the document**

In `InstagramChannel`, replace `unreadFilterCSS: nil` with `unreadFilterCSS: Self.unreadFilterCSS` and add, with the selectors copied from the Measured section and a comment citing the document by filename:

```swift
    // Measured in docs/Instagram Web Inbox — Unread Marker (<date>).md.
    static let unreadFilterCSS = """
    <row selector>:not(:has(<marker selector>)) {
        display: none !important;
    }
    """
```

Prefer role, `aria-*`, and structural selectors over hashed class names, as the feed lock does. If the only signature is a computed style (say, the marker is a dot with a specific background), `:has()` cannot select on computed style; record that under Open and pick the nearest structural ancestor that exists only on unread rows, or leave it nil.

- [ ] **Step 4: Verify on device, then commit**

```bash
(cd Packages/SidedoorCore && swift test)
swiftlint --quiet
xcodebuild -project Sidedoor.xcodeproj -scheme Sidedoor \
  -destination 'platform=iOS,id=52919ACD-52A5-5FD6-B5C8-54F1A3A1191E' build -quiet
```

On the phone: the Unread toggle appears in the top bar on the inbox; on: only unread rows remain; read a thread and return: that row is gone; off: every row is back; relaunch with it on: still on after the page loads (this exercises the `didFinish` re-apply); pull-to-refresh or a full reload keeps it on. Record any deviation in the document's Open section.

```bash
git add docs Packages/SidedoorCore
git commit -m "Instagram unread-only filter from measured inbox markup

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: TikTok DM surface probe (increment 3)

**Files (scratch branch `probe/tiktok-dm-surface`; only the document merges):**
- Create: `Packages/SidedoorCore/Sources/SidedoorCore/Channel/Channels/TikTokChannel.swift` (throwaway)
- Modify: `ChannelID.swift`, `ChannelRootView.swift` (throwaway)
- Create: `docs/TikTok Web DM Surface — Recon Findings (<date>).md` (merges)

**Preconditions:** a secondary TikTok account (§8.1), never the main one. Note in the document whether the TikTok native app is installed on the phone.

- [ ] **Step 1: Coarse check in mobile Safari**

On the phone, in Safari, open `https://www.tiktok.com/messages` logged out, then log in with the secondary account. Record §8.2 item 1: DM UI, login wall, app interstitial, or redirect, and to where. This is a coarse check only; `WKWebView`'s user agent differs from Safari's.

- [ ] **Step 2: Throwaway channel on the scratch branch**

```bash
git checkout -b probe/tiktok-dm-surface develop
```

Create `TikTokChannel.swift`, permissive on purpose:

```swift
import Foundation

/// PROBE ONLY. Classifies everything as `.dm` so the firewall never blocks and the
/// page can be measured. Never merges.
public struct TikTokChannel: Channel {
    public init() {}
    public var displayName: String { "TikTok" }
    public static let hosts: Set<String> = ["tiktok.com", "www.tiktok.com", "m.tiktok.com"]
    public var hosts: Set<String> { Self.hosts }
    public static let homeURL = Self.constantURL("https://www.tiktok.com/messages")
    public var homeURL: URL { Self.homeURL }
    public func classify(path: String) -> RouteKind { .dm }
    public var webScript: ChannelWebScript { ChannelWebScript(css: "") }
}
```

Add `case tiktok` to `ChannelID` with `TikTokChannel()` and the reserved identifier `7075CEAF-1541-4FDB-990D-E2E001D409CA`; add `case .tiktok: "music.note"` to `symbolName(for:)`. `ChannelURLs.fixture(for:)` needs a `.tiktok` case to compile: return the Instagram fixture with a comment `// probe placeholder` (the parametrized firewall tests will fail for TikTok on this branch; that is expected and is why the branch never merges). Build to the phone.

- [ ] **Step 3: Measure, items 2–11**

With Web Inspector attached, work through §8.2 in order and write each finding into the document as you go, under Measured, Inferred, or Open:

2. What the app's WebView shows at `/messages`.
3. Route shapes: inbox, open thread, login, signup, captcha, verification, logout, first-load redirect. Path shapes and query *keys* only.
4. A shared video in a DM: navigates (to what path shape), mounts inline, or opens a modal; whether the next video changes the URL.
5. Any full-bleed video container: computed `overflow-y` and `scroll-snap-type` on `<video>` ancestors; whether items carry a permalink.
6. Interstitials and overlays: DOM shape, whether they block interaction.
7. Media playback under the shared configuration: plays, with audio.
8. Anti-bot: captcha, when, recurrence across relaunch.
9. Only if mobile web shows no DM surface: repeat 2–8 with `preferredContentMode = .desktop` (a one-line change in `FirewallWebView` on this branch) and record `navigator.userAgent` under both modes.
10. Unread marker: row and marker DOM shape, native unread filter or URL parameter.
11. `document.title` shape on inbox and thread, with and without unread.

This task also performs the two on-device checks §6.7 and §6.3 defer to the first two-tab build, since this is the first: switching back to a tab does not call `makeUIView` again (set a breakpoint or add a temporary `print` on the branch), and the tab bar hides while a channel is blocked. Record both results; if the first fails, the fallback in §6.7 becomes a task in the increment-4 plan.

- [ ] **Step 4: Record D1–D5 and the D6/D7 inputs**

At the end of the document, one line per decision (§8.4), each stating what was measured and what it implies. D5 first: if login loops, a recurring captcha, or an un-dismissable app push appear, write "cannot ship under §3" and stop; no user-agent strings, no automation. D1 is the user's decision if mobile web shows no DMs; write the measured facts and leave the decision line for them.

- [ ] **Step 5: Merge only the document**

```bash
git add "docs/TikTok Web DM Surface — Recon Findings ("*").md"
git commit -m "TikTok web DM surface recon findings

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git checkout develop
git checkout probe/tiktok-dm-surface -- "docs/TikTok Web DM Surface — Recon Findings ("*").md"
git commit -am "Add TikTok recon findings

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

The scratch branch stays local with its throwaway code. The increment-4 plan is written from this document.

---

## Plan Self-Review

Spec coverage:

- §2 rename inventory: Task 1, every row, plus the signing correction noted at the top.
- §5.2 types, §5.6 Instagram: Task 2. §5.3, §5.4: Task 3. §5.5: Task 4.
- §6.2–6.10: Task 5. §6.11: Task 4 (script side), Task 5 (toggle, wired but hidden), Task 7 (Instagram CSS from measurement).
- §6.6 one-time cleanup: Task 5, `LegacyDataStoreCleanup`.
- §8 probe: Task 8, with the two deferred on-device checks from §6.3 and §6.7.
- §9 TikTok channel: out of this plan by design; written from the Task 8 document.
- §13.1 suites: `InstagramChannelTests`, `ChannelInvariantTests` (Tasks 2, 4), `ChannelURLs`, `RouteFirewallTests`, `FirewallSurfaceTests` (Task 3), `FirewallScriptTests` (Task 4). §13.2: Task 6 checklist, run in Tasks 6 and 7.

Type consistency:

- `ChannelID.channel`, `.webStoreIdentifier` (Task 2) are used by `RouteFirewall.homeURL`/`kind(of:)` (Task 3) and `FirewallViewModel.init` (Task 5).
- `FirewallSurface.channelID` (Task 3) is used by the Task 3 compile-only edit and by the reset test.
- `FirewallScript.compose(for:)`, `.setUnreadFilterExpression(_:)`, `.routeMessageName`, `.mediaSurfaceMessageName` (Task 4) are used by `FirewallWebView` and `FirewallViewModel` (Task 5). `observerInstall`, `defaultHook`, `noOpUnreadFilter`, `jsStringLiteral` are internal and reached through `@testable`.
- `ChannelWebScript.init(css:inlineMediaHook:unreadFilterCSS:)` defaults let the test doubles pass only `css`.
- `ChannelScreen(model:logout:)` and `SettingsView(logout:)` share the `(ChannelID) -> Void` shape; `ChannelRootView.logout(_:)` supplies it.

Things this plan does not assert as fact:

- Whether `TabView` creates unselected tabs eagerly: measured in Task 8.
- Any TikTok route, DOM shape, or anti-bot behavior: measured in Task 8.
- Instagram's inbox row and unread marker: measured in Task 7.
- That WebKit's `disabled` flag on a detached `<style>` is a no-op is from the HTML standard, not from a device measurement; the Task 4 device sanity check and the Task 7 toggle check cover it in practice.

Validation commands:

- `cd Packages/SidedoorCore && swift test`
- `swiftlint --quiet`
- `xcodegen generate`
- `xcodebuild -project Sidedoor.xcodeproj -scheme Sidedoor -destination 'platform=iOS Simulator,name=iPhone 17' build -quiet`
