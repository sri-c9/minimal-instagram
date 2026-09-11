# Sidedoor

A relationship-first, "attention firewall" iOS app for social DMs. V1 loads
Instagram's official web DM surface in a local `WKWebView`, blocks
distracting routes like feed/explore/reels/search, and allows media only when it
is opened from a DM. No private Instagram API, session extraction, backend
bridge, polling, or message scraping is part of the V1 app flow.

## Instagram ToS / account-safety posture

This is not legal advice, but the working interpretation for this project is:

- Official Instagram Terms of Use: https://help.instagram.com/581066165581870
- The relevant section is **4.2 — How You Can't Use Instagram**.
- A personal, WebView-only wrapper that lets the user manually log into
  Instagram's official web UI is the lowest-risk version of this idea, though not
  zero-risk.
- The WebView route firewall / local CSS-JS injection is a gray area: it only
  changes the local user experience, but Instagram's terms broadly restrict
  modifying, interfering with, or impairing the intended operation of the service.
- Programmatic access is out of scope for the V1 app flow. In particular, private
  Instagram APIs, extracted cookies/session tokens, mobile-header spoofing,
  scraping/parsing DMs outside the WebView, background polling, or automated sends
  should be treated as likely ToS-violating and materially higher account-risk.
- The app must not collect credentials, export private DM data, share accounts or
  access tokens, bypass checkpoints/rate limits, or distribute this as a general
  third-party Instagram client.
- Instagram's "new login" notification showing `Apple iPhone · Mobile Safari
  WebView` is expected for a first run in `WKWebView`; it is not by itself
  evidence of a ToS violation.

See `docs/` for the product and technical design.

## Layout

```
project.yml            XcodeGen manifest — source of truth for the app project (.xcodeproj is generated)
.swiftlint.yml         Lint config (governs App + SidedoorCore)
App/
  Sources/             SwiftUI shell + WKWebView route firewall, one screen per channel (UI/device layer)
  Resources/           Assets.xcassets
Packages/
  SidedoorCore/        Pure, UI-free logic — testable via `swift test`, no simulator
    Sources/SidedoorCore/
      Channel/         Channel protocol, ChannelID registry, InstagramChannel
      WebFirewall/     RouteFirewall, FirewallSurface, FirewallScript
    Tests/SidedoorCoreTests/
docs/                  Product + technical design (copied from the Obsidian vault)
```

`SidedoorCore` is a Swift Package that must never import SwiftUI/UIKit/WebKit. It
holds pure logic such as DTO mapping and route policy tests. The app target owns
the actual `WKWebView` and native SwiftUI shell.

## Requirements

- Xcode 26+ (iOS 26 SDK), Swift 6
- `xcodegen` and `swiftlint` (`brew install xcodegen swiftlint`)

## Common commands

```bash
# Run the fast logic tests (no simulator):
cd Packages/SidedoorCore && swift test

# (Re)generate the Xcode project from project.yml:
xcodegen generate

# Build the app for the simulator:
xcodebuild -project Sidedoor.xcodeproj -scheme Sidedoor \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Lint:
swiftlint
```

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

Open `Sidedoor.xcodeproj` in Xcode to run on a device/simulator. After adding a
brand-new source file, run `xcodegen generate` so it joins the project. For
device builds, put your team ID in `Signing.local.xcconfig` (gitignored; see the
comment in `Signing.xcconfig`).
