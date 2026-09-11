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

    public var statusTitle: String {
        switch self {
        case .web:
            "DMs"
        case .media:
            "Media"
        case .blocked:
            "Blocked"
        case .error:
            "Offline"
        }
    }
}
