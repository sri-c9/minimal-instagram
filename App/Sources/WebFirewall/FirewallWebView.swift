import SidedoorCore
import SwiftUI
import WebKit

struct FirewallWebView: UIViewRepresentable {
    @ObservedObject var model: FirewallViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = model.dataStore
        configuration.allowsInlineMediaPlayback = false
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Every device gets the surface that was measured; WebKit's default serves
        // desktop web on most iPads (§6.10).
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile

        let userContentController = WKUserContentController()
        userContentController.addUserScript(
            WKUserScript(source: model.scriptSource,
                         injectionTime: .atDocumentEnd,
                         forMainFrameOnly: true)
        )
        userContentController.add(context.coordinator, name: FirewallScript.routeMessageName)
        userContentController.add(context.coordinator,
                                  name: FirewallScript.mediaSurfaceMessageName)
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        #if DEBUG
        // Safari Web Inspector attaches only to an inspectable WebView. Debug-only:
        // a shipped build must not expose the user's logged-in DM surface.
        webView.isInspectable = true
        #endif
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // The page lays itself out to the viewport and scrolls inside its own
        // containers, so the outer scroll view has nothing to scroll; bouncing is
        // what lets a pull at the top reach the refresh control at all.
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator,
                                 action: #selector(Coordinator.refresh),
                                 for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        webView.scrollView.alwaysBounceVertical = true

        context.coordinator.webView = webView
        context.coordinator.observeProgress(of: webView)
        model.webView = webView

        webView.load(URLRequest(url: model.resumeURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.model = model

        if let requestedURL = model.consumePendingLoadURL() {
            webView.load(URLRequest(url: requestedURL))
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // The replacement WebView may already have registered itself.
        if coordinator.model.webView === webView {
            coordinator.model.webView = nil
        }
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: FirewallScript.routeMessageName
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: FirewallScript.mediaSurfaceMessageName
        )
        webView.navigationDelegate = nil
        coordinator.progressObservation = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var model: FirewallViewModel
        weak var webView: WKWebView?
        var progressObservation: NSKeyValueObservation?

        init(model: FirewallViewModel) {
            self.model = model
        }

        func observeProgress(of webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                // WebKit posts this on the main thread; KVO does not carry the isolation.
                MainActor.assumeIsolated {
                    self?.model.loadProgress = webView.estimatedProgress
                }
            }
        }

        @objc func refresh() {
            webView?.reload()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.isLoading = true
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if let url = webView.url {
                model.observeCommittedURL(url)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.isLoading = false
            webView.scrollView.refreshControl?.endRefreshing()
            if let url = webView.url {
                model.observeCommittedURL(url)
            }
            model.reapplyUnreadFilterIfOn()
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            model.fail(error)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            model.fail(error)
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case FirewallScript.routeMessageName:
                handleRouteChanged(message.body)
            case FirewallScript.mediaSurfaceMessageName:
                handleMediaSurfaceChanged(message.body)
            default:
                return
            }
        }

        private func handleRouteChanged(_ body: Any) {
            guard let href = body as? String,
                  let url = URL(string: href) else { return }

            let decision = model.decision(for: url)
            switch decision {
            case .allow, .allowMedia:
                model.observeCommittedURL(url)
            case .block:
                webView?.stopLoading()
            }
        }

        private func handleMediaSurfaceChanged(_ body: Any) {
            // A JS boolean arrives bridged as NSNumber, not as a Swift Bool.
            guard let isPresent = (body as? NSNumber)?.boolValue else { return }
            model.observeInlineMediaSurface(isPresent: isPresent)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame ?? true else {
                decisionHandler(.allow)
                return
            }

            guard let targetURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let decision = model.decision(for: targetURL)
            switch decision {
            case .allow, .allowMedia:
                decisionHandler(.allow)
            case .block:
                decisionHandler(.cancel)
            }
        }
    }
}
