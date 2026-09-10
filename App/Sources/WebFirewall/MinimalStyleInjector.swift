import Foundation

enum MinimalStyleInjector {
    static let routeMessageName = "routeChanged"
    static let mediaSurfaceMessageName = "mediaSurfaceChanged"

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

    // The inline feed also mounts and leaves without a route change, so the native
    // shell has no other way to know it is showing media rather than a DM thread.
    // Reporting presence lets it raise the media banner and the Back to DMs escape
    // hatch that the URL-based path would otherwise have provided.
    //
    // Presence is re-derived from the DOM on every pass rather than latched: React
    // may unmount the container, or leave it mounted and hide it, and only one of
    // those trips a childList observer.
    let lastReportedMediaSurface = null;
    let presenceTimer = null;

    // Hiding the container without unmounting it changes no child list, so the
    // observer alone cannot see the feed go away. A slow timer covers that, and it
    // runs only while a locked container is in the document — the rest of the time
    // a new feed can only arrive as a child insertion, which the observer does see.
    function startPresenceTimer() {
        if (presenceTimer !== null) {
            return;
        }
        presenceTimer = window.setInterval(scheduleFeedLock, 500);
    }

    function stopPresenceTimer() {
        if (presenceTimer === null) {
            return;
        }
        window.clearInterval(presenceTimer);
        presenceTimer = null;
    }

    function reportMediaSurface() {
        const locked = document.querySelector('[' + FEED_LOCK_ATTRIBUTE + ']');
        let present = false;
        if (locked) {
            // Still in the document but collapsed means React hid it rather than
            // unmounting it: not present, but keep watching, since it can come back
            // without any child insertion to notice.
            const rect = locked.getBoundingClientRect();
            present = rect.width > 0 && rect.height > 0;
            startPresenceTimer();
        } else {
            stopPresenceTimer();
        }

        if (present === lastReportedMediaSurface) {
            return;
        }
        lastReportedMediaSurface = present;

        try {
            window.webkit.messageHandlers.mediaSurfaceChanged.postMessage(present);
        } catch (error) {
            return;
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
            reportMediaSurface();
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
