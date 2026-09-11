import Foundation
import Testing
@testable import SidedoorCore

/// Holds for every channel in the registry. Adding a channel adds it to these
/// tests for free through `ChannelID.allCases`.
@Suite struct ChannelInvariantTests {
    @Test(arguments: ChannelID.allCases)
    func homeURLIsAnHTTPSDMRouteOnAListedHost(channelID: ChannelID) throws {
        let channel = channelID.channel
        let home = channel.homeURL

        #expect(home.scheme == "https")
        #expect(channel.hosts.contains(try #require(home.host)))
        #expect(home.user == nil && home.password == nil && home.port == nil)
        #expect(channel.classify(path: home.path.isEmpty ? "/" : home.path) == .dm)
    }

    @Test(arguments: ChannelID.allCases)
    func hostsAreNonEmptyAndLowercase(channelID: ChannelID) {
        let hosts = channelID.channel.hosts
        #expect(!hosts.isEmpty)
        for host in hosts {
            #expect(host == host.lowercased())
            #expect(!host.isEmpty)
        }
    }

    @Test(arguments: ChannelID.allCases)
    func displayNameIsNonEmpty(channelID: ChannelID) {
        #expect(!channelID.channel.displayName.isEmpty)
    }

    @Test func webStoreIdentifiersAreDistinctAndNonZero() {
        let identifiers = ChannelID.allCases.map(\.webStoreIdentifier)
        #expect(Set(identifiers).count == identifiers.count)
        for identifier in identifiers {
            #expect(identifier != UUID(uuid: UUID_NULL))
        }
    }

    @Test(arguments: ChannelID.allCases)
    func unreadFilterCSSWhenPresentIsAHasRule(channelID: ChannelID) {
        guard let css = channelID.channel.webScript.unreadFilterCSS else { return }
        #expect(!css.isEmpty)
        #expect(css.contains(":has("))
    }
}
