import BackgroundTasks
import OSLog

/// iOS runs this a few times an hour at most, at its own discretion.
enum BackgroundRefresh {
    static let identifier = "com.mironable.feedless.refresh"
    private static let log = Logger(subsystem: "com.mironable.feedless", category: "background")

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task as! BGAppRefreshTask)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error("schedule failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        let work = Task { @MainActor in
            guard InboxPoller.shared.isEnabled else { task.setTaskCompleted(success: true); return }
            schedule()
            let result = await InboxPoller.shared.poll(notify: true)
            if case .success = result { task.setTaskCompleted(success: true) } else { task.setTaskCompleted(success: false) }
        }
        task.expirationHandler = { work.cancel() }
    }
}
