import Foundation
import Testing
@testable import IGCore

@Suite struct RawDTOCursorTests {
    @Test func inboxDecodesOldestCursor() throws {
        let raw = try Fixture.decode(RawInboxResponse.self, "inbox_mobile")
        #expect(raw.inbox.oldestCursor == "fake_inbox_cursor_abc")
    }

    @Test func threadDecodesOldestCursor() throws {
        let raw = try Fixture.decode(RawThreadResponse.self, "thread_mobile")
        #expect(raw.thread.oldestCursor == "fake_thread_cursor_xyz")
    }

    @Test func inboxWithoutCursorDecodesNil() throws {
        let raw = try Fixture.decode(RawInboxResponse.self, "inbox_synthetic")
        #expect(raw.inbox.oldestCursor == nil)
    }
}
