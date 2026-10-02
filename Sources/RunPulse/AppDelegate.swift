import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AppConfigStore()
    private let keychain = KeychainTokenStore()
    private lazy var tokens = CompositeTokenProvider(keychain: keychain)
    private let client = GitHubClient()
    private var config = AppConfig()
    private lazy var poller = Poller(client: client, tokens: tokens, config: config)
    private let statusBar = StatusBarController()
    private let presenter = NotificationPresenter()
    private lazy var notifications = NotificationManager(scheduler: UNUserNotificationCenter.current())
    private var lastSuccessAt: Date?
    private var failureUnacknowledged = false
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        UNUserNotificationCenter.current().delegate = presenter
        notifications.requestAuthorization()
        config = store.load()

        statusBar.rows = { [unowned self] in MenuModel.rows(state: self.poller.state) }
        statusBar.onRefresh = { [unowned self] in self.poller.refreshNow() }
        statusBar.onPreferences = { [unowned self] in self.showPreferences() }
        statusBar.onMenuOpened = { [unowned self] in
            self.failureUnacknowledged = false
            self.render()
        }
        poller.onUpdate = { [unowned self] _ in self.render() }
        poller.onFinished = { [unowned self] events, details in self.handle(events, details) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.poller.didWake() }
        }

        poller.start()
        render()
    }

    private func handle(_ events: [FinishedEvent], _ details: [String: FailedStep]) {
        for event in events {
            switch event.run.state {
            case .failure: failureUnacknowledged = true
            case .success: lastSuccessAt = Date()
            default: break
            }
        }
        if config.notificationsEnabled {
            notifications.post(events, details: details)
        }
        render()
    }

    private func render() {
        let state = poller.state
        let input = TitleInput(status: state.status, runningCount: state.running.count,
                               lastSuccessAt: lastSuccessAt, failureUnacknowledged: failureUnacknowledged)
        statusBar.setTitle(StatusTitle.make(input, now: Date()))
    }

    private func showPreferences() {
        // Implemented in Task 10.
    }
}
