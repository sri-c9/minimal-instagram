import Foundation

enum FirewallScreenState: Equatable {
    case web
    case media(returnURL: URL)
    case blocked(returnURL: URL)
    case error(String)

    var returnURL: URL? {
        switch self {
        case .web, .error:
            nil
        case .media(let returnURL), .blocked(let returnURL):
            returnURL
        }
    }

    var showsBackToDMs: Bool {
        switch self {
        case .media, .blocked:
            true
        case .web, .error:
            false
        }
    }

    var statusTitle: String {
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
