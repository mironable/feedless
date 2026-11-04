import Foundation

/// Pure URL decisions, kept free of WebKit so they can be unit tested.
struct NavigationPolicy {
    let rules: PlatformRules

    /// Hosts the web view may navigate to itself; everything else goes to Safari.
    func isInternal(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return url.scheme == "about" }
        return rules.hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Returns the URL the main frame should load instead, or nil to leave the navigation alone.
    /// Only the site root is rewritten: no variant, or a variant other than a known feed,
    /// becomes the preferred feed.
    func rewrittenHomeURL(for url: URL, preferredFeedID: String) -> URL? {
        guard isInternal(url), url.path == "/" || url.path.isEmpty else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let variant = components?.queryItems?.first { $0.name == "variant" }?.value
        if let variant, rules.feeds.contains(where: { $0.id == variant }) { return nil }
        var target = URLComponents(url: rules.startURL(feedID: preferredFeedID), resolvingAgainstBaseURL: false)!
        target.host = url.host()
        return target.url
    }

    /// Thread id from /direct/t/<id>/.
    static func threadID(from url: URL) -> String? {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "direct"), parts.count > index + 2, parts[index + 1] == "t" else { return nil }
        let id = parts[index + 2]
        return id.isEmpty ? nil : id
    }

    static func deepLink(threadID: String) -> URL {
        URL(string: "instagram://direct/t/\(threadID)")!
    }
}
