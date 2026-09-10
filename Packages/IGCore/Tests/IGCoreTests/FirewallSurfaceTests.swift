import Foundation
import Testing
@testable import IGCore

@Suite struct FirewallSurfaceTests {
    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    private func threadURL() throws -> URL {
        try url("https://www.instagram.com/direct/t/12345/")
    }

    /// Puts the surface in the state the app is in while a DM thread is open.
    private func surfaceOnThread() throws -> FirewallSurface {
        var surface = FirewallSurface()
        surface.observeCommittedURL(try threadURL())
        return surface
    }

    // MARK: - The inline reels feed

    @Test func inlineFeedInAThreadRaisesMediaMode() throws {
        var surface = try surfaceOnThread()
        #expect(surface.screen == .web)

        surface.observeInlineMediaSurface(isPresent: true)

        #expect(surface.screen == .media(returnURL: try threadURL()))
        #expect(surface.showsBackToDMs)
    }

    @Test func inlineFeedLeavingRestoresTheThread() throws {
        var surface = try surfaceOnThread()
        surface.observeInlineMediaSurface(isPresent: true)

        surface.observeInlineMediaSurface(isPresent: false)

        #expect(surface.screen == .web)
        #expect(!surface.showsBackToDMs)
    }

    @Test func backFromTheInlineFeedReturnsToTheOriginatingThread() throws {
        var surface = try surfaceOnThread()
        surface.observeInlineMediaSurface(isPresent: true)

        #expect(surface.backToDMsURL() == (try threadURL()))
    }

    @Test func repeatedReportsOfTheSameValueAreNoOps() throws {
        var surface = try surfaceOnThread()

        surface.observeInlineMediaSurface(isPresent: true)
        let afterFirstReport = surface
        surface.observeInlineMediaSurface(isPresent: true)

        #expect(surface == afterFirstReport)
    }

    @Test func aFeedReportOutsideADMThreadIsIgnored() throws {
        // Nothing has committed, so there is no thread to return to; the route
        // firewall owns whatever is on screen and this must not overwrite it.
        var surface = FirewallSurface()

        surface.observeInlineMediaSurface(isPresent: true)

        #expect(surface.screen == .web)
    }

    // MARK: - Not fighting the route firewall

    @Test func losingTheInlineFeedLeavesNavigatedMediaModeAlone() throws {
        var surface = try surfaceOnThread()
        surface.observeInlineMediaSurface(isPresent: true)

        // A real navigation to a reel takes over the screen...
        surface.decide(for: try url("https://www.instagram.com/reel/ABC123/"))
        #expect(surface.screen == .media(returnURL: try threadURL()))

        // ...and a late "the inline feed is gone" report must not clear it.
        surface.observeInlineMediaSurface(isPresent: false)

        #expect(surface.screen == .media(returnURL: try threadURL()))
    }

    @Test func losingTheInlineFeedLeavesTheBlockerAlone() throws {
        var surface = try surfaceOnThread()
        surface.observeInlineMediaSurface(isPresent: true)

        surface.decide(for: try url("https://www.instagram.com/explore/"))
        #expect(surface.screen == .blocked(returnURL: try threadURL()))

        surface.observeInlineMediaSurface(isPresent: false)

        #expect(surface.screen == .blocked(returnURL: try threadURL()))
    }

    @Test func aCommittedNavigationRearmsTheInlineReport() throws {
        var surface = try surfaceOnThread()
        surface.observeInlineMediaSurface(isPresent: true)

        // Re-entering the thread (Back to DMs, or a reload) clears the surface,
        // so opening a reel again has to raise media mode a second time.
        surface.observeCommittedURL(try threadURL())
        #expect(surface.screen == .web)

        surface.observeInlineMediaSurface(isPresent: true)

        #expect(surface.screen == .media(returnURL: try threadURL()))
    }

    @Test func prepareLoadClearsTheInlineFeed() throws {
        var surface = try surfaceOnThread()
        surface.observeInlineMediaSurface(isPresent: true)

        surface.prepareLoad()

        #expect(surface.screen == .web)
    }

    // MARK: - Route decisions still hold

    @Test func directRoutesShowTheWebSurface() throws {
        var surface = FirewallSurface()

        surface.decide(for: try threadURL())

        #expect(surface.screen == .web)
    }

    @Test func mediaIsBlockedWhenNotOpenedFromADM() throws {
        var surface = FirewallSurface()

        surface.decide(for: try url("https://www.instagram.com/reel/ABC123/"))

        #expect(surface.screen == .blocked(returnURL: RouteFirewall.inboxURL))
    }

    @Test func errorsSurfaceAndDoNotOfferAReturnURL() throws {
        var surface = try surfaceOnThread()

        surface.fail("offline")

        #expect(surface.screen == .error("offline"))
        #expect(!surface.showsBackToDMs)
        // The last known thread is still where Back to DMs should go.
        #expect(surface.backToDMsURL() == (try threadURL()))
    }

    @Test func resetForgetsTheBrowsedThread() throws {
        var surface = try surfaceOnThread()
        surface.observeInlineMediaSurface(isPresent: true)

        surface.reset()

        #expect(surface.screen == .web)
        #expect(surface.backToDMsURL() == RouteFirewall.inboxURL)
    }
}
