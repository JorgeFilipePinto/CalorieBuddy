import Foundation
import SwiftUI

/// Usage events, stored in the platform's `app_events` table (they used to go to Firebase
/// Analytics).
///
/// Deliberately never includes nutrition values, body measurements or anything read from Apple
/// Health — only *what kind* of action happened (e.g. "a recipe was logged at lunch").
enum AppEvent {
    enum EntrySource: String {
        case manual, barcode, catalog, recipe, mealPlan = "meal_plan", supplement, aiImport = "ai_import"
    }

    case entryLogged(source: EntrySource, mealType: MealType?)
    case mealPlanOptionLogged(meal: String, option: String, substitutions: Int, amountChanges: Int)
    case foodSubstituted(macro: Macro)
    case mealPlanImported
    case mealPlanExported
    case databaseImported
    case databaseExported
    case personalRecordsViewed
    case screenViewed(String)
    case platformSync(automatic: Bool, succeeded: Bool)
    case platformRestore(succeeded: Bool)

    var name: String {
        switch self {
        case .entryLogged: return "entry_logged"
        case .mealPlanOptionLogged: return "meal_plan_option_logged"
        case .foodSubstituted: return "food_substituted"
        case .mealPlanImported: return "meal_plan_imported"
        case .mealPlanExported: return "meal_plan_exported"
        case .databaseImported: return "database_imported"
        case .databaseExported: return "database_exported"
        case .personalRecordsViewed: return "personal_records_viewed"
        case .screenViewed: return "screen_view"
        case .platformSync: return "platform_sync"
        case .platformRestore: return "platform_restore"
        }
    }

    var parameters: [String: Any] {
        switch self {
        case .entryLogged(let source, let mealType):
            var parameters: [String: Any] = ["source": source.rawValue]
            if let mealType { parameters["meal_type"] = mealType.rawValue }
            return parameters
        case .mealPlanOptionLogged(let meal, let option, let substitutions, let amountChanges):
            return ["meal": meal, "option": option, "substitutions": substitutions, "amount_changes": amountChanges]
        case .foodSubstituted(let macro):
            return ["macro": macro.rawValue]
        case .screenViewed(let screen):
            return ["screen": screen]
        case .platformSync(let automatic, let succeeded):
            return ["automatic": automatic, "succeeded": succeeded]
        case .platformRestore(let succeeded):
            return ["succeeded": succeeded]
        case .mealPlanImported, .mealPlanExported, .databaseImported, .databaseExported, .personalRecordsViewed:
            return [:]
        }
    }
}

/// Queues events locally (offline-first, like the rest of the app); `PlatformSyncManager` sends
/// them to `app_events` on the next sync.
enum AppAnalytics {
    private static let enabledKey = "CalorieBuddy.analyticsEnabled"
    /// Oldest events are dropped beyond this, so a long offline stretch can't grow the file forever.
    private static let maxQueued = 5000

    /// Whether usage statistics are recorded. On by default; can be turned off in Definições.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if !newValue { savePending([]) }
        }
    }

    static func log(_ event: AppEvent) {
        guard isEnabled, JSONSerialization.isValidJSONObject(event.parameters) else { return }
        var pending = loadPending()
        pending.append(PendingEvent(id: UUID(), name: event.name, parameters: event.parameters, occurredAt: .now))
        savePending(Array(pending.suffix(maxQueued)))
    }

    static func logScreen(_ name: String) {
        log(.screenViewed(name))
    }

    // MARK: Queue

    struct PendingEvent {
        let id: UUID
        let name: String
        let parameters: [String: Any]
        let occurredAt: Date

        /// The `app_events` row.
        var row: [String: Any] {
            ["id": id.uuidString, "name": name, "params": parameters, "occurred_at": SupabaseClient.timestamp(occurredAt)]
        }
    }

    private static var queueURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("CalorieBuddy/pending_events.json")
    }

    static func loadPending() -> [PendingEvent] {
        guard let data = try? Data(contentsOf: queueURL),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let name = row["name"] as? String,
                  let occurredAt = (row["occurred_at"] as? String).flatMap(SupabaseClient.date(fromTimestamp:)) else { return nil }
            return PendingEvent(id: id, name: name, parameters: row["params"] as? [String: Any] ?? [:], occurredAt: occurredAt)
        }
    }

    private static func savePending(_ events: [PendingEvent]) {
        guard let data = try? JSONSerialization.data(withJSONObject: events.map(\.row)) else { return }
        try? data.write(to: queueURL, options: .atomic)
    }

    /// Removes events that were sent (by id), keeping any logged meanwhile.
    static func removeSent(_ ids: Set<UUID>) {
        savePending(loadPending().filter { !ids.contains($0.id) })
    }
}

extension View {
    /// Records this screen each time it appears (SwiftUI screens aren't tracked automatically).
    func trackScreen(_ name: String) -> some View {
        onAppear { AppAnalytics.logScreen(name) }
    }
}
