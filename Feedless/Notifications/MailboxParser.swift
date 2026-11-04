import Foundation

/// A thread from Instagram's mailbox query: ids and timestamps only, no names or text.
struct MailboxThread: Equatable {
    let id: String
    let lastActivity: Int64
    let viewerWatermark: Int64
    let markedUnread: Bool
    let muted: Bool
    let participantIDs: [String]

    var isUnread: Bool { markedUnread || lastActivity > viewerWatermark }

    /// Instagram's web URL uses the other person's id for a 1:1 thread and the thread id for a group.
    func webURL(viewerID: String) -> URL {
        let others = participantIDs.filter { $0 != viewerID }
        let pathID = others.count == 1 ? others[0] : id
        return URL(string: "https://www.instagram.com/direct/t/\(pathID)/")!
    }
}

struct MailboxSnapshot: Equatable {
    let viewerID: String
    let threads: [MailboxThread]

    var unreadCount: Int { threads.filter { $0.isUnread && !$0.muted }.count }
}

/// Reads the IGDBadgeCountOffMsysQuery response. Everything is optional-chained because the
/// shape is undocumented and changes without notice.
enum MailboxParser {
    static func parse(_ data: Data) throws -> MailboxSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let mailbox = payload["get_slide_mailbox_for_iris_subscription"] as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        let viewerID = string(mailbox["id"]) ?? ""
        let edges = (mailbox["threads_by_folder"] as? [String: Any])?["edges"] as? [[String: Any]] ?? []
        let threads = edges.compactMap { edge -> MailboxThread? in
            guard let node = edge["node"] as? [String: Any],
                  let thread = node["as_ig_direct_thread"] as? [String: Any],
                  let id = string(thread["id"]) ?? string(node["id"]) else { return nil }
            let receipts = thread["slide_read_receipts"] as? [[String: Any]] ?? []
            let viewerWatermark = receipts
                .first { string($0["participant_fbid"]) == viewerID }
                .flatMap { int64($0["watermark_timestamp_ms"]) } ?? 0
            return MailboxThread(
                id: id,
                lastActivity: int64(thread["last_activity_timestamp_ms"]) ?? 0,
                viewerWatermark: viewerWatermark,
                markedUnread: thread["marked_as_unread"] as? Bool ?? false,
                muted: thread["is_muted"] as? Bool ?? false,
                participantIDs: receipts.compactMap { string($0["participant_fbid"]) }
            )
        }
        return MailboxSnapshot(viewerID: viewerID, threads: threads)
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
