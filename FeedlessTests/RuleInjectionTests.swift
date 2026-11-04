import XCTest
import WebKit
@testable import Feedless

@MainActor
final class RuleInjectionTests: XCTestCase {
    private var webView: WKWebView!
    private var delegate: LoadDelegate!

    private final class LoadDelegate: NSObject, WKNavigationDelegate {
        var onFinish: (() -> Void)?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish?() }
    }

    override func setUp() async throws {
        let loader = RuleLoader(platform: "instagram")
        let rules = try loader.loadRules()
        let config = InjectedConfig(platform: rules.id, feed: "following", categories: Dictionary(uniqueKeysWithValues: rules.categories.map { ($0.id, true) }))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        for script in try loader.userScripts(rules: rules, config: config) {
            configuration.userContentController.addUserScript(script)
        }
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        delegate = LoadDelegate()
        webView.navigationDelegate = delegate

        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "instagram-home", withExtension: "html", subdirectory: "Fixtures"))
        let html = try String(contentsOf: fixture, encoding: .utf8)
        let loaded = expectation(description: "fixture loaded")
        delegate.onFinish = { loaded.fulfill() }
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.instagram.com/?variant=following"))
        await fulfillment(of: [loaded], timeout: 10)
        // Let the debounced observer run once.
        try await Task.sleep(for: .milliseconds(500))
    }

    private func display(_ selector: String) async throws -> String {
        let script = "(function(){var e=document.querySelector(\(RuleLoader.jsLiteral(selector)));return e?getComputedStyle(e).display:'missing';})()"
        return try await webView.evaluateJavaScript(script) as! String
    }

    private func assertDisplay(_ selector: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let actual = try await display(selector)
            XCTAssertEqual(actual, expected, selector, file: file, line: line)
        } catch {
            XCTFail("\(selector): \(error)", file: file, line: line)
        }
    }

    func testReelsAndSearchTabsHidden() async throws {
        await assertDisplay("#nav-reels", "none")
        await assertDisplay("#nav-explore", "none")
        await assertDisplay("#nav-home", "inline")
        await assertDisplay("#nav-direct", "inline")
    }

    func testExploreGridHiddenOnlyOnExplorePath() async throws {
        await assertDisplay("#post-1-link", "inline")
        _ = try await webView.evaluateJavaScript("document.documentElement.setAttribute('data-fl-path', '/explore/'); true")
        await assertDisplay("#post-1-link", "none")
    }

    func testFeedSelectorIsHidden() async throws {
        await assertDisplay("header svg[aria-label=\"Down chevron icon\"]", "none")
        await assertDisplay("#feed-menu", "none")
    }

    func testFeedBlocksFlaggedByScript() async throws {
        await assertDisplay("#sponsored", "none")
        await assertDisplay("#reels-rail", "none")
        await assertDisplay("#suggested-accounts", "none")
        await assertDisplay("#stories", "none")
        await assertDisplay("#post-1", "block")
        await assertDisplay("#post-2", "block")
    }

    func testDisablingACategoryRestoresWithoutReload() async throws {
        let config = InjectedConfig(platform: "instagram", feed: "following", categories: ["reels": false, "explore": true, "suggested": true, "ads": true, "stories": true])
        _ = try await webView.evaluateJavaScript(config.updateSource() + "; true")
        await assertDisplay("#nav-reels", "inline")
        await assertDisplay("#reels-rail", "block")
        await assertDisplay("#nav-explore", "none")
        await assertDisplay("#sponsored", "none")
    }

    func testHomeLinksPointAtChosenFeed() async throws {
        let href = try await webView.evaluateJavaScript("document.querySelector('#nav-home').getAttribute('href')") as? String
        XCTAssertEqual(href, "/?variant=following")
        let stillHome = try await webView.evaluateJavaScript("location.pathname") as? String
        XCTAssertEqual(stillHome, "/")
    }

    func testSettingsGearInjectedBeforeNewPost() async throws {
        let script = """
        (function () {
          var gear = document.getElementById('feedless-settings');
          if (!gear) { return 'missing'; }
          var cells = Array.from(document.querySelectorAll('#header-actions a'));
          return cells.map(function (a) { return a.id || a.getAttribute('href'); }).join(',');
        })()
        """
        let order = try await webView.evaluateJavaScript(script) as? String
        XCTAssertEqual(order, "feedless-settings,#,/notifications/")
    }

    func testPathAttributeTracksLocation() async throws {
        let path = try await webView.evaluateJavaScript("document.documentElement.getAttribute('data-fl-path')") as? String
        XCTAssertEqual(path, "/")
    }
}
