import Foundation
import Testing
@testable import IGCore

@Suite struct DomainMapperDropTests {
    @Test func dropsAdsSuggestionsUnknownAndPhotoOnlyShares() throws {
        let raw = try Fixture.decode(RawThreadResponse.self, "thread_with_junk")
        let detail = DomainMapper.mapThread(raw)

        // Allowed survivors: 1 text + 1 clip + 1 media_share-with-video = 3.
        #expect(detail.items.count == 3)
        let ids = Set(detail.items.map(\.id))
        #expect(ids == ["i_text_1", "i_clip_1", "i_share_vid"])
    }

    @Test func ignoresMalformedItemsWithoutCrashing() throws {
        let raw = try Fixture.decode(RawThreadResponse.self, "thread_malformed")
        let detail = DomainMapper.mapThread(raw)

        // Only the one well-formed text item survives.
        #expect(detail.items.count == 1)
        #expect(detail.items.first?.id == "ok_text")
    }
}
