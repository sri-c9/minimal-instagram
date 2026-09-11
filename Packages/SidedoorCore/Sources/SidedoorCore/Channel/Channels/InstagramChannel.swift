import Foundation

/// Instagram web, DMs only. Behavior-identical to the pre-channel firewall.
public struct InstagramChannel: Channel {
    public init() {}

    public var displayName: String { "Instagram" }

    public static let hosts: Set<String> = ["instagram.com", "www.instagram.com"]
    public var hosts: Set<String> { Self.hosts }

    public static let homeURL = Self.constantURL("https://www.instagram.com/direct/inbox/")
    public var homeURL: URL { Self.homeURL }

    public func classify(path: String) -> RouteKind {
        if Self.path(path, isOrUnder: "/accounts/login")
            || Self.path(path, isOrUnder: "/accounts/onetap")
            || Self.path(path, isOrUnder: "/challenge") {
            return .auth
        }
        if Self.path(path, isOrUnder: "/direct") {
            return .dm
        }
        if Self.path(path, isOrUnder: "/reel")
            || Self.path(path, isOrUnder: "/p")
            || Self.path(path, isOrUnder: "/stories") {
            return .media
        }
        return .other
    }

    public var webScript: ChannelWebScript {
        ChannelWebScript(css: Self.css, inlineMediaHook: Self.inlineMediaHook, unreadFilterCSS: nil)
    }

    static let css = """
    a[href="/"],
    a[href^="/explore"],
    a[href^="/reels"],
    a[href^="/search"],
    a[href^="/accounts/activity"],
    a[aria-label="Home"],
    a[aria-label="Explore"],
    a[aria-label="Reels"],
    a[aria-label="Search"] {
        display: none !important;
        pointer-events: none !important;
    }

    nav[role="navigation"] a[href="/"],
    nav[role="navigation"] a[href^="/explore"],
    nav[role="navigation"] a[href^="/reels"],
    nav[role="navigation"] a[href^="/search"] {
        display: none !important;
    }
    """

    // A reel shared in a DM never navigates. Instagram mounts its reels feed
    // component inline in the /direct/t/<thread>/ route, so the URL does not change
    // and RouteFirewall is never given a decision to make. Verified on device: the
    // feed is a nested scroller (overflow-y: scroll, scroll-snap-type: y mandatory)
    // holding one full-bleed reel per snap point, with more appended as you scroll,
    // and no per-item permalink anywhere in its markup.
    //
    // Removing that one container's scrollable overflow strands the feed on the
    // shared reel. Scoped to the scroller itself rather than to gestures, so taps,
    // the native fullscreen player, and DM thread scrolling are all untouched.
    static let inlineMediaHook = """
    const FEED_LOCK_ATTRIBUTE = 'data-sidedoor-feed-locked';

    function lockInlineMedia() {
        const videos = document.querySelectorAll('video');
        for (const video of videos) {
            for (let element = video.parentElement;
                 element && element !== document.body;
                 element = element.parentElement) {
                if (element.hasAttribute(FEED_LOCK_ATTRIBUTE)) {
                    break;
                }

                const computed = window.getComputedStyle(element);
                if (!computed.scrollSnapType.startsWith('y')) {
                    continue;
                }
                if (computed.overflowY !== 'scroll' && computed.overflowY !== 'auto') {
                    continue;
                }

                // Scroll position is left alone: Instagram seeds the container on the
                // reel that was actually shared, which is not always the first item.
                element.style.setProperty('overflow-y', 'hidden', 'important');
                element.style.setProperty('scroll-snap-type', 'none', 'important');
                element.setAttribute(FEED_LOCK_ATTRIBUTE, 'true');
                break;
            }
        }
    }

    // 'present' if any locked container has a non-zero rect; 'hidden' when locked
    // containers exist but React has collapsed every one of them rather than
    // unmounting; 'absent' when none is in the document. "Any", not "the first":
    // a stale collapsed container ahead of a live one must not hide a feed the
    // user can see.
    function inlineMediaState() {
        const locked = document.querySelectorAll('[' + FEED_LOCK_ATTRIBUTE + ']');
        if (locked.length === 0) {
            return 'absent';
        }
        for (const element of locked) {
            const rect = element.getBoundingClientRect();
            if (rect.width > 0 && rect.height > 0) {
                return 'present';
            }
        }
        return 'hidden';
    }
    """
}
