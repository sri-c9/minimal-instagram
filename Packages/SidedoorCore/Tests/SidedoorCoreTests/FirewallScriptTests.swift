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
        #expect(script.contains("installHistoryObserver('pushState')"))
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
