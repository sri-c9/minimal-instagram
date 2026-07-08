# WebView Firewall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static launch screen with an iOS WebView-based Instagram DM firewall: Instagram web owns auth/DMs, while the app enforces local navigation blocking and minimal distraction cleanup.

**Architecture:** Keep the route policy pure and tested in `IGCore`; keep all `WKWebView`/SwiftUI code in the app target. The app uses a native SwiftUI shell around a persistent `WKWebView`, blocks disallowed main-frame navigations, allows DM-opened media in a strict media mode, and never extracts cookies or reads DM content.

**Tech Stack:** Swift 6, SwiftUI, WebKit (`WKWebView`), IGCore Swift Package tests with Swift Testing, XcodeGen, SwiftLint.

## Global Constraints

- iOS deployment target remains `26.0` in `project.yml`.
- Swift language mode remains `6.0` for the app and Swift 6 mode for IGCore.
- `IGCore` must remain UI-free: no SwiftUI, UIKit, or WebKit imports in `Packages/IGCore/Sources/IGCore`.
- V1 must not call Instagram private/mobile APIs from the app flow.
- V1 must not extract, copy, decode, store, or export `sessionid`.
- V1 must not construct `Authorization: Bearer IGT:2:`.
- V1 must not use a backend bridge, proxy, polling loop, automation, or scraping.
- V1 must be content-blind: inspect URLs/routes only; do not read or store DM content, usernames, thread IDs, or media URLs as app data.
- The route firewall blocks by default and gives blocked pages only one action: **Back to DMs**.
- Use persistent WebKit website data for login continuity; logout clears this app's WebKit website data.

---

## File Structure

Create and modify these files:

- Create `Packages/IGCore/Sources/IGCore/WebFirewall/RouteFirewall.swift`
  - Pure route classification and return-route memory.
  - Public API consumed by the app target.

- Create `Packages/IGCore/Tests/IGCoreTests/RouteFirewallTests.swift`
  - Host-unit tests for all allow/block/media/return-route rules.

- Create `App/Sources/WebFirewall/FirewallScreenState.swift`
  - App-only SwiftUI state enum for web, media, blocked, and error states.

- Create `App/Sources/WebFirewall/FirewallViewModel.swift`
  - Main-actor coordinator between SwiftUI, WebView, and `RouteFirewall`.

- Create `App/Sources/WebFirewall/FirewallWebView.swift`
  - `UIViewRepresentable` wrapper around `WKWebView` with navigation delegate.

- Create `App/Sources/WebFirewall/WebFirewallRootView.swift`
  - Native SwiftUI shell around the WebView.

- Create `App/Sources/WebFirewall/BlockedContentView.swift`
  - Native blocker UI with only **Back to DMs**.

- Create `App/Sources/WebFirewall/MinimalStyleInjector.swift`
  - Limited CSS/JS injection and SPA route-change observer.

- Create `App/Sources/WebFirewall/SettingsView.swift`
  - Native settings/logout sheet.

- Modify `App/Sources/RootView.swift`
  - Replace the static screen with `WebFirewallRootView()`.

- Modify `README.md`
  - Update local-run expectations and document the WebView firewall pivot.

---

### Task 1: Pure Route Firewall

**Files:**
- Create: `Packages/IGCore/Sources/IGCore/WebFirewall/RouteFirewall.swift`
- Test: `Packages/IGCore/Tests/IGCoreTests/RouteFirewallTests.swift`

**Interfaces:**
- Produces:
  - `public enum RouteDecision: Equatable, Sendable`
  - `public struct RouteFirewall: Equatable, Sendable`
  - `public static var RouteFirewall.inboxURL: URL`
  - `public mutating func RouteFirewall.decision(for targetURL: URL, currentURL: URL?) -> RouteDecision`
  - `public mutating func RouteFirewall.rememberIfDM(_ url: URL)`
  - `public func RouteFirewall.backToDMsURL() -> URL`
  - `public static func RouteFirewall.isAllowedAuthURL(_ url: URL) -> Bool`
  - `public static func RouteFirewall.isDirectURL(_ url: URL) -> Bool`
  - `public static func RouteFirewall.isMediaURL(_ url: URL) -> Bool`
- Consumes: Foundation `URL` only.

- [ ] **Step 1: Write the failing route-policy tests**

Create `Packages/IGCore/Tests/IGCoreTests/RouteFirewallTests.swift`:

```swift
import Foundation
import Testing
@testable import IGCore

@Suite struct RouteFirewallTests {
    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    @Test func directRoutesAreAllowedAndRemembered() throws {
        var firewall = RouteFirewall()
        let threadURL = try url("https://www.instagram.com/direct/t/12345/")

        let decision = firewall.decision(for: threadURL, currentURL: nil)

        #expect(decision == .allow)
        #expect(firewall.lastDMURL == threadURL)
    }

    @Test func authRoutesAreAllowed() throws {
        var firewall = RouteFirewall()
        let loginURL = try url("https://www.instagram.com/accounts/login/")
        let oneTapURL = try url("https://www.instagram.com/accounts/onetap/")
        let challengeURL = try url("https://www.instagram.com/challenge/action/")

        #expect(firewall.decision(for: loginURL, currentURL: nil) == .allow)
        #expect(firewall.decision(for: oneTapURL, currentURL: nil) == .allow)
        #expect(firewall.decision(for: challengeURL, currentURL: nil) == .allow)
    }

    @Test func mediaRoutesAreAllowedOnlyFromDirectContext() throws {
        var firewall = RouteFirewall()
        let threadURL = try url("https://www.instagram.com/direct/t/12345/")
        let reelURL = try url("https://www.instagram.com/reel/ABC123/")
        let postURL = try url("https://www.instagram.com/p/POST123/")
        let storyURL = try url("https://www.instagram.com/stories/alice/999/")

        #expect(firewall.decision(for: reelURL, currentURL: nil) == .block(returnURL: RouteFirewall.inboxURL))
        #expect(firewall.decision(for: postURL, currentURL: nil) == .block(returnURL: RouteFirewall.inboxURL))
        #expect(firewall.decision(for: storyURL, currentURL: nil) == .block(returnURL: RouteFirewall.inboxURL))

        #expect(firewall.decision(for: reelURL, currentURL: threadURL) == .allowMedia(returnURL: threadURL))
        #expect(firewall.decision(for: postURL, currentURL: threadURL) == .allowMedia(returnURL: threadURL))
        #expect(firewall.decision(for: storyURL, currentURL: threadURL) == .allowMedia(returnURL: threadURL))
    }

    @Test func secondMediaNavigationFromMediaModeIsBlocked() throws {
        var firewall = RouteFirewall()
        let threadURL = try url("https://www.instagram.com/direct/t/12345/")
        let firstReelURL = try url("https://www.instagram.com/reel/FIRST/")
        let suggestedReelURL = try url("https://www.instagram.com/reel/SUGGESTED/")

        #expect(firewall.decision(for: firstReelURL, currentURL: threadURL) == .allowMedia(returnURL: threadURL))
        #expect(firewall.decision(for: suggestedReelURL, currentURL: firstReelURL) == .block(returnURL: threadURL))
    }

    @Test func distractingRoutesAreBlocked() throws {
        var firewall = RouteFirewall()
        let threadURL = try url("https://www.instagram.com/direct/t/12345/")
        _ = firewall.decision(for: threadURL, currentURL: nil)

        let blockedURLs = try [
            url("https://www.instagram.com/"),
            url("https://www.instagram.com/explore/"),
            url("https://www.instagram.com/reels/"),
            url("https://www.instagram.com/search/"),
            url("https://www.instagram.com/alice/"),
            url("https://www.instagram.com/explore/tags/surfing/"),
            url("https://www.instagram.com/explore/locations/123/place/")
        ]

        for blockedURL in blockedURLs {
            #expect(firewall.decision(for: blockedURL, currentURL: threadURL) == .block(returnURL: threadURL))
        }
    }

    @Test func nonInstagramHostsAreBlocked() throws {
        var firewall = RouteFirewall()
        let externalURL = try url("https://example.com/direct/inbox/")

        #expect(firewall.decision(for: externalURL, currentURL: nil) == .block(returnURL: RouteFirewall.inboxURL))
    }

    @Test func httpInstagramURLsAreBlocked() throws {
        var firewall = RouteFirewall()
        let httpURL = try url("http://www.instagram.com/direct/inbox/")

        #expect(firewall.decision(for: httpURL, currentURL: nil) == .block(returnURL: RouteFirewall.inboxURL))
    }

    @Test func backToDMsFallsBackToInboxWhenNoThreadIsKnown() {
        let firewall = RouteFirewall()

        #expect(firewall.backToDMsURL() == RouteFirewall.inboxURL)
    }

    @Test func backToDMsUsesLastRememberedDirectRoute() throws {
        var firewall = RouteFirewall()
        let inboxURL = try url("https://www.instagram.com/direct/inbox/")
        let threadURL = try url("https://www.instagram.com/direct/t/12345/")

        firewall.rememberIfDM(inboxURL)
        #expect(firewall.backToDMsURL() == inboxURL)

        firewall.rememberIfDM(threadURL)
        #expect(firewall.backToDMsURL() == threadURL)
    }
}
```

- [ ] **Step 2: Run the route-policy tests and verify they fail**

Run:

```bash
cd Packages/IGCore
swift test --filter RouteFirewallTests
```

Expected: compile failure because `RouteFirewall` and `RouteDecision` do not exist.

- [ ] **Step 3: Implement the route firewall**

Create `Packages/IGCore/Sources/IGCore/WebFirewall/RouteFirewall.swift`:

```swift
import Foundation

public enum RouteDecision: Equatable, Sendable {
    case allow
    case allowMedia(returnURL: URL)
    case block(returnURL: URL)
}

public struct RouteFirewall: Equatable, Sendable {
    public static var inboxURL: URL {
        guard let url = URL(string: "https://www.instagram.com/direct/inbox/") else {
            preconditionFailure("Static Instagram inbox URL is invalid")
        }
        return url
    }

    public private(set) var lastDMURL: URL?

    public init(lastDMURL: URL? = nil) {
        self.lastDMURL = lastDMURL
    }

    public mutating func decision(for targetURL: URL, currentURL: URL?) -> RouteDecision {
        guard Self.isInstagramWebURL(targetURL) else {
            return .block(returnURL: backToDMsURL())
        }

        if Self.isAllowedAuthURL(targetURL) {
            return .allow
        }

        if Self.isDirectURL(targetURL) {
            lastDMURL = targetURL
            return .allow
        }

        if Self.isMediaURL(targetURL), let currentURL, Self.isDirectURL(currentURL) {
            lastDMURL = currentURL
            return .allowMedia(returnURL: currentURL)
        }

        return .block(returnURL: backToDMsURL())
    }

    public mutating func rememberIfDM(_ url: URL) {
        guard Self.isInstagramWebURL(url), Self.isDirectURL(url) else { return }
        lastDMURL = url
    }

    public func backToDMsURL() -> URL {
        lastDMURL ?? Self.inboxURL
    }

    public static func isAllowedAuthURL(_ url: URL) -> Bool {
        guard isInstagramWebURL(url) else { return false }
        return path(url, is: "/accounts/login")
            || path(url, hasPrefix: "/accounts/login/")
            || path(url, is: "/accounts/onetap")
            || path(url, hasPrefix: "/accounts/onetap/")
            || path(url, is: "/challenge")
            || path(url, hasPrefix: "/challenge/")
    }

    public static func isDirectURL(_ url: URL) -> Bool {
        guard isInstagramWebURL(url) else { return false }
        return path(url, is: "/direct") || path(url, hasPrefix: "/direct/")
    }

    public static func isMediaURL(_ url: URL) -> Bool {
        guard isInstagramWebURL(url) else { return false }
        return path(url, is: "/reel")
            || path(url, hasPrefix: "/reel/")
            || path(url, is: "/p")
            || path(url, hasPrefix: "/p/")
            || path(url, is: "/stories")
            || path(url, hasPrefix: "/stories/")
    }

    private static func isInstagramWebURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "instagram.com" || host == "www.instagram.com"
    }

    private static func path(_ url: URL, is expected: String) -> Bool {
        normalizedPath(url) == expected
    }

    private static func path(_ url: URL, hasPrefix prefix: String) -> Bool {
        normalizedPath(url).hasPrefix(prefix)
    }

    private static func normalizedPath(_ url: URL) -> String {
        let path = url.path
        return path.isEmpty ? "/" : path
    }
}
```

- [ ] **Step 4: Run the route-policy tests and verify they pass**

Run:

```bash
cd Packages/IGCore
swift test --filter RouteFirewallTests
```

Expected: all `RouteFirewallTests` pass.

- [ ] **Step 5: Run the full IGCore suite**

Run:

```bash
cd Packages/IGCore
swift test
```

Expected: all existing tests plus `RouteFirewallTests` pass. Live tests skip unless `IG_SESSIONID` is set.

- [ ] **Step 6: Commit Task 1**

Run from repo root:

```bash
git add Packages/IGCore/Sources/IGCore/WebFirewall/RouteFirewall.swift \
  Packages/IGCore/Tests/IGCoreTests/RouteFirewallTests.swift
git commit -m "feat: add web route firewall"
```

---

### Task 2: Native WebView Shell and Blocker

**Files:**
- Create: `App/Sources/WebFirewall/FirewallScreenState.swift`
- Create: `App/Sources/WebFirewall/FirewallViewModel.swift`
- Create: `App/Sources/WebFirewall/FirewallWebView.swift`
- Create: `App/Sources/WebFirewall/WebFirewallRootView.swift`
- Create: `App/Sources/WebFirewall/BlockedContentView.swift`
- Modify: `App/Sources/RootView.swift`

**Interfaces:**
- Consumes:
  - `RouteFirewall.inboxURL`
  - `RouteFirewall.decision(for:currentURL:)`
  - `RouteFirewall.rememberIfDM(_:)`
  - `RouteDecision`
- Produces:
  - `struct WebFirewallRootView: View`
  - `struct FirewallWebView: UIViewRepresentable`
  - `@MainActor final class FirewallViewModel: ObservableObject`
  - `struct BlockedContentView: View`

- [ ] **Step 1: Add app screen state**

Create `App/Sources/WebFirewall/FirewallScreenState.swift`:

```swift
import Foundation

enum FirewallScreenState: Equatable {
    case web
    case media(returnURL: URL)
    case blocked(returnURL: URL)
    case error(String)

    var returnURL: URL? {
        switch self {
        case .web, .error:
            nil
        case .media(let returnURL), .blocked(let returnURL):
            returnURL
        }
    }

    var showsBackToDMs: Bool {
        switch self {
        case .media, .blocked:
            true
        case .web, .error:
            false
        }
    }
}
```

- [ ] **Step 2: Add the main WebView coordinator model**

Create `App/Sources/WebFirewall/FirewallViewModel.swift`:

```swift
import Combine
import Foundation
import IGCore

@MainActor
final class FirewallViewModel: ObservableObject {
    @Published var screen: FirewallScreenState = .web
    @Published var isLoading = false
    @Published var currentURL: URL?
    @Published var reloadToken = UUID()

    private var routeFirewall = RouteFirewall()
    private var pendingLoadURL: URL?

    var homeURL: URL { RouteFirewall.inboxURL }

    var showsBackToDMs: Bool { screen.showsBackToDMs }

    func decision(for targetURL: URL) -> RouteDecision {
        let decision = routeFirewall.decision(for: targetURL, currentURL: currentURL)
        apply(decision, targetURL: targetURL)
        return decision
    }

    func observeCommittedURL(_ url: URL) {
        currentURL = url
        routeFirewall.rememberIfDM(url)

        if RouteFirewall.isDirectURL(url) || RouteFirewall.isAllowedAuthURL(url) {
            screen = .web
        }
    }

    func fail(_ error: Error) {
        isLoading = false
        screen = .error(error.localizedDescription)
    }

    func backToDMs() {
        let returnURL = screen.returnURL ?? routeFirewall.backToDMsURL()
        pendingLoadURL = returnURL
        screen = .web
    }

    func consumePendingLoadURL() -> URL? {
        let url = pendingLoadURL
        pendingLoadURL = nil
        return url
    }

    private func apply(_ decision: RouteDecision, targetURL: URL) {
        switch decision {
        case .allow:
            if RouteFirewall.isDirectURL(targetURL) || RouteFirewall.isAllowedAuthURL(targetURL) {
                screen = .web
            }
        case .allowMedia(let returnURL):
            screen = .media(returnURL: returnURL)
        case .block(let returnURL):
            screen = .blocked(returnURL: returnURL)
        }
    }
}
```

- [ ] **Step 3: Add the native blocked-content screen**

Create `App/Sources/WebFirewall/BlockedContentView.swift`:

```swift
import SwiftUI

struct BlockedContentView: View {
    let backToDMs: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("This part of Instagram is blocked")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("Minimal Instagram only opens DMs and media shared in DMs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: backToDMs) {
                Text("Back to DMs")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
    }
}
```

- [ ] **Step 4: Add the basic WebView wrapper**

Create `App/Sources/WebFirewall/FirewallWebView.swift`:

```swift
import IGCore
import SwiftUI
import WebKit

struct FirewallWebView: UIViewRepresentable {
    @ObservedObject var model: FirewallViewModel
    let reloadToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.webView = webView
        context.coordinator.reloadToken = reloadToken

        webView.load(URLRequest(url: model.homeURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.model = model

        if context.coordinator.reloadToken != reloadToken {
            context.coordinator.reloadToken = reloadToken
            webView.load(URLRequest(url: model.homeURL))
            return
        }

        if let requestedURL = model.consumePendingLoadURL() {
            webView.load(URLRequest(url: requestedURL))
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var model: FirewallViewModel
        weak var webView: WKWebView?
        var reloadToken: UUID?

        init(model: FirewallViewModel) {
            self.model = model
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.isLoading = true
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if let url = webView.url {
                model.observeCommittedURL(url)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.isLoading = false
            if let url = webView.url {
                model.observeCommittedURL(url)
            }
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            model.fail(error)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            model.fail(error)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame ?? true else {
                decisionHandler(.allow)
                return
            }

            guard let targetURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let decision = model.decision(for: targetURL)
            switch decision {
            case .allow, .allowMedia:
                decisionHandler(.allow)
            case .block:
                decisionHandler(.cancel)
            }
        }
    }
}
```

- [ ] **Step 5: Add the native shell**

Create `App/Sources/WebFirewall/WebFirewallRootView.swift`:

```swift
import SwiftUI

struct WebFirewallRootView: View {
    @StateObject private var model = FirewallViewModel()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Divider()
                webContent
            }

            if case .blocked = model.screen {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()

                BlockedContentView {
                    model.backToDMs()
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            if model.showsBackToDMs {
                Button {
                    model.backToDMs()
                } label: {
                    Label("Back to DMs", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
            }

            Text("Minimal Instagram")
                .font(.headline)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background)
    }

    private var webContent: some View {
        ZStack {
            FirewallWebView(model: model, reloadToken: model.reloadToken)

            if model.isLoading {
                ProgressView()
                    .padding(18)
                    .background(.regularMaterial, in: Capsule())
            }

            if case .error(let message) = model.screen {
                errorView(message)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Couldn't load Instagram")
                .font(.headline)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Back to DMs") {
                model.backToDMs()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding()
    }
}

#Preview {
    WebFirewallRootView()
}
```

- [ ] **Step 6: Replace `RootView` with the WebView firewall shell**

Replace `App/Sources/RootView.swift` with:

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        WebFirewallRootView()
    }
}

#Preview {
    RootView()
}
```

- [ ] **Step 7: Generate the Xcode project**

Run from repo root:

```bash
xcodegen generate
```

Expected: project generation succeeds and the new app files are included through `App/Sources`.

- [ ] **Step 8: Build the app**

Run from repo root:

```bash
xcodebuild -project MinimalInstagram.xcodeproj \
  -scheme MinimalInstagram \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  build -quiet
```

Expected: build succeeds. If the local machine only has a different simulator, run `xcodebuild -project MinimalInstagram.xcodeproj -scheme MinimalInstagram -showdestinations` and choose an available iOS simulator destination.

- [ ] **Step 9: Run SwiftLint**

Run:

```bash
swiftlint --quiet
```

Expected: no output.

- [ ] **Step 10: Commit Task 2**

Run:

```bash
git add App/Sources/RootView.swift App/Sources/WebFirewall
git commit -m "feat: add webview firewall shell"
```

---

### Task 3: Minimal CSS and SPA Route Observer

**Files:**
- Create: `App/Sources/WebFirewall/MinimalStyleInjector.swift`
- Modify: `App/Sources/WebFirewall/FirewallWebView.swift`

**Interfaces:**
- Consumes:
  - `FirewallViewModel.decision(for:)`
  - `FirewallViewModel.observeCommittedURL(_:)`
- Produces:
  - `enum MinimalStyleInjector`
  - WebKit script message handler named `routeChanged`

- [ ] **Step 1: Add the minimal injection source**

Create `App/Sources/WebFirewall/MinimalStyleInjector.swift`:

```swift
import Foundation

enum MinimalStyleInjector {
    static let routeMessageName = "routeChanged"

    static let source = #"""
(function() {
    if (window.__minimalInstagramFirewallInstalled === true) {
        return;
    }
    window.__minimalInstagramFirewallInstalled = true;

    const style = document.createElement('style');
    style.setAttribute('data-minimal-instagram', 'true');
    style.textContent = `
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

        body {
            overscroll-behavior: contain !important;
        }
    `;
    document.documentElement.appendChild(style);

    function notifyRouteChanged() {
        try {
            window.webkit.messageHandlers.routeChanged.postMessage(window.location.href);
        } catch (error) {
            return;
        }
    }

    function installHistoryObserver(methodName) {
        const original = history[methodName];
        history[methodName] = function() {
            const result = original.apply(this, arguments);
            window.setTimeout(notifyRouteChanged, 0);
            return result;
        };
    }

    installHistoryObserver('pushState');
    installHistoryObserver('replaceState');
    window.addEventListener('popstate', notifyRouteChanged);
    window.setTimeout(notifyRouteChanged, 0);
})();
"""
}
```

- [ ] **Step 2: Install the user script and message handler in `FirewallWebView`**

Modify the `makeUIView(context:)` body in `App/Sources/WebFirewall/FirewallWebView.swift` so it creates a `WKUserContentController` before the WebView:

```swift
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let userContentController = WKUserContentController()
        userContentController.addUserScript(
            WKUserScript(source: MinimalStyleInjector.source,
                         injectionTime: .atDocumentEnd,
                         forMainFrameOnly: true)
        )
        userContentController.add(context.coordinator, name: MinimalStyleInjector.routeMessageName)
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.webView = webView
        context.coordinator.reloadToken = reloadToken

        webView.load(URLRequest(url: model.homeURL))
        return webView
    }
```

- [ ] **Step 3: Make the coordinator receive route-change messages**

Change the coordinator declaration in `App/Sources/WebFirewall/FirewallWebView.swift` from:

```swift
    final class Coordinator: NSObject, WKNavigationDelegate {
```

to:

```swift
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
```

Add this method inside `Coordinator`:

```swift
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == MinimalStyleInjector.routeMessageName,
                  let href = message.body as? String,
                  let url = URL(string: href) else { return }

            let decision = model.decision(for: url)
            switch decision {
            case .allow, .allowMedia:
                model.observeCommittedURL(url)
            case .block:
                webView?.stopLoading()
            }
        }
```

- [ ] **Step 4: Remove the script message handler during dismantle**

Add this static method inside `FirewallWebView` but outside `Coordinator`:

```swift
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: MinimalStyleInjector.routeMessageName
        )
        webView.navigationDelegate = nil
    }
```

- [ ] **Step 5: Build and lint**

Run from repo root:

```bash
xcodebuild -project MinimalInstagram.xcodeproj \
  -scheme MinimalInstagram \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  build -quiet
swiftlint --quiet
```

Expected: build succeeds and SwiftLint emits no output.

- [ ] **Step 6: Commit Task 3**

Run:

```bash
git add App/Sources/WebFirewall/MinimalStyleInjector.swift App/Sources/WebFirewall/FirewallWebView.swift
git commit -m "feat: add minimal instagram web cleanup"
```

---

### Task 4: Settings and WebKit Logout

**Files:**
- Create: `App/Sources/WebFirewall/SettingsView.swift`
- Modify: `App/Sources/WebFirewall/FirewallViewModel.swift`
- Modify: `App/Sources/WebFirewall/WebFirewallRootView.swift`

**Interfaces:**
- Consumes:
  - `FirewallViewModel.reloadToken`
  - `FirewallViewModel.homeURL`
- Produces:
  - `func FirewallViewModel.logout()`
  - `struct SettingsView: View`

- [ ] **Step 1: Add WebKit logout to the view model**

Add `import WebKit` to `App/Sources/WebFirewall/FirewallViewModel.swift`:

```swift
import Combine
import Foundation
import IGCore
import WebKit
```

Add this method inside `FirewallViewModel`:

```swift
    func logout() {
        isLoading = true
        let dataStore = WKWebsiteDataStore.default()
        dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                             modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                self.currentURL = nil
                self.routeFirewall = RouteFirewall()
                self.pendingLoadURL = nil
                self.screen = .web
                self.reloadToken = UUID()
            }
        }
    }
```

- [ ] **Step 2: Add the settings view**

Create `App/Sources/WebFirewall/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    let logout: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Button(role: .destructive) {
                        dismiss()
                        logout()
                    } label: {
                        Label("Log Out of Instagram in This App", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("About") {
                    Text("Minimal Instagram loads Instagram web DMs and blocks distracting routes locally.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Add the settings button and sheet to the native shell**

In `App/Sources/WebFirewall/WebFirewallRootView.swift`, add this property near the existing `@StateObject`:

```swift
    @State private var showingSettings = false
```

Change the top-level `body` to attach the settings sheet:

```swift
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Divider()
                webContent
            }

            if case .blocked = model.screen {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()

                BlockedContentView {
                    model.backToDMs()
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView {
                model.logout()
            }
        }
    }
```

Add the settings button before the closing brace of the `HStack` in `topBar`, after `Spacer()`:

```swift
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .imageScale(.medium)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Settings")
```

- [ ] **Step 4: Build and lint**

Run:

```bash
xcodebuild -project MinimalInstagram.xcodeproj \
  -scheme MinimalInstagram \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  build -quiet
swiftlint --quiet
```

Expected: build succeeds and SwiftLint emits no output.

- [ ] **Step 5: Manual logout check**

Run the app in the simulator or on device:

```bash
open MinimalInstagram.xcodeproj
```

Manual expected behavior:

1. App opens Instagram WebView.
2. Settings gear appears in the native top bar.
3. Settings → Log Out of Instagram in This App dismisses the sheet.
4. WebView reloads `/direct/inbox/`.
5. If the user had been logged in inside this app's WebView, Instagram asks for login again.

- [ ] **Step 6: Commit Task 4**

Run:

```bash
git add App/Sources/WebFirewall/FirewallViewModel.swift \
  App/Sources/WebFirewall/WebFirewallRootView.swift \
  App/Sources/WebFirewall/SettingsView.swift
git commit -m "feat: add webview logout settings"
```

---

### Task 5: Documentation and Final Verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: app behavior from Tasks 1-4.
- Produces: updated local run instructions and final verified app build.

- [ ] **Step 1: Update README project description**

Modify the top of `README.md` to describe the current app direction. Replace the first paragraph:

```markdown
A relationship-first, "attention firewall" iOS client over Instagram — DMs and
friend-shared reels only. No feed, explore, or recommendations. Single-user (the
author's own account) for V1.
```

with:

```markdown
A relationship-first, "attention firewall" iOS app for Instagram web DMs. V1
loads Instagram's official web DM surface in a local `WKWebView`, blocks
distracting routes like feed/explore/reels/search, and allows media only when it
is opened from a DM. No private Instagram API, session extraction, backend
bridge, polling, or message scraping is part of the V1 app flow.
```

- [ ] **Step 2: Update README layout notes**

Replace this section in `README.md`:

```markdown
App/
  Sources/             SwiftUI app shell, WKWebView auth, AVPlayer reel viewer (UI/device layer)
  Resources/           Assets.xcassets
```

with:

```markdown
App/
  Sources/             SwiftUI shell + WKWebView route firewall (UI/device layer)
  Resources/           Assets.xcassets
```

Replace this paragraph:

```markdown
`IGCore` is a Swift Package that must never import SwiftUI/UIKit. That package
boundary is what structurally enforces the design's firewall rule (pure mapper,
one-way dependencies). Components are added test-first.
```

with:

```markdown
`IGCore` is a Swift Package that must never import SwiftUI/UIKit/WebKit. It holds
pure logic such as DTO mapping and route policy tests. The app target owns the
actual `WKWebView` and native SwiftUI shell.
```

- [ ] **Step 3: Add WebView-specific manual test notes to README**

Add this section after the common commands block in `README.md`:

```markdown
## Manual WebView firewall checks

After launching the app, verify:

1. The app opens `instagram.com/direct/inbox/` inside the native shell.
2. Instagram login / 2FA / checkpoint flows remain usable inside the WebView.
3. DM read and send work through Instagram's own web UI.
4. Tapping a reel/post/story from a DM opens media mode.
5. `Back to DMs` returns to the originating thread or inbox.
6. Feed, Explore, Reels tab, Search, profile, hashtag, and location routes show
   the local blocker screen.
7. Settings → logout clears the app's Instagram WebKit data and returns to login.
```

- [ ] **Step 4: Run all automated checks**

Run from repo root:

```bash
swiftlint --quiet
cd Packages/IGCore && swift test
cd ../..
xcodegen generate
xcodebuild -project MinimalInstagram.xcodeproj \
  -scheme MinimalInstagram \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  build -quiet
```

Expected:

- SwiftLint emits no output.
- IGCore tests pass.
- XcodeGen succeeds.
- App build exits 0.

- [ ] **Step 5: Launch on simulator from CLI**

Run, replacing the device id if needed:

```bash
DEVICE_ID=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone 17 \(/ && /26.5/ {print $2; exit}')
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData \
  -path '*/Build/Products/Debug-iphonesimulator/MinimalInstagram.app' \
  -type d -print -quit)

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch "$DEVICE_ID" com.srichandramouli.MinimalInstagram
```

Expected: the app launches and shows the native Minimal Instagram shell containing Instagram web.

- [ ] **Step 6: Commit Task 5**

Run:

```bash
git add README.md MinimalInstagram.xcodeproj
git commit -m "docs: document webview firewall flow"
```

If `MinimalInstagram.xcodeproj` remains ignored by `.gitignore`, commit only `README.md`:

```bash
git add README.md
git commit -m "docs: document webview firewall flow"
```

---

## Plan Self-Review

Spec coverage:

- Native shell: Task 2.
- Persistent WebView: Task 2, `WKWebsiteDataStore.default()`.
- Route firewall: Task 1 pure policy and Task 2 navigation delegate.
- DM-opened media mode: Task 1 decision rules and Task 2 native back control.
- Blocked screen with only Back to DMs: Task 2.
- Content-blind behavior: enforced by file responsibilities and no DOM scraping code.
- Minimal CSS layer and SPA route observer: Task 3.
- Logout clears WebKit data: Task 4.
- README/manual checks: Task 5.

Type consistency:

- `RouteDecision` cases used in app match Task 1 definitions.
- `RouteFirewall` methods used by `FirewallViewModel` match Task 1 signatures.
- `FirewallScreenState` computed properties used by `FirewallViewModel` and `WebFirewallRootView` match Task 2 definitions.
- `MinimalStyleInjector.routeMessageName` and `.source` used by `FirewallWebView` match Task 3 definitions.

Validation commands:

- `cd Packages/IGCore && swift test --filter RouteFirewallTests`
- `cd Packages/IGCore && swift test`
- `swiftlint --quiet`
- `xcodegen generate`
- `xcodebuild -project MinimalInstagram.xcodeproj -scheme MinimalInstagram -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build -quiet`
