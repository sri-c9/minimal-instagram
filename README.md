# Minimal Instagram

A relationship-first, "attention firewall" iOS client over Instagram — DMs and
friend-shared reels only. No feed, explore, or recommendations. Single-user (the
author's own account) for V1.

See `docs/` for the product and technical design.

## Layout

```
project.yml            XcodeGen manifest — source of truth for the app project (.xcodeproj is generated)
.swiftlint.yml         Lint config (governs App + IGCore)
App/
  Sources/             SwiftUI app shell, WKWebView auth, AVPlayer reel viewer (UI/device layer)
  Resources/           Assets.xcassets
Packages/
  IGCore/              Pure, UI-free logic — testable via `swift test`, no simulator
    Sources/IGCore/
    Tests/IGCoreTests/
docs/                  Product + technical design (copied from the Obsidian vault)
```

`IGCore` is a Swift Package that must never import SwiftUI/UIKit. That package
boundary is what structurally enforces the design's firewall rule (pure mapper,
one-way dependencies). Components are added test-first.

**Intended `IGCore` structure** (created as each component is built, test-first):
`Session/` · `Client/` · `Mapper/` · `Repository/` · `Media/` · `Models/`.

## Requirements

- Xcode 26+ (iOS 26 SDK), Swift 6
- `xcodegen` and `swiftlint` (`brew install xcodegen swiftlint`)

## Common commands

```bash
# Run the fast logic tests (no simulator):
cd Packages/IGCore && swift test

# (Re)generate the Xcode project from project.yml:
xcodegen generate

# Build the app for the simulator:
xcodebuild -project MinimalInstagram.xcodeproj -scheme MinimalInstagram \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Lint:
swiftlint
```

Open `MinimalInstagram.xcodeproj` in Xcode to run on a device/simulator. After
adding a brand-new source file, run `xcodegen generate` so it joins the project.
On first device run, select your personal team under Signing & Capabilities.
