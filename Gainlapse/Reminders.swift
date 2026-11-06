import Foundation
import UserNotifications

enum Reminders {
    private static let identifierPrefix = "progress-photo-"

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks for permission if iOS hasn't asked yet, then schedules reminders for these photo days.
    static func requestAndSchedule(dates: [Date]) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        await schedule(dates: dates)
    }

    /// Updates reminders without prompting. Individual dates are used instead of a weekly repeat
    /// because the first week can be longer than seven days.
    static func reschedule(dates: [Date]) async {
        guard await status() == .authorized else { return }
        await schedule(dates: dates)
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix(identifierPrefix) })
    }

    private static func schedule(dates: [Date]) async {
        let center = UNUserNotificationCenter.current()
        await cancelAll()
        let calendar = Calendar.current
        for (index, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "It's progress pic day"
            content.body = "Take this week's photo and keep your timelapse going."
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "\(identifierPrefix)\(index)", content: content, trigger: trigger))
        }
    }
}
