import Foundation

/// Pulls the unread-DM count out of Instagram's badge GraphQL response without depending on
/// its exact shape: the first badge-like key with a numeric value wins.
enum BadgeParser {
    private static let countKeys: Set<String> = ["badge_count", "unseen_count", "unread_count", "total_count"]

    static func unreadCount(in data: Data) throws -> Int {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let count = search(root) else { throw CocoaError(.coderValueNotFound) }
        return count
    }

    private static func search(_ node: Any) -> Int? {
        switch node {
        case let dict as [String: Any]:
            for key in countKeys {
                if let value = dict[key] {
                    if let number = int(value) { return number }
                    if let nested = search(value) { return nested }
                }
            }
            for (_, value) in dict {
                if let nested = search(value) { return nested }
            }
            return nil
        case let array as [Any]:
            for value in array {
                if let nested = search(value) { return nested }
            }
            return nil
        default:
            return nil
        }
    }

    private static func int(_ value: Any) -> Int? {
        switch value {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }
}
