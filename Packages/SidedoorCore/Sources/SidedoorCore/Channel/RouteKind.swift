/// What a channel says a path is. Exactly one kind per path; `.other` is blocked.
public enum RouteKind: Hashable, CaseIterable, Sendable {
    /// Login, one-tap, challenge, captcha, verification.
    case auth
    /// The inbox and threads.
    case dm
    /// A single post, reel, story, or video page.
    case media
    /// Everything else.
    case other
}
