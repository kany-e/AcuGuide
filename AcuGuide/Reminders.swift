import Foundation
import UserNotifications

// Foreground presentation: without a delegate, iOS silently swallows a reminder that fires while
// the app is open — the user simply loses that day's nudge (review-caught). Installed once at app
// start; a static keeps the delegate reference alive (the center holds it weakly).
final class ReminderPresentation: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderPresentation()
    func install() { UNUserNotificationCenter.current().delegate = self }
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

// Optional daily practice reminder — one local notification, scheduled on-device (consistent with
// the no-server posture). Copy stays inside the wellness rules. Sync is idempotent: it always
// removes the pending request first, then re-schedules if enabled and authorized.
enum PracticeReminder {
    static let requestId = "acuguide.practice.reminder"

    // Serializes overlapping syncs: each call invalidates the ones in flight, so a stale
    // requestAuthorization callback (e.g. the user toggled OFF while the system dialog was up,
    // then tapped Allow) can no longer re-schedule a reminder the newer sync already removed.
    // Main-thread only (called from Settings UI).
    private static var generation = 0

    // Enable/disable + (re)schedule at `minutes` past midnight. Calls back with whether notifications
    // are authorized (so Settings can flip the toggle back off and hint at system Settings).
    static func sync(on: Bool, minutes: Int, completion: @escaping (Bool) -> Void = { _ in }) {
        generation += 1
        let gen = generation
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestId])
        guard on else { completion(true); return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                guard gen == Self.generation else { return }   // superseded — do NOT (re)schedule
                guard granted else { completion(false); return }
                let content = UNMutableNotificationContent()
                content.title = "AcuGuide"
                content.body = AppLocale.pick("给自己几分钟，做一组温和的穴位按压。",
                                              "A few quiet minutes for gentle acupressure?")
                content.sound = .default
                var comps = DateComponents()
                comps.hour = minutes / 60
                comps.minute = minutes % 60
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                center.add(UNNotificationRequest(identifier: requestId, content: content, trigger: trigger))
                completion(true)
            }
        }
    }
}
