import Foundation
import UserNotifications

/// Local reminders: the day before and a few hours before each deadline.
enum NotificationService {
    // Seconds before the due time: 39h / 15h for all-day items, 24h / 3h for timed ones.
    private static let allDayOffsets: [(TimeInterval, String)] = [
        (-140_400, "is due tomorrow"),
        (-54_000, "is due today"),
    ]
    private static let timedOffsets: [(TimeInterval, String)] = [
        (-86_400, "is due in 24 hours"),
        (-10_800, "is due in 3 hours"),
    ]

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func isAllowed() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    static func clearDeadlines() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("due-") })
    }

    static func scheduleDeadlines(_ items: [StudyItem]) async {
        await clearDeadlines()
        guard await isAllowed() else { return }
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let upcoming = items.filter { $0.due > now }.sorted { $0.due < $1.due }.prefix(30)

        for item in upcoming {
            let offsets: [(TimeInterval, String)]
            if item.isAllDay {
                offsets = allDayOffsets
            } else {
                offsets = timedOffsets
            }
            for (offset, phrase) in offsets {
                let fire = item.due.addingTimeInterval(offset)
                guard fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = item.kind == .exam ? "📚 Exam coming up" : "⏰ Deadline reminder"
                content.body = "\(item.title) \(phrase)."
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let request = UNNotificationRequest(
                    identifier: "due-\(item.id)-\(Int(offset))",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                )
                try? await center.add(request)
            }
        }
    }

    /// A repeating 8 AM nudge to read the day's finance headlines.
    static func scheduleDailyNews(enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily-news"])
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "📈 Your daily finance briefing"
        content.body = "Today's market, economy and company headlines are ready in StudyHub."
        content.sound = .default
        var time = DateComponents()
        time.hour = 8
        time.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        center.add(UNNotificationRequest(identifier: "daily-news", content: content, trigger: trigger))
    }

    static func scheduleFocus(id: String, at date: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancelFocus() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["focus-end", "focus-break", "focus-break-end"]
        )
    }
}
