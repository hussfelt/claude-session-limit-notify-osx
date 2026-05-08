import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var notifications: NotificationManager?
    private var monitor: SessionMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusBar = StatusBarController()
        let notifications = NotificationManager()
        let monitor = SessionMonitor()

        notifications.requestAuthorization()

        statusBar.refreshHandler = { [weak monitor] in
            monitor?.refreshNow()
        }

        monitor.onUpdate = { [weak statusBar, weak notifications] state in
            statusBar?.render(state: state)
            if case .active(let snapshot) = state {
                notifications?.evaluate(snapshot: snapshot)
            }
        }

        statusBar.render(state: .loading)
        monitor.start()

        self.statusBar = statusBar
        self.notifications = notifications
        self.monitor = monitor
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }
}
