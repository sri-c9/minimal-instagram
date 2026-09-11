import Foundation

/// Composes the user script the shell injects at document end in the main frame.
/// Shared parts (install guard, style injection, history hooks, the two message
/// posts, the scheduler, the presence timer) are here; the channel supplies CSS,
/// an optional inline-media hook, and an optional unread-filter stylesheet.
public enum FirewallScript {
    public static let routeMessageName = "routeChanged"
    public static let mediaSurfaceMessageName = "mediaSurfaceChanged"

    public static func compose(for channel: any Channel) -> String {
        let script = channel.webScript
        let parts = [
            "(function() {",
            prelude(css: script.css, unreadFilterCSS: script.unreadFilterCSS),
            script.inlineMediaHook ?? defaultHook,
            bridge,
            epilogue(installsObserver: script.inlineMediaHook != nil),
            "})();"
        ]
        return parts.joined(separator: "\n\n")
    }

    /// The one Swift→JS call in the app. Safe to evaluate on any page the script
    /// has run on: `setUnreadFilter` is always defined, as a no-op when the
    /// channel has no unread filter.
    public static func setUnreadFilterExpression(_ on: Bool) -> String {
        "window.__sidedoor.setUnreadFilter(\(on ? "true" : "false"));"
    }

    // MARK: - Parts

    static let defaultHook = """
    function lockInlineMedia() {}
    function inlineMediaState() { return 'absent'; }
    """

    static let noOpUnreadFilter = "window.__sidedoor = { setUnreadFilter: function() {} };"

    static let observerInstall = """
    // The inline feed mounts without a route change, so route notifications
    // alone would never catch it; the observer is what actually arms this.
    if (document.body) {
        new MutationObserver(scheduleSurfaceCheck).observe(document.body, {
            childList: true,
            subtree: true
        });
    }
    """

    /// JSON-encodes the string. A JSON string literal is a valid JS string
    /// literal, so backticks, backslashes, `${`, quotes, and U+2028/2029 in
    /// channel CSS cannot break out of the script.
    static func jsStringLiteral(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed]),
              let literal = String(data: data, encoding: .utf8) else {
            preconditionFailure("A Swift String is always JSON-encodable")
        }
        return literal
    }

    private static func prelude(css: String, unreadFilterCSS: String?) -> String {
        var lines = [
            "if (window.__sidedoorInstalled === true) {",
            "    return;",
            "}",
            "window.__sidedoorInstalled = true;",
            "",
            "const style = document.createElement('style');",
            "style.setAttribute('data-sidedoor', 'true');",
            "style.textContent = \(jsStringLiteral(css))",
            "    + '\\nbody { overscroll-behavior: contain !important; }';",
            "document.documentElement.appendChild(style);"
        ]

        if let unreadFilterCSS {
            lines += [
                "",
                "// Appended first, disabled second: a style element's disabled flag lives",
                "// on its sheet, which only exists once the element is in the document.",
                "const unreadStyle = document.createElement('style');",
                "unreadStyle.setAttribute('data-sidedoor-unread', 'true');",
                "unreadStyle.textContent = \(jsStringLiteral(unreadFilterCSS));",
                "document.documentElement.appendChild(unreadStyle);",
                "unreadStyle.disabled = true;",
                "window.__sidedoor = {",
                "    setUnreadFilter: function(on) {",
                "        unreadStyle.disabled = !on;",
                "    }",
                "};"
            ]
        } else {
            lines += ["", noOpUnreadFilter]
        }

        return lines.joined(separator: "\n")
    }

    private static let bridge = """
    // Presence is re-derived from the DOM on every pass rather than latched: a
    // page may unmount an inline feed, or leave it mounted and hide it, and only
    // one of those trips a childList observer. Hiding changes no child list, so
    // a slow timer covers it, running only while a locked surface exists.
    let lastReportedMediaSurface = null;
    let presenceTimer = null;
    let surfaceCheckScheduled = false;

    function startPresenceTimer() {
        if (presenceTimer !== null) {
            return;
        }
        presenceTimer = window.setInterval(scheduleSurfaceCheck, 500);
    }

    function stopPresenceTimer() {
        if (presenceTimer === null) {
            return;
        }
        window.clearInterval(presenceTimer);
        presenceTimer = null;
    }

    // A throw anywhere here skips the rest of the pass with no state, timer, or
    // deduplication change; the next mutation or tick simply retries.
    function runSurfaceCheck() {
        lockInlineMedia();
        const state = inlineMediaState();
        if (state === 'absent') {
            stopPresenceTimer();
        } else {
            startPresenceTimer();
        }

        const present = state === 'present';
        if (present === lastReportedMediaSurface) {
            return;
        }
        window.webkit.messageHandlers.mediaSurfaceChanged.postMessage(present);
        lastReportedMediaSurface = present;
    }

    function scheduleSurfaceCheck() {
        if (surfaceCheckScheduled) {
            return;
        }
        surfaceCheckScheduled = true;
        window.requestAnimationFrame(function() {
            surfaceCheckScheduled = false;
            try {
                runSurfaceCheck();
            } catch (error) {
                return;
            }
        });
    }

    function postRoute() {
        scheduleSurfaceCheck();
        try {
            window.webkit.messageHandlers.routeChanged.postMessage(window.location.href);
        } catch (error) {
            return;
        }
    }
    """

    private static func epilogue(installsObserver: Bool) -> String {
        let history = """
        function installHistoryObserver(methodName) {
            const original = history[methodName];
            history[methodName] = function() {
                const result = original.apply(this, arguments);
                window.setTimeout(postRoute, 0);
                return result;
            };
        }

        installHistoryObserver('pushState');
        installHistoryObserver('replaceState');
        window.addEventListener('popstate', postRoute);
        window.setTimeout(postRoute, 0);
        """
        return installsObserver ? history + "\n\n" + observerInstall : history
    }
}
