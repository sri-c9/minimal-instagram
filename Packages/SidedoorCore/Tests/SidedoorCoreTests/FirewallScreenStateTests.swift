import Foundation
@testable import SidedoorCore
import Testing

@Suite("FirewallScreenState chrome")
struct FirewallScreenStateTests {
    private let inbox = URL(string: "https://www.instagram.com/direct/inbox/")!
    private let thread = URL(string: "https://www.instagram.com/direct/t/1/")!

    @Test func onlyABlockCoversTheWebContent() {
        #expect(FirewallScreenState.blocked(returnURL: inbox).coversWebContent)
        #expect(!FirewallScreenState.web.coversWebContent)
        #expect(!FirewallScreenState.media(returnURL: inbox).coversWebContent)
        #expect(!FirewallScreenState.error("offline").coversWebContent)
    }

    @Test func onlyMediaModeNeedsACaption() {
        #expect(FirewallScreenState.media(returnURL: inbox).caption == "Viewing media shared from DMs")
        #expect(FirewallScreenState.web.caption == nil)
        #expect(FirewallScreenState.blocked(returnURL: inbox).caption == nil)
        #expect(FirewallScreenState.error("offline").caption == nil)
    }

    @Test func enteringABlockCues() {
        #expect(FirewallScreenState.feedbackCue(from: .web, to: .blocked(returnURL: inbox)) == .blocked)
        #expect(FirewallScreenState.feedbackCue(from: .media(returnURL: inbox),
                                                to: .blocked(returnURL: inbox)) == .blocked)
    }

    @Test func aBlockReplacingABlockDoesNotCueAgain() {
        #expect(FirewallScreenState.feedbackCue(from: .blocked(returnURL: inbox),
                                                to: .blocked(returnURL: thread)) == nil)
    }

    @Test func returningToDMsCues() {
        #expect(FirewallScreenState.feedbackCue(from: .blocked(returnURL: inbox), to: .web) == .returnedToDMs)
        #expect(FirewallScreenState.feedbackCue(from: .media(returnURL: inbox), to: .web) == .returnedToDMs)
    }

    @Test func ordinaryNavigationIsSilent() {
        #expect(FirewallScreenState.feedbackCue(from: .web, to: .web) == nil)
        #expect(FirewallScreenState.feedbackCue(from: .web, to: .media(returnURL: inbox)) == nil)
        #expect(FirewallScreenState.feedbackCue(from: .web, to: .error("offline")) == nil)
        #expect(FirewallScreenState.feedbackCue(from: .error("offline"), to: .web) == nil)
    }
}
