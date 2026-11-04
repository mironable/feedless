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
        // Instagram is a single-page app, so WebKit's own back gesture animates stale snapshots.
        // A plain edge swipe that asks the page to go back behaves like the native app.
        let edgeSwipe = UIScreenEdgePanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.edgeSwipe(_:)))
        edgeSwipe.edges = .left
        edgeSwipe.delegate = context.coordinator
        webView.addGestureRecognizer(edgeSwipe)
        store.loadStartIfBlank()
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: coordinator.store.rules.messageHandler)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UIGestureRecognizerDelegate {
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
            case "openSettings":
                NotificationCenter.default.post(name: AppDelegate.openSettingsNotification, object: nil)
            default:
                break
            }
        }

        private var swipeSnapshot: UIView?
        private var swipeDim: UIView?
        private var swipeWentBack = false

        /// Drags a snapshot of the current page aside. Once past the threshold the page itself goes
        /// back, so the real previous page is what gets revealed; letting go early goes forward again.
        @objc func edgeSwipe(_ recognizer: UIScreenEdgePanGestureRecognizer) {
            guard let view = recognizer.view, let container = view.superview else { return }
            let width = view.bounds.width
            let translation = max(0, recognizer.translation(in: view).x)
            switch recognizer.state {
            case .began:
                guard let snapshot = view.snapshotView(afterScreenUpdates: false) else { return }
                let dim = UIView(frame: view.frame)
                dim.backgroundColor = UIColor.black.withAlphaComponent(0.25)
                snapshot.frame = view.frame
                snapshot.layer.shadowColor = UIColor.black.cgColor
                snapshot.layer.shadowOpacity = 0.3
                snapshot.layer.shadowRadius = 8
                container.addSubview(dim)
                container.addSubview(snapshot)
                swipeDim = dim
                swipeSnapshot = snapshot
                swipeWentBack = false
            case .changed:
                guard let snapshot = swipeSnapshot else { return }
                snapshot.frame.origin.x = view.frame.origin.x + translation
                swipeDim?.alpha = 1 - translation / width
                if !swipeWentBack, translation > 60 {
                    swipeWentBack = true
                    store.webView.evaluateJavaScript("history.back()")
                }
            case .ended, .cancelled, .failed:
                guard let snapshot = swipeSnapshot else { return }
                let velocity = recognizer.velocity(in: view).x
                let complete = swipeWentBack && (translation > width * 0.35 || velocity > 300)
                if swipeWentBack, !complete {
                    store.webView.evaluateJavaScript("history.forward()")
                }
                let dim = swipeDim
                swipeSnapshot = nil
                swipeDim = nil
                UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                    snapshot.frame.origin.x = complete ? view.frame.origin.x + width : view.frame.origin.x
                    dim?.alpha = complete ? 0 : 1
                } completion: { _ in
                    snapshot.removeFromSuperview()
                    dim?.removeFromSuperview()
                }
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

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
