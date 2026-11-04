import Foundation
import WebKit
import UserNotifications
import OSLog

/// Replays Instagram's own mailbox GraphQL request with the web view's cookies and raises a
/// local notification per thread with activity newer than the viewer's read watermark.
/// Instagram cannot push to a WKWebView, and this query is what its web client polls.
@MainActor
final class InboxPoller {
    static let shared = InboxPoller()

    struct CapturedRequest: Codable {
        var t: Double
        var url: String
        var headers: [String: String]
        var body: String?
        var response: String?
    }

    enum PollError: LocalizedError {
        case noCapturedRequest
        case notLoggedIn
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .noCapturedRequest: return "No badge request captured yet. Open the feed once with alerts on."
            case .notLoggedIn: return "No Instagram session cookie"
            case .http(let status, let snippet): return "HTTP \(status): \(snippet)"
            }
        }
    }

    private static let origin = URL(string: "https://www.instagram.com")!
    private let log = Logger(subsystem: "com.mironable.feedless", category: "inbox")
    private let defaults = UserDefaults.standard

    /// Supplied by the web view: Instagram's per-session claim header, kept in sessionStorage.
    var claimProvider: (() async -> String?)?
    /// Supplied by the web view: the latest badge request the page made.
    var captureProvider: (() async -> CapturedRequest?)?
    /// Supplied by the web view: thread id to title, learned as threads are opened.
    var namesProvider: (() async -> [String: String])?

    var isEnabled: Bool { defaults.bool(forKey: Keys.enabled) }

    private(set) var lastSummary: String {
        get { defaults.string(forKey: Keys.summary) ?? "Never polled" }
        set { defaults.set(newValue, forKey: Keys.summary) }
    }

    private var captured: CapturedRequest? {
        get { defaults.data(forKey: Keys.captured).flatMap { try? JSONDecoder().decode(CapturedRequest.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.captured) }
    }

    /// Last activity seen per thread id; alerts fire only for activity newer than this.
    private var seenActivity: [String: Int64] {
        get { (defaults.dictionary(forKey: Keys.seen) as? [String: NSNumber])?.mapValues { $0.int64Value } ?? [:] }
        set { defaults.set(newValue.mapValues { NSNumber(value: $0) }, forKey: Keys.seen) }
    }

    private var threadNames: [String: String] {
        get { defaults.dictionary(forKey: Keys.names) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Keys.names) }
    }

    /// Pulls the page's latest badge request and thread names into storage. Call while the web view is alive.
    func refreshCapture() async {
        if let fresh = await captureProvider?(), fresh.t > (captured?.t ?? 0) {
            captured = fresh
        }
        if let names = await namesProvider?(), !names.isEmpty {
            threadNames = threadNames.merging(names) { _, new in new }
        }
    }

    /// Fetch once. With `notify` false the count is recorded without alerts, used when the app
    /// goes to the background so messages already read in the app are not announced later.
    @discardableResult
    func poll(notify: Bool) async -> Result<MailboxSnapshot, Error> {
        await refreshCapture()
        do {
            let snapshot = try await fetchMailbox()
            var seen = seenActivity
            let firstRun = seen.isEmpty
            var alerted = 0
            for thread in snapshot.threads {
                let previous = seen[thread.id] ?? 0
                if notify, !firstRun, !thread.muted, thread.isUnread, thread.lastActivity > previous {
                    await post(thread: thread, viewerID: snapshot.viewerID)
                    alerted += 1
                }
                seen[thread.id] = max(previous, thread.lastActivity)
            }
            seenActivity = seen
            try? await UNUserNotificationCenter.current().setBadgeCount(snapshot.unreadCount)
            lastSummary = "\(Self.timeFormatter.string(from: .now)): \(snapshot.unreadCount) unread, \(alerted) alerted" + (notify ? "" : " (silent)")
            log.info("poll ok unread=\(snapshot.unreadCount) alerted=\(alerted)")
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

    private func fetchMailbox() async throws -> MailboxSnapshot {
        guard let captured else { throw PollError.noCapturedRequest }
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
            .filter { $0.domain.hasSuffix("instagram.com") }
        guard cookies.contains(where: { $0.name == "sessionid" && !$0.value.isEmpty }) else { throw PollError.notLoggedIn }

        let url = URL(string: captured.url, relativeTo: Self.origin)!.absoluteURL
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        for (key, value) in captured.headers where !["cookie", "content-length", "host"].contains(key.lowercased()) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        request.setValue(WebViewStore.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.instagram.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://www.instagram.com", forHTTPHeaderField: "Origin")
        if let csrf = cookies.first(where: { $0.name == "csrftoken" })?.value {
            request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
        }
        if let claim = await claimProvider?() {
            request.setValue(claim, forHTTPHeaderField: "X-IG-WWW-Claim")
        }
        request.httpBody = captured.body.map { Data($0.utf8) }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw PollError.http(status, String(decoding: data.prefix(200), as: UTF8.self).replacingOccurrences(of: "\n", with: " "))
        }
        do {
            return try MailboxParser.parse(data)
        } catch {
            throw PollError.http(status, "unexpected shape: " + String(decoding: data.prefix(200), as: UTF8.self))
        }
    }

    private func post(thread: MailboxThread, viewerID: String) async {
        let url = thread.webURL(viewerID: viewerID)
        let name = threadNames[thread.id] ?? threadNames[url.lastPathComponent]
        let content = UNMutableNotificationContent()
        content.title = name ?? "Instagram"
        content.body = name.map { "New message from \($0)" } ?? "New message"
        content.sound = .default
        content.threadIdentifier = thread.id
        content.userInfo = ["url": url.absoluteString]
        let request = UNNotificationRequest(identifier: "dm-\(thread.id)-\(thread.lastActivity)", content: content, trigger: nil)
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
        static let captured = "inboxBadgeRequest"
        static let seen = "inboxSeenActivity"
        static let names = "inboxThreadNames"
    }
}
