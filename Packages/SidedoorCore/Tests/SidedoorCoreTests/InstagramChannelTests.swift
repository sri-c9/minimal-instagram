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
        #expect(channel.webScript.unreadFilterCSS != nil)
    }

    @Test func unreadFilterHidesRowsWithoutTheMeasuredMarker() throws {
        let css = try #require(channel.webScript.unreadFilterCSS)
        #expect(css.contains(":not(:has("))
        #expect(css.contains("display: none !important"))
        // Scope and marker as measured in docs/Instagram Web Inbox — Unread Marker (2026-09-10).md.
        #expect(css.contains(#"[data-pagelet="IGDInboxThreadListScrollableAreaPagelet"]"#))
        #expect(css.contains(#"span[data-visualcompletion="ignore"]"#))
    }

    @Test func cssHidesNavigationAndDoesNotCarryTheSharedBodyRule() {
        let css = channel.webScript.css
        #expect(css.contains(#"a[href^="/explore"]"#))
        #expect(css.contains(#"a[aria-label="Reels"]"#))
        #expect(!css.contains("overscroll-behavior"))
    }
}
