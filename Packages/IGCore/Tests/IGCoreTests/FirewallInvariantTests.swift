import Foundation
import Testing
@testable import IGCore

@Suite struct FirewallInvariantTests {
    /// The core product promise as a test: feed adversarial payloads through the
    /// mapper; output may contain ONLY allow-listed types. Fails if anyone ever
    /// adds a mapping for a forbidden type.
    /// (The real `thread_real` fixture is added to these arguments after capture.)
    @Test(arguments: ["thread_with_junk", "thread_malformed"])
    func outputContainsOnlyAllowListedTypes(fixture: String) throws {
        let raw = try Fixture.decode(RawThreadResponse.self, fixture)
        let detail = DomainMapper.mapThread(raw)

        for item in detail.items {
            switch item {
            case .message(let message):
                #expect(!message.text.isEmpty, "emitted an empty message — not a real allowed item")
            case .reel(let reel):
                #expect(reel.videoURL.scheme?.hasPrefix("http") == true, "reel must carry a playable video URL")
            }
        }
        // No forbidden ids ever survive.
        let survivingIDs = Set(detail.items.map(\.id))
        let forbidden: Set<String> = ["i_ad_1", "i_sugg_1", "i_unknown_1", "i_share_photo", "clip_no_video"]
        #expect(survivingIDs.isDisjoint(with: forbidden))
    }
}
