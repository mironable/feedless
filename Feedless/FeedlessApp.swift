import SwiftUI

@main
struct FeedlessApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: Settings
    @StateObject private var store: WebViewStore

    init() {
        let loader = RuleLoader(platform: "instagram")
        let rules = try! loader.loadRules()
        let settings = Settings(rules: rules)
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: WebViewStore(loader: loader, rules: rules, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
        }
    }
}
