import Foundation
import Testing
@testable import IGCore

@Suite struct DomainMapperThreadTests {
    @Test func mapsTextMessages() throws {
        let raw = try Fixture.decode(RawThreadResponse.self, "thread_with_junk")
        let detail = DomainMapper.mapThread(raw)

        let messages: [Message] = detail.items.compactMap {
            if case .message(let message) = $0 { return message } else { return nil }
        }
        #expect(messages.map(\.id) == ["i_text_1"])
        #expect(messages.first?.text == "hi")
        #expect(messages.first?.senderID == "111")
        #expect(detail.id == "t_junk_1")
        #expect(detail.title == "Alice Example")
    }

    @Test func mapsSharedReelsWithPlayableVideoURL() throws {
        let raw = try Fixture.decode(RawThreadResponse.self, "thread_with_junk")
        let detail = DomainMapper.mapThread(raw)

        let reels: [SharedReel] = detail.items.compactMap {
            if case .reel(let reel) = $0 { return reel } else { return nil }
        }
        #expect(reels.map(\.id) == ["i_clip_1", "i_share_vid"])
        #expect(reels.allSatisfy { $0.videoURL.scheme == "https" })
        #expect(reels.first?.thumbnailURL?.absoluteString == "https://scontent.cdninstagram.com/v/thumb1.jpg")
    }

    // MARK: - Real-shape confirmation (sanitized capture, 2026-05-23)
    // Confirms our DTOs decode Instagram's actual web `direct_v2` shape:
    // clip.clip.video_versions and direct_media_share.media.video_versions.

    @Test func mapsTextMessagesFromRealThread() throws {
        let raw = try Fixture.decode(RawThreadResponse.self, "thread_real")
        let detail = DomainMapper.mapThread(raw)

        let messages: [Message] = detail.items.compactMap {
            if case .message(let message) = $0 { return message } else { return nil }
        }
        // Two non-empty texts survive; the empty-text item is dropped.
        #expect(messages.map(\.id) == ["r_text_1", "r_text_2"])
        #expect(messages.allSatisfy { !$0.text.isEmpty })
        #expect(messages.allSatisfy { !$0.senderID.isEmpty })
    }

    @Test func mapsSharedReelsFromRealThread() throws {
        let raw = try Fixture.decode(RawThreadResponse.self, "thread_real")
        let detail = DomainMapper.mapThread(raw)

        let reels: [SharedReel] = detail.items.compactMap {
            if case .reel(let reel) = $0 { return reel } else { return nil }
        }
        // Both clips + the video media_share survive; the photo media_share is gated out.
        #expect(reels.map(\.id) == ["r_clip_1", "r_clip_2", "r_share_vid"])
        #expect(reels.allSatisfy { $0.videoURL.scheme == "https" })
    }
}
