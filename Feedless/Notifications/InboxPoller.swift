import Foundation
import WebKit
import UserNotifications
import OSLog

/// Polls Instagram's inbox with the web view's cookies and raises local notifications for new DMs.
/// Instagram cannot push to a WKWebView, so this is the only route; expect minutes of latency.
@MainActor
final class InboxPoller {
    static let shared = InboxPoller()

    enum PollError: LocalizedError {
        case notEnabled
        case notLoggedIn
        case http([String])

        var errorDescription: String? {
            switch self {
            case .notEnabled: return "Message alerts are off"
            case .notLoggedIn: return "No Instagram session cookie"
            case .http(let attempts): return attempts.joined(separator: "; ")
            }
        }
    }

    /// Known inbox endpoints, tried in order until one answers 200. The web client has moved
    /// between these hosts over the years.
    private static let candidates: [(label: String, url: URL)] = [
        ("www", URL(string: "https://www.instagram.com/api/v1/direct_v2/inbox/?persistentBadging=true&folder=&limit=20&thread_message_limit=10")!),
        ("i", URL(string: "https://i.instagram.com/api/v1/direct_v2/inbox/?persistentBadging=true&folder=&limit=20&thread_message_limit=10")!),
    ]
    private static let webAppID = "936619743392459"
    private static let asbdID = "129477"

    /// Supplied by the web view: Instagram's per-session claim header, kept in sessionStorage.
    var claimProvider: (() async -> String?)?
    private let log = Logger(subsystem: "com.mironable.feedless", category: "inbox")
    private let defaults = UserDefaults.standard

    var isEnabled: Bool { defaults.bool(forKey: Keys.enabled) }

    private(set) var lastSummary: String {
        get { defaults.string(forKey: Keys.summary) ?? "Never polled" }
        set { defaults.set(newValue, forKey: Keys.summary) }
    }

    private var baseline: Int64 {
        get { Int64(defaults.integer(forKey: Keys.baseline)) }
        set { defaults.set(Int(newValue), forKey: Keys.baseline) }
    }

    /// Fetch once. With `notify` false the baseline moves without alerts, used when the app
    /// goes to the background so messages already read in the app are not announced later.
    @discardableResult
    func poll(notify: Bool) async -> Result<InboxSnapshot, Error> {
        do {
            let snapshot = try await fetchInbox()
            let fresh = InboxParser.newMessages(in: snapshot, after: baseline)
            if notify, baseline > 0 {
                for message in fresh { await post(message) }
            }
            baseline = max(baseline, snapshot.newestTimestamp)
            try? await UNUserNotificationCenter.current().setBadgeCount(snapshot.unseenCount)
            lastSummary = "\(Self.timeFormatter.string(from: .now)): \(snapshot.unseenCount) unseen, \(fresh.count) new" + (notify ? "" : " (silent)")
            log.info("poll ok unseen=\(snapshot.unseenCount) new=\(fresh.count)")
            return .success(snapshot)
        } catch {
            lastSummary = "\(Self.timeFormatter.string(from: .now)): \(error.localizedDescription)"
            log.error("poll failed: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    private func fetchInbox() async throws -> InboxSnapshot {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
            .filter { $0.domain.hasSuffix("instagram.com") }
        guard cookies.contains(where: { $0.name == "sessionid" && !$0.value.isEmpty }) else { throw PollError.notLoggedIn }
        let csrf = cookies.first { $0.name == "csrftoken" }?.value ?? ""
        let claim = await claimProvider?() ?? "0"

        var attempts: [String] = []
        let preferred = defaults.integer(forKey: Keys.endpoint)
        let order = Array(Self.candidates.indices).sorted { ($0 == preferred ? 0 : 1, $0) < ($1 == preferred ? 0 : 1, $1) }
        for index in order {
            let candidate = Self.candidates[index]
            var request = URLRequest(url: candidate.url, timeoutInterval: 20)
            request.httpShouldHandleCookies = false
            request.setValue(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
            request.setValue(WebViewStore.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(Self.webAppID, forHTTPHeaderField: "X-IG-App-ID")
            request.setValue(Self.asbdID, forHTTPHeaderField: "X-ASBD-ID")
            request.setValue(claim, forHTTPHeaderField: "X-IG-WWW-Claim")
            request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            request.setValue("https://www.instagram.com/direct/inbox/", forHTTPHeaderField: "Referer")
            request.setValue("*/*", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                defaults.set(index, forKey: Keys.endpoint)
                return try InboxParser.parse(data)
            }
            let snippet = String(decoding: data.prefix(80), as: UTF8.self).replacingOccurrences(of: "\n", with: " ")
            attempts.append("\(candidate.label) HTTP \(status) \(snippet)")
        }
        throw PollError.http(attempts)
    }

    private func post(_ message: InboxMessage) async {
        let content = UNMutableNotificationContent()
        content.title = message.threadTitle
        content.subtitle = message.senderName == message.threadTitle ? "" : message.senderName
        content.body = message.body
        content.sound = .default
        content.threadIdentifier = message.threadID
        content.userInfo = ["threadID": message.threadID]
        let request = UNNotificationRequest(identifier: "dm-\(message.threadID)-\(message.timestamp)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private enum Keys {
        static let enabled = "dmNotifications"
        static let summary = "inboxLastSummary"
        static let baseline = "inboxBaseline"
        static let endpoint = "inboxEndpoint"
    }
}
