import Foundation

enum MinimalStyleInjector {
    static let routeMessageName = "routeChanged"

    static let source = #"""
(function() {
    if (window.__minimalInstagramFirewallInstalled === true) {
        return;
    }
    window.__minimalInstagramFirewallInstalled = true;

    const style = document.createElement('style');
    style.setAttribute('data-minimal-instagram', 'true');
    style.textContent = `
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

        body {
            overscroll-behavior: contain !important;
        }
    `;
    document.documentElement.appendChild(style);

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
    const FEED_LOCK_ATTRIBUTE = 'data-minimal-instagram-feed-locked';

    function lockReelFeedScrollers() {
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

    let feedLockScheduled = false;

    function scheduleFeedLock() {
        if (feedLockScheduled) {
            return;
        }
        feedLockScheduled = true;
        window.requestAnimationFrame(function() {
            feedLockScheduled = false;
            lockReelFeedScrollers();
        });
    }

    function notifyRouteChanged() {
        scheduleFeedLock();
        try {
            window.webkit.messageHandlers.routeChanged.postMessage(window.location.href);
        } catch (error) {
            return;
        }
    }

    function installHistoryObserver(methodName) {
        const original = history[methodName];
        history[methodName] = function() {
            const result = original.apply(this, arguments);
            window.setTimeout(notifyRouteChanged, 0);
            return result;
        };
    }

    installHistoryObserver('pushState');
    installHistoryObserver('replaceState');
    window.addEventListener('popstate', notifyRouteChanged);
    window.setTimeout(notifyRouteChanged, 0);

    // The feed mounts without a route change, so route notifications alone would
    // never catch it; the observer is what actually arms this.
    if (document.body) {
        new MutationObserver(scheduleFeedLock).observe(document.body, {
            childList: true,
            subtree: true
        });
    }
})();
"""#
}
