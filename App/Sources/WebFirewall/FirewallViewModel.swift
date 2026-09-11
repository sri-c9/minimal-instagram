import Combine
import Foundation
import SidedoorCore
import WebKit

/// Thin observable wrapper over `FirewallSurface` for one channel. Everything that
/// decides *what* the shell shows lives in `SidedoorCore`; this holds only what
/// needs a main actor and a WebView: loading state, the pending load, the data
/// store, the unread-filter preference, and a weak handle to the WebView so the
/// root can pause media when the channel stops being active.
@MainActor
final class FirewallViewModel: ObservableObject {
    let channel: ChannelID
    let dataStore: WKWebsiteDataStore
    let scriptSource: String

    @Published private(set) var surface: FirewallSurface
    @Published var isLoading = false
    @Published var reloadToken = UUID()
    @Published private(set) var isUnreadFilterOn: Bool

    /// Set by `FirewallWebView.makeUIView`, cleared by `dismantleUIView`.
    weak var webView: WKWebView?

    private var pendingLoadURL: URL?
    private let unreadFilterKey: String

    init(channel: ChannelID) {
        self.channel = channel
        surface = FirewallSurface(channel: channel)
        dataStore = WKWebsiteDataStore(forIdentifier: channel.webStoreIdentifier)
        scriptSource = FirewallScript.compose(for: channel.channel)

        let key = "unreadFilter.\(channel.rawValue)"
        unreadFilterKey = key
        isUnreadFilterOn = UserDefaults.standard.bool(forKey: key)
    }

    var displayName: String { channel.channel.displayName }

    var homeURL: URL { channel.channel.homeURL }

    /// Where a freshly built WebView starts: the last DM route, or home. Read by
    /// `makeUIView` only; a channel switch never rebuilds the WebView.
    var resumeURL: URL { surface.backToDMsURL() }

    var offersUnreadFilter: Bool { channel.channel.webScript.unreadFilterCSS != nil }

    var screen: FirewallScreenState { surface.screen }

    var showsBackToDMs: Bool { surface.showsBackToDMs }

    func decision(for targetURL: URL) -> RouteDecision {
        let decision = surface.decide(for: targetURL)
        if case .block = decision {
            isLoading = false
        }
        return decision
    }

    func observeCommittedURL(_ url: URL) {
        surface.observeCommittedURL(url)
    }

    func observeInlineMediaSurface(isPresent: Bool) {
        surface.observeInlineMediaSurface(isPresent: isPresent)
    }

    func fail(_ error: Error) {
        isLoading = false
        guard !error.isNavigationCancellation else { return }
        surface.fail(error.localizedDescription)
    }

    func backToDMs() {
        load(surface.backToDMsURL())
    }

    func reloadHome() {
        load(homeURL)
    }

    func consumePendingLoadURL() -> URL? {
        let url = pendingLoadURL
        pendingLoadURL = nil
        return url
    }

    /// Stops audio and video in this channel's page. The only thing the app does
    /// to a channel that is no longer the active tab.
    func pauseMedia() {
        webView?.pauseAllMediaPlayback(completionHandler: nil)
    }

    func setUnreadFilter(_ isOn: Bool) {
        isUnreadFilterOn = isOn
        UserDefaults.standard.set(isOn, forKey: unreadFilterKey)
        applyUnreadFilter()
    }

    /// A full navigation reinstalls the user script with the filter off, so the
    /// stored preference is re-applied when the page finishes loading.
    func reapplyUnreadFilterIfOn() {
        guard isUnreadFilterOn else { return }
        applyUnreadFilter()
    }

    func logout() {
        isLoading = true
        dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                             modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                self.pendingLoadURL = nil
                self.surface.reset()
                self.reloadToken = UUID()
            }
        }
    }

    private func applyUnreadFilter() {
        // The only Swift→JS call in the app. An error is ignored on purpose: before
        // the user script has run there is no `__sidedoor` yet, and `didFinish`
        // re-applies the stored preference.
        webView?.evaluateJavaScript(FirewallScript.setUnreadFilterExpression(isUnreadFilterOn),
                                    completionHandler: nil)
    }

    private func load(_ url: URL) {
        pendingLoadURL = url
        isLoading = true
        surface.prepareLoad()
    }
}

private extension Error {
    var isNavigationCancellation: Bool {
        let error = self as NSError
        return NavigationFailure.isCancellation(domain: error.domain, code: error.code)
    }
}
