import Foundation

struct PlatformRules: Codable, Equatable {
    struct Feed: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let path: String
    }

    struct Category: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let detail: String
    }

    let id: String
    let name: String
    let hosts: [String]
    let homeURL: URL
    let css: String?
    let js: String?
    let contentRules: String?
    let messageHandler: String
    let feeds: [Feed]
    let categories: [Category]

    var defaultFeed: Feed { feeds[0] }

    func feed(id: String) -> Feed {
        feeds.first { $0.id == id } ?? defaultFeed
    }

    func startURL(feedID: String) -> URL {
        URL(string: feed(id: feedID).path, relativeTo: homeURL)!.absoluteURL
    }
}
