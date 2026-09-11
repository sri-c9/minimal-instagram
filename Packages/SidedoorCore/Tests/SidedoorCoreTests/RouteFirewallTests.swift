import Foundation
import Testing
@testable import SidedoorCore

@Suite struct RouteFirewallTests {
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
