import Foundation

/// One DM worth notifying about.
struct InboxMessage: Equatable {
    let threadID: String
    let threadTitle: String
    let senderName: String
    let timestamp: Int64
    let body: String
}

struct InboxSnapshot: Equatable {
    let viewerID: String
    let unseenCount: Int
    let messages: [InboxMessage]

    var newestTimestamp: Int64 { messages.map(\.timestamp).max() ?? 0 }
}

/// Reads Instagram's direct_v2 inbox JSON. Everything is optional-chained because the
/// shape is undocumented and changes without notice.
enum InboxParser {
    static func parse(_ data: Data) throws -> InboxSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        let viewerID = string(root["viewer"].flatMap { ($0 as? [String: Any])?["pk"] }) ?? ""
        let inbox = root["inbox"] as? [String: Any] ?? [:]
        let unseen = inbox["unseen_count"] as? Int ?? 0
        let threads = inbox["threads"] as? [[String: Any]] ?? []

        var messages: [InboxMessage] = []
        for thread in threads {
            guard let threadID = string(thread["thread_id"]) else { continue }
            let users = thread["users"] as? [[String: Any]] ?? []
            let names = Dictionary(uniqueKeysWithValues: users.compactMap { user -> (String, String)? in
                guard let pk = string(user["pk"]) else { return nil }
                return (pk, string(user["username"]) ?? "")
            })
            let title = string(thread["thread_title"]).flatMap { $0.isEmpty ? nil : $0 }
                ?? names.values.sorted().joined(separator: ", ")
            let items = thread["items"] as? [[String: Any]] ?? []
            for item in items {
                guard let sender = string(item["user_id"]), sender != viewerID,
                      let timestamp = int64(item["timestamp"]) else { continue }
                messages.append(InboxMessage(
                    threadID: threadID,
                    threadTitle: title,
                    senderName: names[sender] ?? title,
                    timestamp: timestamp,
                    body: body(of: item)
                ))
            }
        }
        return InboxSnapshot(viewerID: viewerID, unseenCount: unseen, messages: messages)
    }

    /// Messages newer than `after`, oldest first, one per thread at most (the newest).
    static func newMessages(in snapshot: InboxSnapshot, after: Int64) -> [InboxMessage] {
        var newestPerThread: [String: InboxMessage] = [:]
        for message in snapshot.messages where message.timestamp > after {
            if let existing = newestPerThread[message.threadID], existing.timestamp >= message.timestamp { continue }
            newestPerThread[message.threadID] = message
        }
        return newestPerThread.values.sorted { $0.timestamp < $1.timestamp }
    }

    private static func body(of item: [String: Any]) -> String {
        let type = string(item["item_type"]) ?? ""
        switch type {
        case "text":
            return string(item["text"]) ?? "New message"
        case "media":
            return "Sent a photo"
        case "voice_media":
            return "Sent a voice message"
        case "raven_media":
            return "Sent a view-once photo"
        case "clip", "reel_share":
            return "Shared a reel"
        case "media_share", "xma_media_share":
            return "Shared a post"
        case "story_share", "xma_story_share":
            return "Shared a story"
        case "animated_media":
            return "Sent a GIF"
        case "like":
            return "❤️"
        case "link":
            return ((item["link"] as? [String: Any])?["text"] as? String) ?? "Sent a link"
        default:
            return "New message"
        }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let n as NSNumber: return n.int64Value
        case let s as String: return Int64(s)
        default: return nil
        }
    }
}
