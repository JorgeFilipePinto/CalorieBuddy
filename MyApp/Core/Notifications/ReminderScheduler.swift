import Foundation
import UserNotifications

/// Schedules the free reminders as local notifications (the free developer account has no push):
/// the next days' occurrences are queued ahead, each asking "Já consumiste?". Answering "Sim" confirms
/// that window for the day and removes its remaining notifications. Rescheduled on open and after
/// every local change, so the queue always matches the reminders as they are.
enum ReminderScheduler {
    static let category = "REMINDER"
    static let confirmAction = "REMINDER_DONE"
    static let laterAction = "REMINDER_LATER"
    private static let prefix = "reminder-"
    /// iOS keeps at most 64 pending notifications per app; the pantry warnings use up to 30.
    private static let maxScheduled = 30
    private static let daysAhead = 7

    private static var store: DataStore?

    /// Registers the notification buttons and remembers the store the buttons act on.
    static func connect(store: DataStore) {
        self.store = store
        let done = UNNotificationAction(identifier: confirmAction, title: "Já consumi", options: [])
        let later = UNNotificationAction(identifier: laterAction, title: "Ainda não", options: [])
        let category = UNNotificationCategory(identifier: category, actions: [done, later], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func dayString(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    /// One planned notification.
    struct Occurrence: Equatable {
        var reminder: UUID
        var window: UUID
        var day: String
        var date: Date
        var title: String
        var body: String

        var identifier: String { "\(ReminderScheduler.prefix)\(reminder.uuidString)-\(day)-\(window.uuidString)-\(Int(date.timeIntervalSince1970))" }
        var windowPrefix: String { "\(ReminderScheduler.prefix)\(reminder.uuidString)-\(day)-\(window.uuidString)-" }
    }

    /// The occurrences from `now` on, nearest first, skipping disabled reminders, other weekdays and
    /// windows already confirmed for the day.
    static func occurrences(for reminders: [Reminder], from now: Date = .now, calendar: Calendar = .current) -> [Occurrence] {
        var result: [Occurrence] = []
        let today = calendar.startOfDay(for: now)
        for offset in 0..<daysAhead {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: dayStart)
            let day = dayString(dayStart)
            for reminder in reminders where reminder.isEnabled && reminder.weekdays.contains(weekday) {
                for window in reminder.windows where !reminder.isDone(day: day, window: window.id) {
                    for minute in window.fireMinutes {
                        guard let date = calendar.date(byAdding: .minute, value: minute, to: dayStart), date > now else { continue }
                        let note = reminder.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        result.append(Occurrence(reminder: reminder.id, window: window.id, day: day, date: date,
                                                 title: reminder.title, body: note.isEmpty ? "Já consumiste?" : "\(note) — já consumiste?"))
                    }
                }
            }
        }
        return Array(result.sorted { $0.date < $1.date }.prefix(maxScheduled))
    }

    /// Replaces the queued reminders with the ones the store now calls for.
    static func reschedule(store: DataStore) {
        let wanted = occurrences(for: store.reminders)
        let center = UNUserNotificationCenter.current()
        if !wanted.isEmpty {
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
        center.getPendingNotificationRequests { requests in
            let wantedIDs = Set(wanted.map(\.identifier))
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(prefix) && !wantedIDs.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            let existing = Set(requests.map(\.identifier))
            for occurrence in wanted where !existing.contains(occurrence.identifier) {
                let content = UNMutableNotificationContent()
                content.title = occurrence.title
                content.body = occurrence.body
                content.sound = .default
                content.categoryIdentifier = category
                content.userInfo = ["reminder": occurrence.reminder.uuidString, "window": occurrence.window.uuidString, "day": occurrence.day]
                var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: occurrence.date)
                components.second = 0
                center.add(UNNotificationRequest(identifier: occurrence.identifier, content: content,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            }
        }
    }

    /// A notification button was pressed.
    @MainActor
    static func handle(action: String, userInfo: [AnyHashable: Any]) {
        guard action == confirmAction,
              let reminder = (userInfo["reminder"] as? String).flatMap(UUID.init(uuidString:)),
              let window = (userInfo["window"] as? String).flatMap(UUID.init(uuidString:)),
              let day = userInfo["day"] as? String, let store else { return }
        store.confirmReminder(id: reminder, window: window, day: day)
        removeNotifications(reminder: reminder, window: window, day: day)
    }

    /// Removes what is queued or already shown for one window of one day.
    static func removeNotifications(reminder: UUID, window: UUID, day: String) {
        let prefix = "\(prefix)\(reminder.uuidString)-\(day)-\(window.uuidString)-"
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
        center.getDeliveredNotifications { delivered in
            center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) })
        }
    }
}
