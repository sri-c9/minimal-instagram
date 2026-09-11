import Foundation

/// A conversation's contents as a single chronologically ordered timeline.
public struct ThreadDetail: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let items: [ThreadItem]

    public init(id: String, title: String, items: [ThreadItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}
