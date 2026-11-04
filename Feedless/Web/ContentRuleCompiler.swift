import Foundation
import WebKit
import CryptoKit

/// Compiles a rules file once and reuses the cached list on later launches.
/// The cache key includes a hash of the file so an edited rules file recompiles.
enum ContentRuleCompiler {
    static func load(identifierPrefix: String, json: String) async throws -> WKContentRuleList {
        let store = WKContentRuleListStore.default()!
        let identifier = identifierPrefix + "-" + SHA256.hash(data: Data(json.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        if let cached = try? await store.contentRuleList(forIdentifier: identifier) {
            return cached
        }
        guard let compiled = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) else {
            throw CocoaError(.coderInvalidValue)
        }
        let stale = (try? await store.availableIdentifiers())?.filter { $0.hasPrefix(identifierPrefix + "-") && $0 != identifier } ?? []
        for old in stale {
            try? await store.removeContentRuleList(forIdentifier: old)
        }
        return compiled
    }
}
