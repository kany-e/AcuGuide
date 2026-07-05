import Foundation
import UserNotifications

// Optional daily practice reminder — one local notification, scheduled on-device (consistent with
// the no-server posture). Copy stays inside the wellness rules. Sync is idempotent: it always
// removes the pending request first, then re-schedules if enabled and authorized.
enum PracticeReminder {
    static let requestId = "acuguide.practice.reminder"

    // Enable/disable + (re)schedule at `minutes` past midnight. Calls back with whether notifications
    // are authorized (so Settings can flip the toggle back off and hint at system Settings).
    static func sync(on: Bool, minutes: Int, completion: @escaping (Bool) -> Void = { _ in }) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestId])
        guard on else { completion(true); return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { DispatchQueue.main.async { completion(false) }; return }
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
            DispatchQueue.main.async { completion(true) }
        }
    }
}
