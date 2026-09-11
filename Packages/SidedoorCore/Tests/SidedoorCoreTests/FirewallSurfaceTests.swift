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
