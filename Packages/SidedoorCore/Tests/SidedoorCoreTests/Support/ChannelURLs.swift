import Foundation
import Testing
@testable import SidedoorCore

/// One set of representative URLs per channel, so the firewall and surface suites
/// run unchanged over every channel in the registry. Named to avoid the existing
/// `Fixture` JSON helper.
struct ChannelURLs {
    let inboxURL: URL
    let threadURL: URL
    let threadURLWithQueryAndFragment: URL
    /// What the firewall should remember after seeing `threadURLWithQueryAndFragment`.
    let expectedRememberedURL: URL
    let mediaURL: URL
    let secondMediaURL: URL
    let authURLs: [URL]
    let blockedURLs: [URL]
    /// A host no channel owns.
    let externalURL: URL
    /// A DM route on a different channel's host: must be blocked, pinning "nothing shared".
    let otherChannelURL: URL

    static func fixture(for channel: ChannelID) throws -> ChannelURLs {
        switch channel {
        case .instagram:
            try ChannelURLs(
                inboxURL: url("https://www.instagram.com/direct/inbox/"),
                threadURL: url("https://www.instagram.com/direct/t/12345/"),
                threadURLWithQueryAndFragment: url("https://www.instagram.com/direct/t/12345/?igsh=token#frag"),
                expectedRememberedURL: url("https://www.instagram.com/direct/t/12345/"),
                mediaURL: url("https://www.instagram.com/reel/ABC123/"),
                secondMediaURL: url("https://www.instagram.com/reel/SUGGESTED/"),
                authURLs: [
                    url("https://www.instagram.com/accounts/login/"),
                    url("https://www.instagram.com/accounts/onetap/"),
                    url("https://www.instagram.com/challenge/action/")
                ],
                blockedURLs: [
                    url("https://www.instagram.com/"),
                    url("https://www.instagram.com/explore/"),
                    url("https://www.instagram.com/reels/"),
                    url("https://www.instagram.com/search/"),
                    url("https://www.instagram.com/alice/"),
                    url("https://www.instagram.com/explore/tags/surfing/"),
                    url("https://www.instagram.com/explore/locations/123/place/")
                ],
                externalURL: url("https://example.com/direct/inbox/"),
                otherChannelURL: url("https://www.tiktok.com/messages")
            )
        }
    }

    private static func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }
}
