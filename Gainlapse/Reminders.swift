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

    private static let recapIdentifier = "recap"

    /// Tells the user a milestone recap is ready, this evening or tomorrow morning if it's already late.
    static func scheduleRecap(weeks: Int) async {
        guard await status() == .authorized else { return }
        let calendar = Calendar.current
        let now = Date.now
        var date = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? now
        if date.timeIntervalSince(now) < 30 * 60 {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
        let content = UNMutableNotificationContent()
        content.title = "\(ProgressStore.recapTitle(weeks)): your recap is ready"
        content.body = "See \(weeks) weeks side by side, then share it if you like."
        content.sound = .default
        content.userInfo = ["kind": "recap"]
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: recapIdentifier, content: content, trigger: trigger))
    }

    static func cancelRecap() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [recapIdentifier])
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
