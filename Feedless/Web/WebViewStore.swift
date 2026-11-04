import Foundation
import WebKit
import Combine

/// Owns the single WKWebView for the app's lifetime so login and scroll state survive view updates.
@MainActor
final class WebViewStore: ObservableObject {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    let rules: PlatformRules
    let policy: NavigationPolicy
    let loader: RuleLoader
    let settings: Settings
    let webView: WKWebView

    @Published var canGoBack = false
    @Published private(set) var contentRuleList: WKContentRuleList?

    private var cancellables = Set<AnyCancellable>()
    private var appliedFeedID: String

    init(loader: RuleLoader, rules: PlatformRules, settings: Settings) {
        self.loader = loader
        self.rules = rules
        self.settings = settings
        policy = NavigationPolicy(rules: rules)
        appliedFeedID = settings.feedID

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = nil

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        installUserScripts()
        webView.publisher(for: \.canGoBack).assign(to: &$canGoBack)

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)

        Task { await compileContentRules() }
    }

    private func compileContentRules() async {
        guard let file = rules.contentRules else { return }
        do {
            let json = try loader.text(file)
            contentRuleList = try await ContentRuleCompiler.load(identifierPrefix: rules.id, json: json)
            updateContentRules()
        } catch {
            assertionFailure("Content rules failed to compile: \(error)")
        }
    }

    /// Ads category on: block requests from the rules file. Off: let them through.
    private func updateContentRules() {
        guard let list = contentRuleList else { return }
        let controller = webView.configuration.userContentController
        if settings.isEnabled("ads") {
            controller.add(list)
        } else {
            controller.remove(list)
        }
    }

    var startURL: URL { rules.startURL(feedID: settings.feedID) }

    func loadHome() {
        webView.load(URLRequest(url: startURL))
    }

    /// The search page keeps its search field; instagram.css drops the explore grid under it.
    func loadSearch() {
        webView.load(URLRequest(url: URL(string: "/explore/search/", relativeTo: rules.homeURL)!.absoluteURL))
    }

    func loadStartIfBlank() {
        if webView.url == nil { loadHome() }
    }

    /// Re-registers scripts for future navigations and pushes the config into the current page.
    func applySettings() {
        installUserScripts()
        updateContentRules()
        webView.evaluateJavaScript(settings.injectedConfig.updateSource())
        if settings.feedID != appliedFeedID {
            appliedFeedID = settings.feedID
            if webView.url?.path() == "/" { loadHome() }
        }
    }

    func resetSession() async {
        let store = webView.configuration.websiteDataStore
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records)
        loadHome()
    }

    private func installUserScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        do {
            for script in try loader.userScripts(rules: rules, config: settings.injectedConfig) {
                controller.addUserScript(script)
            }
        } catch {
            assertionFailure("Rule files missing: \(error)")
        }
    }
}
