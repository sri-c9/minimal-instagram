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

    function notifyRouteChanged() {
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
})();
"""#
}
