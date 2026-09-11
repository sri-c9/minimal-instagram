import Foundation

/// One entry in a thread's timeline. The firewall, expressed in the type system:
/// there is no case for ads, suggestions, or any non-allow-listed content, so they
/// are literally unrepresentable in mapper output.
public enum ThreadItem: Equatable, Sendable, Identifiable {
    case message(Message)
    case reel(SharedReel)

    public var id: String {
        switch self {
        case .message(let message): return message.id
        case .reel(let reel): return reel.id
        }
    }
}
