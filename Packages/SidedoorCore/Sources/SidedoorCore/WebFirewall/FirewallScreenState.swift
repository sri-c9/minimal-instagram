import Foundation

/// What the native shell is currently showing around the WebView.
public enum FirewallScreenState: Equatable, Sendable {
    case web
    case media(returnURL: URL)
    case blocked(returnURL: URL)
    case error(String)

    public var returnURL: URL? {
        switch self {
        case .web, .error:
            nil
        case .media(let returnURL), .blocked(let returnURL):
            returnURL
        }
    }

    public var showsBackToDMs: Bool {
        switch self {
        case .media, .blocked:
            true
        case .web, .error:
            false
        }
    }

    /// Whether the shell covers the page entirely. A blocked route stays on
    /// screen behind the blocker otherwise, which is the distraction being blocked.
    public var coversWebContent: Bool {
        if case .blocked = self { true } else { false }
    }

    /// One line beside the title, only where the page itself does not say where
    /// the user is. DMs and auth carry the site's own header; the blocker and the
    /// error card carry their own copy.
    public var caption: String? {
        if case .media = self { "Viewing media shared from DMs" } else { nil }
    }

    /// The haptic a transition deserves, if any.
    public static func feedbackCue(from old: Self, to new: Self) -> FirewallFeedbackCue? {
        switch (old.coversWebContent, new) {
        case (false, .blocked):
            .blocked
        case (_, .web) where old.showsBackToDMs:
            .returnedToDMs
        default:
            nil
        }
    }
}

public enum FirewallFeedbackCue: Equatable, Sendable {
    case blocked
    case returnedToDMs
}
