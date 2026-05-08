import Foundation
import UserNotifications

final class NotificationManager: NSObject {
    private let thresholds: [Double] = [80, 90, 95, 100]

    /// Per-block memory of which thresholds we've already fired.
    private var firedThresholds: [String: Set<Double>] = [:]
    private var lastBlockId: String?
    private var authorized = false

    func requestAuthorization() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            self?.authorized = granted
            if let error {
                NSLog("Notification auth error: \(error)")
            }
        }
    }

    func evaluate(snapshot: SessionSnapshot) {
        // Detect a new 5-hour block.
        if let lastId = lastBlockId, lastId != snapshot.blockId {
            firedThresholds.removeValue(forKey: lastId)
            sendReset()
        }
        lastBlockId = snapshot.blockId

        var fired = firedThresholds[snapshot.blockId, default: []]
        for threshold in thresholds where snapshot.currentPercent >= threshold && !fired.contains(threshold) {
            fired.insert(threshold)
            sendThreshold(threshold, snapshot: snapshot)
        }
        firedThresholds[snapshot.blockId] = fired
    }

    private func sendReset() {
        post(
            id: "reset-\(UUID().uuidString)",
            title: "Claude session reset",
            body: "A new 5-hour usage window just started."
        )
    }

    private func sendThreshold(_ threshold: Double, snapshot: SessionSnapshot) {
        let title: String
        let body: String
        switch threshold {
        case 100:
            title = "Claude session at 100%"
            body = "You've hit the cap for this 5-hour window. Further messages may be throttled."
        case 95:
            title = "Claude session at 95%"
            body = "Almost out of headroom for this window. Wrap up soon."
        case 90:
            title = "Claude session at 90%"
            body = "Heads up — you're close to the cap."
        default:
            title = "Claude session at 80%"
            body = "Burn rate alert — you've used 80% of this 5-hour window."
        }
        let endStr = DateFormatter.localizedString(from: snapshot.endTime, dateStyle: .none, timeStyle: .short)
        post(
            id: "threshold-\(snapshot.blockId)-\(Int(threshold))",
            title: title,
            body: "\(body) Resets at \(endStr)."
        )
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Notification post error: \(error)")
            }
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    // Show notifications even when our app is "frontmost" (we're a menu bar app, but still).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
