import SwiftUI
import WebKit
import SafariServices
import OSLog

struct WebContainerView: UIViewRepresentable {
    @ObservedObject var store: WebViewStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = store.webView
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.configuration.userContentController.add(context.coordinator, name: store.rules.messageHandler)
        store.loadStartIfBlank()
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: coordinator.store.rules.messageHandler)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let store: WebViewStore
        private let log = Logger(subsystem: "com.mironable.feedless", category: "navigation")

        init(store: WebViewStore) {
            self.store = store
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
            guard let url = action.request.url else { return (.allow, preferences) }
            let isMainFrame = action.targetFrame?.isMainFrame ?? true
            guard isMainFrame else { return (.allow, preferences) }
            log.debug("main frame -> \(url.absoluteString, privacy: .public)")

            if !store.policy.isInternal(url) {
                if url.scheme == "http" || url.scheme == "https" {
                    present(SFSafariViewController(url: url), over: webView)
                } else if url.scheme != "about" {
                    await UIApplication.shared.open(url)
                }
                return (.cancel, preferences)
            }
            if let rewritten = store.policy.rewrittenHomeURL(for: url, preferredFeedID: store.settings.feedID) {
                webView.load(URLRequest(url: rewritten))
                return (.cancel, preferences)
            }
            return (.allow, preferences)
        }

        /// target=_blank links: keep internal ones in the same web view.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let url = action.request.url else { return nil }
            if store.policy.isInternal(url) {
                webView.load(URLRequest(url: url))
            } else {
                present(SFSafariViewController(url: url), over: webView)
            }
            return nil
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "openInApp":
                openInNativeApp(pageURL: message.frameInfo.request.url ?? store.webView.url)
            default:
                break
            }
        }

        private func openInNativeApp(pageURL: URL?) {
            guard let pageURL, let threadID = NavigationPolicy.threadID(from: pageURL) else { return }
            let deepLink = NavigationPolicy.deepLink(threadID: threadID)
            UIApplication.shared.open(deepLink) { opened in
                if !opened { UIApplication.shared.open(pageURL) }
            }
        }

        private func present(_ controller: UIViewController, over view: UIView) {
            var top = view.window?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            top?.present(controller, animated: true)
        }
    }
}
