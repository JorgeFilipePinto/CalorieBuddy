import Foundation
import UserNotifications

/// Expiry warnings for the food stock, as local notifications: one when the app opens if
/// something is expiring (at most once an hour, so coming back from another app doesn't repeat
/// it), plus one scheduled per day ahead at 09:00 for what starts expiring that day — so it also
/// arrives when the app isn't opened.
enum PantryExpiryAlerts {
    private static let lastAlertKey = "CalorieBuddy.lastPantryExpiryAlert"
    private static let scheduledPrefix = "pantry-expiry-"
    private static let minimumInterval: TimeInterval = 60 * 60

    /// On opening the app.
    static func appDidOpen(store: DataStore) {
        reschedule(store: store)
        let expiring = store.expiringPantryLots()
        guard !expiring.isEmpty else { return }
        let last = UserDefaults.standard.object(forKey: lastAlertKey) as? Date
        if let last, Date.now.timeIntervalSince(last) < minimumInterval { return }
        UserDefaults.standard.set(Date.now, forKey: lastAlertKey)
        post(title: title(for: expiring), body: body(for: expiring), identifier: "pantry-open-alert", trigger: nil)
    }

    /// Replaces the scheduled warnings with ones for the stock as it is now (after any change).
    static func reschedule(store: DataStore) {
        let calendar = Calendar.current
        let warningDays = store.expiryWarningDays
        let today = calendar.startOfDay(for: .now)

        // Lots by the day their warning starts (`warningDays` before they expire).
        var byDay: [Date: [String]] = [:]
        for lot in store.pantryLots {
            guard let expiresOn = lot.expiresOn,
                  let food = store.foodItems.first(where: { $0.id == lot.foodItemID }),
                  let day = calendar.date(byAdding: .day, value: -warningDays, to: calendar.startOfDay(for: expiresOn)),
                  day > today else { continue }
            byDay[day, default: []].append(food.name)
        }

        // iOS keeps at most 64 pending notifications per app: the nearest days are enough.
        let days = Array(byDay.keys.sorted().prefix(30))
        let wanted = Set(days.map { identifier(for: $0) })
        let prefix = scheduledPrefix
        // Same identifier = replaced; the ones for days no longer needed are removed.
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(prefix) && !wanted.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        for day in days {
            let names = Array(Set(byDay[day] ?? [])).sorted()
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = 9
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let body = warningDays == 0
                ? "Expira hoje: \(names.joined(separator: ", "))."
                : "Expira daqui a \(warningDays) \(warningDays == 1 ? "dia" : "dias"): \(names.joined(separator: ", "))."
            post(title: "Validade a Terminar", body: body,
                 identifier: identifier(for: day), trigger: trigger)
        }
    }

    private static func identifier(for day: Date) -> String {
        scheduledPrefix + day.formatted(.iso8601.year().month().day())
    }

    private static func title(for lots: [ExpiringLot]) -> String {
        lots.contains { $0.daysLeft < 0 } ? "Alimentos Fora de Validade" : "Validade a Terminar"
    }

    private static func body(for lots: [ExpiringLot]) -> String {
        let shown = lots.prefix(4).map { "\($0.food.name) (\($0.label))" }
        let more = lots.count > 4 ? " e mais \(lots.count - 4)" : ""
        return shown.joined(separator: ", ") + more + "."
    }

    private static func post(title: String, body: String, identifier: String, trigger: UNNotificationTrigger?) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }
}

/// Lets the app's local notifications show as banners while it's open too (iOS hides them by
/// default when the app is in the foreground) — the expiry warning fires right as it opens.
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotificationPresenter()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
