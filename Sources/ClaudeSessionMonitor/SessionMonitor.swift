import Foundation

final class SessionMonitor {
    private let client: CCUsageClient
    private let queue = DispatchQueue(label: "com.hussfelt.ClaudeSessionMonitor.poll", qos: .utility)
    private var timer: DispatchSourceTimer?

    /// Refresh cadence when an active session is present.
    private let activeInterval: TimeInterval = 60
    /// Refresh cadence when there's no active session.
    private let idleInterval: TimeInterval = 5 * 60

    private var currentInterval: TimeInterval = 60

    var onUpdate: ((MonitorState) -> Void)?

    init(client: CCUsageClient = CCUsageClient()) {
        self.client = client
    }

    func start() {
        scheduleNext(after: 0)
    }

    func refreshNow() {
        timer?.cancel()
        scheduleNext(after: 0)
    }

    private func scheduleNext(after delay: TimeInterval) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + delay)
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = t
        t.resume()
    }

    private func tick() {
        let state: MonitorState
        do {
            if let snapshot = try client.fetchActiveSnapshot() {
                state = .active(snapshot)
                currentInterval = activeInterval
            } else {
                state = .idle
                currentInterval = idleInterval
            }
        } catch {
            state = .error(error.localizedDescription)
            currentInterval = activeInterval // retry sooner on error
        }

        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(state)
        }

        scheduleNext(after: currentInterval)
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
