import CryptoKit
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

enum PlatformSyncError: LocalizedError {
    /// First sync from this install, but the platform already holds a backup (another iPhone, a
    /// reinstall): syncing now would replace it, so the user has to choose.
    case serverHasBackup
    case noServerBackup

    var errorDescription: String? {
        switch self {
        case .serverHasBackup:
            return "Já existe um backup desta app na plataforma. Restaura-o primeiro, ou escolhe substituí-lo pelos dados deste iPhone."
        case .noServerBackup:
            return "Ainda não existe nenhum backup desta app na plataforma."
        }
    }
}

/// Keeps the app and the platform (the `Api` Supabase project that the dashboard reads) in sync.
/// Replaces the old Firebase backup: the app stays offline-first (everything is saved to the local
/// JSON first) and each sync sends only what changed, signed in as the athlete.
///
/// One sync, in order:
/// 1. **Nutrition plans, both ways** — pulls the plans (the nutritionist edits them on the
///    dashboard), then pushes local changes through `save_nutrition_plan()`. A plan changed on
///    both sides keeps the most recent edit.
/// 2. **App data, up** — every record of the app database (except the plans) goes to
///    `app_documents` as the app encodes it, a lossless backup to restore from; the diary and the
///    catalog also go to the typed `food_entries` / `food_items` the dashboard reads. Only records
///    whose hash changed since the last sync are sent; records deleted locally are soft-deleted.
/// 3. **Apple Health, up** — from the last synced moment (minus a few days, for data the Watch
///    delivers late), window by window through `sync_health_samples()` / `sync_workouts()`.
/// 4. Usage events, then one `app_syncs` row, which the dashboard shows as "last synced".
@Observable
final class PlatformSyncManager {
    private static let autoSyncKey = "CalorieBuddy.autoPlatformSync"
    private static let batchSize = 500
    /// Ids per `in.(…)` filter, to keep request URLs short.
    private static let idsPerFilter = 100
    /// History sent the first time Apple Health is synced.
    private static let healthBackfillDays = 90
    /// Days re-sent on every sync, for data other apps/the Watch write late.
    private static let healthOverlapDays = 3
    /// The database accepts at most 62 days per call.
    private static let healthWindowDays = 30

    let client: SupabaseClient
    private(set) var lastSync: Date?
    private(set) var isBusy = false
    private(set) var lastError: String?
    /// Problems that didn't stop the sync (e.g. a plan the platform refused).
    private(set) var warnings: [String] = []
    private(set) var lastSummary: String?

    /// Whether the app syncs by itself when it opens and when it goes to the background.
    var autoSyncEnabled: Bool = UserDefaults.standard.object(forKey: PlatformSyncManager.autoSyncKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoSyncEnabled, forKey: Self.autoSyncKey) }
    }

    init(client: SupabaseClient = SupabaseClient()) {
        self.client = client
        lastSync = PlatformSyncState.load().lastSync
    }

    var isAvailable: Bool { client.isConfigured }

    // MARK: Sync

    /// Syncs everything (see the type's documentation). `replacingServerBackup` is the user's
    /// explicit choice after `PlatformSyncError.serverHasBackup`.
    func sync(store: DataStore, healthKit: HealthKitManager, automatic: Bool = false,
              replacingServerBackup: Bool = false) async throws {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            guard client.isSignedIn else { throw SupabaseError.notSignedIn }
            var state = PlatformSyncState.load()
            var newWarnings: [String] = []

            let plans = try await syncNutritionPlans(store: store, state: &state, warnings: &newWarnings)
            state.save()
            let documents = try await pushDocuments(store.databaseSnapshot(), state: &state,
                                                    replacingServerBackup: replacingServerBackup)
            state.save()
            let health = try await pushHealth(healthKit, state: &state)
            try await flushEvents()

            let summary = [
                "\(documents.entries) registos do diário", "\(documents.other) outros registos",
                "\(health.samples) amostras e \(health.workouts) treinos da app Saúde",
                "\(plans.pulled) planos recebidos", "\(plans.pushed) planos enviados"
            ]
            try await client.upsert("app_syncs", rows: [[
                "id": UUID().uuidString,
                "app_version": Self.appVersion,
                "stats": ["entries": documents.entries, "documents": documents.other,
                          "health_samples": health.samples, "workouts": health.workouts,
                          "plans_pulled": plans.pulled, "plans_pushed": plans.pushed]
            ]], onConflict: "id")

            state.lastSync = .now
            state.save()
            lastSync = state.lastSync
            lastSummary = "Enviados/recebidos: " + summary.joined(separator: ", ") + "."
            warnings = newWarnings
            lastError = nil
            AppAnalytics.log(.platformSync(automatic: automatic, succeeded: true))
        } catch {
            lastError = error.localizedDescription
            AppAnalytics.log(.platformSync(automatic: automatic, succeeded: false))
            throw error
        }
    }

    /// Automatic sync — silently skipped when disabled, signed out, busy, or synced less than
    /// `minimumInterval` ago. Errors stay visible in the sync screen.
    func autoSyncIfEnabled(store: DataStore, healthKit: HealthKitManager, minimumInterval: TimeInterval = 0) async {
        guard isAvailable, client.isSignedIn, autoSyncEnabled, !isBusy else { return }
        if let lastSync, Date().timeIntervalSince(lastSync) < minimumInterval { return }
        #if canImport(UIKit)
        // Ask iOS for a little extra time so the sync can finish after the app is backgrounded.
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "PlatformSync")
        defer { UIApplication.shared.endBackgroundTask(taskID) }
        #endif
        try? await sync(store: store, healthKit: healthKit, automatic: true)
    }

    // MARK: Restore

    /// Replaces the local database with the backup on the platform (the current one is kept as the
    /// local backup, exactly like importing a file). Apple Health isn't touched.
    func restore(into store: DataStore) async throws {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            guard client.isSignedIn else { throw SupabaseError.notSignedIn }
            let rows = try await client.selectRows("app_documents", select: "collection,id,data",
                                                   filters: ["deleted_at": "is.null"], order: "collection,id")
            guard !rows.isEmpty else { throw PlatformSyncError.noServerBackup }
            let plans = try await fetchRemotePlans().compactMap(\.plan)

            func decode<T: Decodable>(_ collection: String, as type: T.Type) throws -> [T] {
                try rows.filter { $0["collection"] as? String == collection }.map { row in
                    let data = try JSONSerialization.data(withJSONObject: row["data"] ?? [:])
                    return try SupabaseClient.jsonDecoder.decode(T.self, from: data)
                }
            }
            let database = AppDatabase(
                version: AppDatabase.currentVersion,
                exportedAt: .now,
                settings: try decode(AppCollection.settings, as: UserSettings.self).first ?? .default,
                entries: try decode(AppCollection.entries, as: FoodEntry.self),
                foodItems: try decode(AppCollection.foodItems, as: FoodItem.self),
                recipes: try decode(AppCollection.recipes, as: Recipe.self),
                stores: try decode(AppCollection.stores, as: Store.self),
                supplementCategories: try decode(AppCollection.supplementCategories, as: SupplementCategory.self),
                supplements: try decode(AppCollection.supplements, as: Supplement.self),
                supplementLogs: try decode(AppCollection.supplementLogs, as: SupplementLogEntry.self),
                stockLocations: try decode(AppCollection.stockLocations, as: StockLocation.self),
                mealPlans: try decode(AppCollection.mealPlan, as: MealPlan.self),
                nutritionPlans: plans,
                bodyMeasurements: try decode(AppCollection.bodyMeasurements, as: BodyMeasurement.self),
                progressPhotos: try decode(AppCollection.progressPhotos, as: ProgressPhoto.self)
            )
            store.replaceDatabase(with: database)

            // What's local now is exactly what's on the platform.
            var state = PlatformSyncState.load()
            state.documentHashes = [:]
            for collection in AppCollection.all(of: database) {
                state.documentHashes[collection.name] = try Dictionary(
                    uniqueKeysWithValues: collection.documents.map { ($0.id, try Self.hash($0.value)) }
                )
            }
            state.planHashes = try Dictionary(uniqueKeysWithValues: plans.map { ($0.id.uuidString, try Self.hash($0)) })
            state.save()
            lastError = nil
            AppAnalytics.log(.platformRestore(succeeded: true))
        } catch {
            lastError = error.localizedDescription
            AppAnalytics.log(.platformRestore(succeeded: false))
            throw error
        }
    }

    // MARK: Nutrition plans (both ways)

    private func syncNutritionPlans(store: DataStore, state: inout PlatformSyncState,
                                    warnings: inout [String]) async throws -> (pulled: Int, pushed: Int) {
        let remotePlans = try await fetchRemotePlans().compactMap(\.plan)
        let remoteByID = Dictionary(uniqueKeysWithValues: remotePlans.map { ($0.id, $0) })

        // Pull: take the platform's version unless this iPhone changed the plan more recently.
        var pulled: [NutritionPlan] = []
        for remote in remotePlans {
            let key = remote.id.uuidString
            guard let local = store.nutritionPlans.first(where: { $0.id == remote.id }) else {
                pulled.append(remote)
                continue
            }
            if Self.sameContent(local, remote) {
                state.planHashes[key] = try Self.hash(local)
                continue
            }
            let editedHere = try state.planHashes[key] != Self.hash(local)
            if editedHere && local.updatedAt > remote.updatedAt { continue }
            pulled.append(remote)
        }
        store.applyRemoteNutritionPlans(pulled)
        for plan in pulled { state.planHashes[plan.id.uuidString] = try Self.hash(plan) }

        // Push: whatever changed here since the last sync.
        var pushed = 0
        for plan in store.nutritionPlans {
            let hash = try Self.hash(plan)
            guard state.planHashes[plan.id.uuidString] != hash else { continue }
            do {
                if plan.deletedAt != nil {
                    // Never reached the platform, or already deleted there: nothing to send.
                    if remoteByID[plan.id]?.deletedAt == nil, remoteByID[plan.id] != nil {
                        try await client.update("nutrition_plans",
                                                filters: ["id": "eq.\(plan.id.uuidString)", "deleted_at": "is.null"],
                                                values: ["deleted_at": SupabaseClient.timestamp(plan.deletedAt ?? .now)])
                        pushed += 1
                    }
                } else {
                    try await client.rpc("save_nutrition_plan", object: [
                        "p_id": plan.id.uuidString,
                        "p_name": plan.name,
                        "p_starts_on": Self.dayString(plan.startsOn),
                        "p_ends_on": plan.endsOn.map(Self.dayString) ?? NSNull(),
                        "p_priority": plan.priority,
                        "p_notes": plan.notes ?? "",
                        "p_training": Self.targetsObject(plan.training),
                        "p_rest": Self.targetsObject(plan.rest)
                    ])
                    pushed += 1
                }
                state.planHashes[plan.id.uuidString] = hash
            } catch let error as SupabaseError {
                switch error.code {
                case "P0002":
                    // Deleted on the dashboard meanwhile: follow the platform.
                    if let remote = remoteByID[plan.id] {
                        store.applyRemoteNutritionPlans([remote])
                        state.planHashes[plan.id.uuidString] = try Self.hash(remote)
                    }
                default:
                    warnings.append("O plano “\(plan.name)” não foi enviado: \(error.localizedDescription)")
                }
            }
        }
        return (pulled.count, pushed)
    }

    private func fetchRemotePlans() async throws -> [RemotePlan] {
        try await client.select(
            "nutrition_plans", as: RemotePlan.self,
            select: "id,name,starts_on,ends_on,priority,notes,created_at,updated_at,deleted_at,nutrition_targets(day_type,kcal,protein_g,carbs_g,fat_g,water_ml)",
            order: "starts_on,id"
        )
    }

    /// Same plan as far as the user is concerned (timestamps aside).
    private static func sameContent(_ a: NutritionPlan, _ b: NutritionPlan) -> Bool {
        a.name == b.name && dayString(a.startsOn) == dayString(b.startsOn)
            && a.endsOn.map(dayString) == b.endsOn.map(dayString) && a.priority == b.priority
            && (a.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == (b.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            && a.training == b.training && a.rest == b.rest && (a.deletedAt == nil) == (b.deletedAt == nil)
    }

    private static func targetsObject(_ targets: NutritionTargets) -> [String: Int] {
        ["kcal": targets.kcal, "protein_g": targets.proteinG, "carbs_g": targets.carbsG,
         "fat_g": targets.fatG, "water_ml": targets.waterML]
    }

    // MARK: App data (up)

    private func pushDocuments(_ database: AppDatabase, state: inout PlatformSyncState,
                               replacingServerBackup: Bool) async throws -> (entries: Int, other: Int) {
        if state.documentHashes.isEmpty {
            // First sync from this install: don't silently overwrite a backup made elsewhere.
            let remote = try await client.selectRows("app_documents", select: "collection,id",
                                                     filters: ["deleted_at": "is.null"], order: "collection,id",
                                                     limit: replacingServerBackup ? nil : 1)
            if !remote.isEmpty && !replacingServerBackup { throw PlatformSyncError.serverHasBackup }
            // Replacing: everything on the platform that isn't on this iPhone gets deleted there.
            for row in remote {
                guard let collection = row["collection"] as? String, let id = row["id"] as? String else { continue }
                state.documentHashes[collection, default: [:]][id] = ""
            }
        }

        var counts = (entries: 0, other: 0)
        for collection in AppCollection.all(of: database) {
            let previous = state.documentHashes[collection.name] ?? [:]
            var current: [String: String] = [:]
            var changed: [(id: String, value: any Encodable)] = []
            for document in collection.documents {
                let hash = try Self.hash(document.value)
                current[document.id] = hash
                if previous[document.id] != hash { changed.append(document) }
            }
            let deleted = previous.keys.filter { current[$0] == nil }

            // Typed rows first, so the dashboard has them even if the backup part fails.
            switch collection.name {
            case AppCollection.entries:
                let rows = changed.compactMap { $0.value as? FoodEntry }.map(Self.foodEntryRow)
                for batch in rows.chunked(into: Self.batchSize) {
                    try await client.upsert("food_entries", rows: batch, onConflict: "id")
                }
                try await softDelete("food_entries", ids: deleted)
            case AppCollection.foodItems:
                let rows = changed.compactMap { $0.value as? FoodItem }.map(Self.foodItemRow)
                for batch in rows.chunked(into: Self.batchSize) {
                    try await client.upsert("food_items", rows: batch, onConflict: "id")
                }
                try await softDelete("food_items", ids: deleted)
            default:
                break
            }

            let documentRows: [[String: Any]] = try changed.map { document in
                ["collection": collection.name, "id": document.id, "data": try Self.jsonObject(document.value), "deleted_at": NSNull()]
            }
            for batch in documentRows.chunked(into: Self.batchSize) {
                try await client.upsert("app_documents", rows: batch, onConflict: "collection,id")
            }
            for batch in deleted.chunked(into: Self.idsPerFilter) {
                try await client.update("app_documents",
                                        filters: ["collection": "eq.\(collection.name)", "id": "in.(\(Self.quoted(batch)))"],
                                        values: ["deleted_at": SupabaseClient.timestamp(.now)])
            }

            state.documentHashes[collection.name] = current
            state.save()
            if collection.name == AppCollection.entries {
                counts.entries += changed.count + deleted.count
            } else {
                counts.other += changed.count + deleted.count
            }
        }
        return counts
    }

    private func softDelete(_ table: String, ids: [String]) async throws {
        for batch in ids.chunked(into: Self.idsPerFilter) {
            try await client.update(table, filters: ["id": "in.(\(Self.quoted(batch)))", "deleted_at": "is.null"],
                                    values: ["deleted_at": SupabaseClient.timestamp(.now)])
        }
    }

    /// A diary entry as the dashboard's `food_entries` row. The app doesn't record quantities
    /// or fibre; missing macros are sent as 0.
    private static func foodEntryRow(_ entry: FoodEntry) -> [String: Any] {
        [
            "id": entry.id.uuidString,
            "eaten_at": SupabaseClient.timestamp(entry.date),
            "meal": entry.mealType.rawValue,
            "name": entry.name,
            "kcal": clamp(Double(entry.calories), max: 99_999),
            "protein_g": clamp(entry.protein ?? 0, max: 9_999),
            "carbs_g": clamp(entry.carbs ?? 0, max: 9_999),
            "fat_g": clamp(entry.fat ?? 0, max: 9_999),
            "barcode": entry.barcode ?? NSNull(),
            "group_id": entry.groupID?.uuidString ?? NSNull(),
            "group_name": entry.groupName ?? NSNull(),
            "source": "ios_app",
            "deleted_at": NSNull()
        ]
    }

    /// A catalog food as the dashboard's `food_items` row: nutrition per 100 g/ml (or per unit),
    /// whatever basis and dose the app stores it with.
    private static func foodItemRow(_ item: FoodItem) -> [String: Any] {
        let isCounted = item.unit.baseUnit == .unit
        let dose = item.baseDoseAmount > 0 ? item.baseDoseAmount : 1
        let factor: Double = switch item.nutritionBasis {
        case .per100: isCounted ? 0.01 : 1
        case .perDose: isCounted ? 1 / dose : 100 / dose
        }
        return [
            "id": item.id.uuidString,
            "name": item.name,
            "brand": item.brand ?? NSNull(),
            "unit": isCounted ? "unit" : (item.unit.baseUnit == .milliliter ? "ml" : "g"),
            "kcal_per_100": clamp(Double(item.calories) * factor, max: 99_999),
            "protein_g_per_100": clamp((item.protein ?? 0) * factor, max: 9_999),
            "carbs_g_per_100": clamp((item.carbs ?? 0) * factor, max: 9_999),
            "fat_g_per_100": clamp((item.fat ?? 0) * factor, max: 9_999),
            "source": "ios_app",
            "deleted_at": NSNull()
        ]
    }

    // MARK: Apple Health (up)

    private func pushHealth(_ healthKit: HealthKitManager,
                            state: inout PlatformSyncState) async throws -> (samples: Int, workouts: Int) {
        guard healthKit.isSupported else { return (0, 0) }
        let calendar = Calendar.current
        let now = Date()
        let earliest = state.healthSyncedUntil.map { $0.addingTimeInterval(-Double(Self.healthOverlapDays) * 86_400) }
            ?? calendar.date(byAdding: .day, value: -Self.healthBackfillDays, to: now) ?? now
        // Windows start at 18:00 — where the platform splits nights (sleep_day) — so no night's
        // sleep is ever divided between two windows.
        var windowStart = calendar.startOfDay(for: earliest).addingTimeInterval(-6 * 3600)
        var counts = (samples: 0, workouts: 0)

        while windowStart < now {
            let windowEnd = min(calendar.date(byAdding: .day, value: Self.healthWindowDays, to: windowStart) ?? now, now)
            guard let payload = try await healthKit.syncPayload(from: windowStart, to: windowEnd) else { break }
            let bounds: [String: Any] = ["p_from": SupabaseClient.timestamp(windowStart), "p_to": SupabaseClient.timestamp(windowEnd)]
            try await client.rpc("sync_health_samples", object: bounds.merging([
                "p_types": HealthKitManager.syncedSampleTypes,
                "p_samples": payload.samples.map(\.row)
            ]) { $1 })
            try await client.rpc("sync_workouts", object: bounds.merging([
                "p_workouts": payload.workouts.map(\.row)
            ]) { $1 })
            counts.samples += payload.samples.count
            counts.workouts += payload.workouts.count
            state.healthSyncedUntil = windowEnd
            state.save()
            windowStart = windowEnd
        }
        return counts
    }

    // MARK: Usage events (up)

    private func flushEvents() async throws {
        for batch in AppAnalytics.loadPending().chunked(into: Self.batchSize) {
            try await client.upsert("app_events", rows: batch.map(\.row), onConflict: "id", ignoreDuplicates: true)
            AppAnalytics.removeSent(Set(batch.map(\.id)))
        }
    }

    // MARK: Helpers

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static func clamp(_ value: Double, max upper: Double) -> Double {
        (min(max(value, 0), upper) * 100).rounded() / 100
    }

    private static func quoted(_ ids: [String]) -> String {
        ids.map { "\"\($0)\"" }.joined(separator: ",")
    }

    /// `yyyy-MM-dd` of a local day; plans that "always applied" (`.distantPast`) become 2000-01-01.
    static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: max(date, dayFormatter.date(from: "2000-01-01") ?? date))
    }

    fileprivate static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let hashEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// Fingerprint of a record's contents, to tell whether it changed since the last sync.
    private static func hash(_ value: any Encodable) throws -> String {
        SHA256.hash(data: try hashEncoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }

    /// A record exactly as the app encodes it (dates ISO 8601), as a JSON object for `jsonb`.
    private static func jsonObject(_ value: any Encodable) throws -> Any {
        try JSONSerialization.jsonObject(with: SupabaseClient.jsonEncoder.encode(value))
    }
}

/// A `nutrition_plans` row with its targets, as read from the platform.
private struct RemotePlan: Decodable {
    struct Targets: Decodable {
        let day_type: String
        let kcal: Int
        let protein_g: Int
        let carbs_g: Int
        let fat_g: Int
        let water_ml: Int

        var targets: NutritionTargets {
            NutritionTargets(kcal: kcal, proteinG: protein_g, carbsG: carbs_g, fatG: fat_g, waterML: water_ml)
        }
    }

    let id: UUID
    let name: String
    let starts_on: String
    let ends_on: String?
    let priority: Int
    let notes: String?
    let created_at: String
    let updated_at: String
    let deleted_at: String?
    let nutrition_targets: [Targets]

    /// As the app models it (`nil` if incomplete — the database always saves both targets).
    var plan: NutritionPlan? {
        guard let startsOn = PlatformSyncManager.dayFormatter.date(from: starts_on),
              let training = nutrition_targets.first(where: { $0.day_type == "training" }),
              let rest = nutrition_targets.first(where: { $0.day_type == "rest" }) else { return nil }
        return NutritionPlan(
            id: id,
            name: name,
            startsOn: startsOn,
            endsOn: ends_on.flatMap(PlatformSyncManager.dayFormatter.date(from:)),
            priority: priority,
            notes: notes,
            training: training.targets,
            rest: rest.targets,
            createdAt: SupabaseClient.date(fromTimestamp: created_at) ?? .now,
            updatedAt: SupabaseClient.date(fromTimestamp: updated_at) ?? .now,
            deletedAt: deleted_at.flatMap(SupabaseClient.date(fromTimestamp:))
        )
    }
}

/// One group of app records backed up to `app_documents` (collection = the `AppDatabase` field).
/// Nutrition plans aren't here: they have their own tables, shared with the dashboard.
private struct AppCollection {
    static let entries = "entries"
    static let foodItems = "foodItems"
    static let recipes = "recipes"
    static let stores = "stores"
    static let supplementCategories = "supplementCategories"
    static let supplements = "supplements"
    static let supplementLogs = "supplementLogs"
    static let stockLocations = "stockLocations"
    static let mealPlan = "mealPlan"
    static let settings = "settings"
    static let bodyMeasurements = "bodyMeasurements"
    static let progressPhotos = "progressPhotos"

    let name: String
    let documents: [(id: String, value: any Encodable)]

    init<T: Encodable & Identifiable>(_ name: String, _ items: [T]) where T.ID == UUID {
        self.name = name
        self.documents = items.map { ($0.id.uuidString, $0) }
    }

    init(name: String, documents: [(id: String, value: any Encodable)]) {
        self.name = name
        self.documents = documents
    }

    static func all(of database: AppDatabase) -> [AppCollection] {
        [
            AppCollection(entries, database.entries),
            AppCollection(foodItems, database.foodItems),
            AppCollection(recipes, database.recipes),
            AppCollection(stores, database.stores),
            AppCollection(supplementCategories, database.supplementCategories),
            AppCollection(supplements, database.supplements),
            AppCollection(supplementLogs, database.supplementLogs),
            AppCollection(stockLocations, database.stockLocations),
            AppCollection(bodyMeasurements, database.bodyMeasurements),
            // Only the metadata (date, pose, photo id): the images themselves aren't uploaded yet —
            // see `.claude/notes/photos-api-dashboard.md` (Supabase Storage bucket).
            AppCollection(progressPhotos, database.progressPhotos),
            // One document per plan, by id. (A single plan used to be stored under id "current";
            // the first sync after the update soft-deletes that one.)
            AppCollection(mealPlan, database.mealPlans),
            AppCollection(name: settings, documents: [("current", database.settings)])
        ]
    }
}

/// What this install last synced: a hash per record, per plan, and how far Apple Health got.
private struct PlatformSyncState: Codable {
    var documentHashes: [String: [String: String]] = [:]
    var planHashes: [String: String] = [:]
    var healthSyncedUntil: Date?
    var lastSync: Date?

    /// One file per server: a Debug build (local Supabase) and a Release build (the VPS) on the
    /// same iPhone must not share what they think was already sent.
    private static var url: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let server = SupabaseConfig.current.map { "\($0.url.host() ?? "")\($0.url.port.map { ":\($0)" } ?? "")" } ?? "none"
        let suffix = SHA256.hash(data: Data(server.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
        return support.appendingPathComponent("CalorieBuddy/platform_sync_state-\(suffix).json")
    }

    static func load() -> PlatformSyncState {
        guard let data = try? Data(contentsOf: url),
              let state = try? SupabaseClient.jsonDecoder.decode(PlatformSyncState.self, from: data) else { return PlatformSyncState() }
        return state
    }

    func save() {
        guard let data = try? SupabaseClient.jsonEncoder.encode(self) else { return }
        try? data.write(to: Self.url, options: .atomic)
    }
}

extension Array {
    /// Consecutive slices of at most `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
