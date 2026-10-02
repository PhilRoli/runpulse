import AppKit
import UserNotifications

protocol NotificationScheduler {
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?)
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

extension UNUserNotificationCenter: NotificationScheduler {}

struct NotificationMessage: Equatable {
    var title: String
    var body: String
    var url: URL
}

@MainActor
final class NotificationManager {
    private let scheduler: NotificationScheduler
    private var authRequested = false

    init(scheduler: NotificationScheduler) {
        self.scheduler = scheduler
    }

    func post(_ events: [FinishedEvent], details: [String: FailedStep]) {
        let messages = events.compactMap { Self.message(for: $0.run, detail: details[$0.run.key]) }
        guard !messages.isEmpty else { return }
        requestAuthIfNeeded()
        for message in messages {
            let content = UNMutableNotificationContent()
            content.title = message.title
            content.body = message.body
            content.sound = .default
            content.userInfo = ["url": message.url.absoluteString]
            scheduler.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil),
                          withCompletionHandler: nil)
        }
    }

    /// Called at launch: requesting lazily inside `post` loses the first batch, because `add` runs before the
    /// user has answered the permission prompt.
    func requestAuthorization() {
        requestAuthIfNeeded()
    }

    /// nil for states that don't notify (still running, skipped, other).
    static func message(for run: Run, detail: FailedStep?) -> NotificationMessage? {
        let name = "\(run.repoName) · \(run.workflow)"
        let duration = Format.duration(run.updatedAt.timeIntervalSince(run.startedAt ?? run.createdAt))
        let branch = run.branch ?? ""
        let title: String
        let parts: [String]
        switch run.state {
        case .success:
            title = "✓ \(name) passed"
            parts = [branch, duration]
        case .failure:
            title = "✗ \(name) failed"
            parts = [detail?.label ?? "", branch]
        case .cancelled:
            title = "⊘ \(name) cancelled"
            parts = [branch, duration]
        case .queued, .inProgress, .skipped, .other:
            return nil
        }
        let body = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        return NotificationMessage(title: title, body: body, url: run.htmlURL)
    }

    private func requestAuthIfNeeded() {
        guard !authRequested else { return }
        authRequested = true
        Task { [scheduler] in _ = try? await scheduler.requestAuthorization(options: [.alert, .sound]) }
    }
}

/// Shows banners while RunPulse is frontmost and opens the run when a notification is clicked.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let raw = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
