import Foundation
import Combine

/// User preferences backed by UserDefaults.
@MainActor
final class Settings: ObservableObject {
    private let defaults: UserDefaults
    private let rules: PlatformRules

    @Published var feedID: String {
        didSet { defaults.set(feedID, forKey: Keys.feed) }
    }

    @Published private(set) var enabledCategories: [String: Bool] {
        didSet { defaults.set(enabledCategories, forKey: Keys.categories) }
    }

    @Published var showTouches: Bool {
        didSet { defaults.set(showTouches, forKey: Keys.showTouches) }
    }

    @Published var dmNotifications: Bool {
        didSet { defaults.set(dmNotifications, forKey: Keys.dmNotifications) }
    }

    init(rules: PlatformRules, defaults: UserDefaults = .standard) {
        self.rules = rules
        self.defaults = defaults
        let storedFeed = defaults.string(forKey: Keys.feed) ?? rules.defaultFeed.id
        feedID = rules.feeds.contains { $0.id == storedFeed } ? storedFeed : rules.defaultFeed.id
        let stored = defaults.dictionary(forKey: Keys.categories) as? [String: Bool] ?? [:]
        enabledCategories = Dictionary(uniqueKeysWithValues: rules.categories.map { ($0.id, stored[$0.id] ?? true) })
        showTouches = defaults.bool(forKey: Keys.showTouches)
        dmNotifications = defaults.bool(forKey: Keys.dmNotifications)
    }

    func isEnabled(_ categoryID: String) -> Bool {
        enabledCategories[categoryID] ?? true
    }

    func setEnabled(_ enabled: Bool, for categoryID: String) {
        enabledCategories[categoryID] = enabled
    }

    var injectedConfig: InjectedConfig {
        InjectedConfig(platform: rules.id, feed: feedID, categories: enabledCategories)
    }

    private enum Keys {
        static let feed = "feed"
        static let categories = "categories"
        static let showTouches = "showTouches"
        static let dmNotifications = "dmNotifications"
    }
}
