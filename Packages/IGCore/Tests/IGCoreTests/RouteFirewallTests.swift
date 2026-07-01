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
