import Foundation
import Testing
@testable import IGCore

@Suite struct DomainMapperInboxTests {
    @Test func mapsSyntheticInboxToConversations() throws {
        let raw = try Fixture.decode(RawInboxResponse.self, "inbox_synthetic")
        let conversations = DomainMapper.mapInbox(raw)

        #expect(conversations.map(\.id) == ["t_inbox_1", "t_inbox_2"])

        #expect(conversations[0].title == "Carol Example")
        #expect(conversations[0].isUnread == true)
        #expect(conversations[0].isPinned == false)

        #expect(conversations[1].isUnread == false)
        #expect(conversations[1].isPinned == true)
        // full_name is empty -> displayName/title fall back to username
        #expect(conversations[1].title == "dave")
        #expect(conversations[1].participants.first?.displayName == "dave")
    }

    @Test func mapsEmptyInboxToNoConversations() throws {
        let raw = try Fixture.decode(RawInboxResponse.self, "inbox_empty")
        #expect(DomainMapper.mapInbox(raw).isEmpty)
    }
}
