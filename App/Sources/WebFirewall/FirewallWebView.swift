import IGCore
import SwiftUI
import WebKit

struct FirewallWebView: UIViewRepresentable {
    @ObservedObject var model: FirewallViewModel
    let reloadToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.webView = webView
        context.coordinator.reloadToken = reloadToken

        webView.load(URLRequest(url: model.homeURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.model = model

        if context.coordinator.reloadToken != reloadToken {
            context.coordinator.reloadToken = reloadToken
            webView.load(URLRequest(url: model.homeURL))
            return
        }

        if let requestedURL = model.consumePendingLoadURL() {
            webView.load(URLRequest(url: requestedURL))
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var model: FirewallViewModel
        weak var webView: WKWebView?
        var reloadToken: UUID?

        init(model: FirewallViewModel) {
            self.model = model
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
            if let url = webView.url {
                model.observeCommittedURL(url)
            }
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            model.fail(error)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            model.fail(error)
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
