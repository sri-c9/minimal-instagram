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

    // MARK: - Real-shape confirmation (sanitized capture, 2026-05-23)

    @Test func mapsRealInboxToConversations() throws {
        let raw = try Fixture.decode(RawInboxResponse.self, "inbox_real")
        let conversations = DomainMapper.mapInbox(raw)

        #expect(conversations.map(\.id) == ["ri_1", "ri_2", "ri_3", "ri_4"])
        #expect(conversations[0].isUnread == true)          // read_state 1
        #expect(conversations[1].isPinned == true)          // is_pin true
        #expect(conversations[2].title == "deepcurrent")    // empty full_name -> username
        #expect(conversations[3].title == "Ana, Ben")       // group -> joined names
        #expect(conversations.allSatisfy { !$0.participants.isEmpty })
    }
}
