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
    /// A document from the platform the app can't decode (skipped, reported as a warning).
    case unreadableDocument

    var errorDescription: String? {
        switch self {
        case .serverHasBackup:
            return "Já existe um backup desta app na plataforma. Restaura-o primeiro, ou escolhe substituí-lo pelos dados deste iPhone."
        case .noServerBackup:
            return "Ainda não existe nenhum backup desta app na plataforma."
        case .unreadableDocument:
            return "Um registo da plataforma não está num formato que a app consiga ler."
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
/// 2. **App data, down** — the `app_documents` changed since the last pull (the athlete edits the
///    diary and the catalog on the dashboard too) are merged in: the platform's version wins
///    unless the app changed the same record since the last sync — then the app's wins.
/// 2b. **App data, up** — every record of the app database (except the plans) goes to
///    `app_documents` as the app encodes it, a lossless backup to restore from; the diary and the
///    catalog also go to the typed `food_entries` / `food_items` the dashboard reads. Only records
///    whose hash changed since the last sync are sent; records deleted locally are soft-deleted.
/// 3. **Apple Health, up** — from the last synced moment (minus a few days, for data the Watch
///    delivers late), window by window through `sync_health_samples()` / `sync_workouts()`.
/// 4. Usage events, then one `app_syncs` row, which the dashboard shows as "last synced".
@Observable
final class PlatformSyncManager {
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
        try await performSync(store: store, healthKit: healthKit, automatic: automatic,
                              replacingServerBackup: replacingServerBackup)
    }

    private func performSync(store: DataStore, healthKit: HealthKitManager, automatic: Bool,
                             replacingServerBackup: Bool) async throws {
        do {
            guard client.isSignedIn else { throw SupabaseError.notSignedIn }
            var state = PlatformSyncState.load()
            var newWarnings: [String] = []

            let plans = try await syncNutritionPlans(store: store, state: &state, warnings: &newWarnings)
            state.save()
            // What was changed on the dashboard comes in first, so the push below doesn't undo it.
            let pulled = try await pullDocuments(store: store, state: &state, warnings: &newWarnings)
            state.save()
            let database = store.databaseSnapshot()
            let documents = try await pushDocuments(database, state: &state,
                                                    replacingServerBackup: replacingServerBackup)
            state.save()
            let photos = try await pushPhotos(database, state: &state)
            let health = try await pushHealth(healthKit, state: &state)
            try await flushEvents()

            let summary = [
                "\(pulled) alterações do dashboard",
                "\(documents.entries) registos do diário", "\(documents.other) outros registos",
                "\(photos.uploaded) fotos enviadas e \(photos.deleted) apagadas",
                "\(health.samples) amostras e \(health.workouts) treinos da app Saúde",
                "\(plans.pulled) planos recebidos", "\(plans.pushed) planos enviados"
            ]
            try await client.upsert("app_syncs", rows: [[
                "id": UUID().uuidString,
                "app_version": Self.appVersion,
                "stats": ["entries": documents.entries, "documents": documents.other, "documents_pulled": pulled,
                          "photos_uploaded": photos.uploaded, "photos_deleted": photos.deleted,
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

    /// Automatic sync — silently skipped when signed out, busy, or synced less than
    /// `minimumInterval` ago. Errors stay visible in the sync screen.
    func autoSyncIfEnabled(store: DataStore, healthKit: HealthKitManager, minimumInterval: TimeInterval = 0) async {
        // Always on while signed in: the dashboard depends on the platform having everything.
        guard isAvailable, client.isSignedIn, !isBusy else { return }
        if let lastSync, Date().timeIntervalSince(lastSync) < minimumInterval { return }
        #if canImport(UIKit)
        // Ask iOS for a little extra time so the sync can finish after the app is backgrounded.
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "PlatformSync")
        defer { UIApplication.shared.endBackgroundTask(taskID) }
        #endif
        try? await sync(store: store, healthKit: healthKit, automatic: true)
    }

    /// How long after the last local change the sync starts, so a burst of edits (a recipe logged
    /// as several entries, a few foods added in a row) goes up together.
    private static let localChangeDelay: Duration = .seconds(3)
    /// Whether a sync for local changes is already waiting.
    private var localSyncPending = false
    private var lastLocalChange = ContinuousClock.now

    /// After every change the user makes (`DataStore.localChangeCount`): products, intakes,
    /// photos… reach the platform — and the dashboard — within seconds. If a sync is running it
    /// may have missed the change, so this waits for it and syncs again; changes while waiting
    /// share that one sync.
    func syncAfterLocalChange(store: DataStore, healthKit: HealthKitManager) async {
        lastLocalChange = .now
        guard isAvailable, client.isSignedIn, !localSyncPending else { return }
        localSyncPending = true
        while isBusy || ContinuousClock.now - lastLocalChange < Self.localChangeDelay {
            try? await Task.sleep(for: .seconds(1))
        }
        // Cleared before syncing: a change made during this sync asks for another one.
        localSyncPending = false
        await autoSyncIfEnabled(store: store, healthKit: healthKit)
    }

    // MARK: Session (sign in / sign out)

    /// While signing in and downloading the account: the login screen stays up until it's done.
    private(set) var isLoadingAccount = false

    /// The login screen: signs in (athlete accounts only), then `completeSignIn`. On failure the
    /// session is dropped again (nothing local is erased) and the error is thrown.
    func signIn(email: String, password: String, store: DataStore, healthKit: HealthKitManager) async throws {
        isLoadingAccount = true
        defer { isLoadingAccount = false }
        do {
            try await client.signIn(email: email, password: password)
            try await completeSignIn(store: store, healthKit: healthKit)
        } catch {
            await client.signOut()
            throw error
        }
    }

    /// After signing in on the login screen: brings this iPhone in line with the platform, which
    /// always holds the data (the dashboard depends on it).
    ///
    /// - An install that already synced with this server (e.g. the session had expired) just syncs.
    /// - Otherwise, when the platform has data: whatever this iPhone holds that never reached it is
    ///   sent first without deleting anything there, then everything is downloaded (diary, catalog,
    ///   recipes, supplements, plans, measurements, photos, settings) — replacing what's local.
    /// - When the platform is empty, this iPhone's data becomes its first backup.
    func completeSignIn(store: DataStore, healthKit: HealthKitManager) async throws {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        if PlatformSyncState.load().documentHashes.isEmpty {
            let remote = try await client.selectRows("app_documents", select: "collection,id",
                                                     filters: ["deleted_at": "is.null"], order: "collection,id", limit: 1)
            if !remote.isEmpty {
                if store.hasUserData { try await mergeLocalIntoPlatform(store: store) }
                try await performRestore(into: store)
            }
        }
        try await performSync(store: store, healthKit: healthKit, automatic: false, replacingServerBackup: false)
    }

    /// Ends the session and erases this iPhone's data, so the next sign-in starts from the
    /// platform. Syncs first so nothing is lost; if that fails, it throws and nothing is erased —
    /// unless `discardingUnsynced` (the user chose to sign out anyway).
    func signOutErasingData(store: DataStore, healthKit: HealthKitManager, discardingUnsynced: Bool) async throws {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        if !discardingUnsynced, client.isSignedIn {
            try await performSync(store: store, healthKit: healthKit, automatic: false, replacingServerBackup: false)
        }
        await client.signOut()
        store.deleteEverything()
        PlatformSyncState.erase()
        lastSync = nil
        lastSummary = nil
        lastError = nil
        warnings = []
    }

    /// Sends every local record to the platform without deleting anything there — for data that
    /// was on this iPhone before it ever synced with this server (union: nothing is lost).
    private func mergeLocalIntoPlatform(store: DataStore) async throws {
        var state = PlatformSyncState.load()
        var ignored: [String] = []
        _ = try await syncNutritionPlans(store: store, state: &state, warnings: &ignored)
        let database = store.databaseSnapshot()
        // Settings stay as the platform has them (there is only one set).
        for collection in AppCollection.all(of: database) where collection.name != AppCollection.settings {
            switch collection.name {
            case AppCollection.entries:
                let foods = Dictionary(database.foodItems.map { ($0.id, $0) }) { first, _ in first }
                let rows = collection.documents.compactMap { $0.value as? FoodEntry }.map { Self.foodEntryRow($0, foods: foods) }
                for batch in rows.chunked(into: Self.batchSize) { try await client.upsert("food_entries", rows: batch, onConflict: "id") }
            case AppCollection.foodItems:
                let rows = collection.documents.compactMap { $0.value as? FoodItem }.map(Self.foodItemRow)
                for batch in rows.chunked(into: Self.batchSize) { try await client.upsert("food_items", rows: batch, onConflict: "id") }
            case AppCollection.progressPhotos:
                let rows = collection.documents.compactMap { $0.value as? ProgressPhoto }.map(Self.progressPhotoRow)
                for batch in rows.chunked(into: Self.batchSize) { try await client.upsert("progress_photos", rows: batch, onConflict: "id") }
            case AppCollection.supplements:
                let rows = collection.documents.compactMap { $0.value as? Supplement }.map { Self.supplementRow($0, in: database) }
                for batch in rows.chunked(into: Self.batchSize) { try await client.upsert("supplements", rows: batch, onConflict: "id") }
            default:
                break
            }
            let documentRows: [[String: Any]] = try collection.documents.map { document in
                ["collection": collection.name, "id": document.id, "data": try Self.jsonObject(document.value), "deleted_at": NSNull()]
            }
            for batch in documentRows.chunked(into: Self.batchSize) {
                try await client.upsert("app_documents", rows: batch, onConflict: "collection,id")
            }
        }
        _ = try await pushPhotos(database, state: &state)
        state.save()
    }

    // MARK: Restore

    /// Replaces the local database with the backup on the platform (the current one is kept as the
    /// local backup, exactly like importing a file). Apple Health isn't touched.
    func restore(into store: DataStore) async throws {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        try await performRestore(into: store)
    }

    private func performRestore(into store: DataStore) async throws {
        do {
            guard client.isSignedIn else { throw SupabaseError.notSignedIn }
            let rows = try await client.selectRows("app_documents", select: "collection,id,data",
                                                   filters: ["deleted_at": "is.null"], order: "collection,id")
            guard !rows.isEmpty else { throw PlatformSyncError.noServerBackup }
            let plans = try await fetchRemotePlans().compactMap(\.plan)

            // A record the app can't read is left out (and counted) rather than failing the whole
            // restore — signing in depends on it.
            var unreadable = 0
            func decode<T: Decodable>(_ collection: String, as type: T.Type) throws -> [T] {
                rows.filter { $0["collection"] as? String == collection }.compactMap { row in
                    do {
                        let data = try JSONSerialization.data(withJSONObject: row["data"] ?? [:])
                        return try SupabaseClient.jsonDecoder.decode(T.self, from: data)
                    } catch {
                        unreadable += 1
                        return nil
                    }
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
                progressPhotos: try decode(AppCollection.progressPhotos, as: ProgressPhoto.self),
                foodCategories: try decode(AppCollection.foodCategories, as: FoodCategory.self)
            )

            // The images, before switching databases, so the restored records show their photos
            // right away. One that fails is retried by `pushPhotos` on the next syncs.
            var downloaded = Set<String>()
            var missing = 0
            for (path, id) in Self.photoPaths(in: database) {
                if PhotoStore.exists(id) { continue }
                do {
                    try PhotoStore.write(try await client.downloadObject(Self.photoBucket, path: path), id: id)
                    downloaded.insert(path)
                } catch {
                    missing += 1
                }
            }
            warnings = (missing > 0 ? ["\(missing) fotos não puderam ser descarregadas — a app volta a tentar em cada sincronização."] : [])
                + (unreadable > 0 ? ["\(unreadable) registos da plataforma não puderam ser lidos e ficaram de fora."] : [])

            store.replaceDatabase(with: database)

            // What's local now is exactly what's on the platform.
            var state = PlatformSyncState.load()
            state.uploadedPhotoPaths = Array(downloaded)
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

    // MARK: App data (down): changes made on the dashboard

    /// Takes in the `app_documents` the dashboard changed since the last pull. A record the app
    /// also changed since the last sync keeps the app's version (the push then overwrites the
    /// platform's); otherwise the platform's version — or its deletion — wins. Documents the app
    /// can't read are skipped with a warning, never blocking the rest.
    private func pullDocuments(store: DataStore, state: inout PlatformSyncState,
                               warnings: inout [String]) async throws -> Int {
        // First sync from this install: nothing has been synced yet to compare against (the push
        // decides what to do with an existing backup).
        guard !state.documentHashes.isEmpty else { return 0 }
        var filters: [String: String] = [:]
        if let since = state.documentsPulledUntil { filters["updated_at"] = "gt.\(since)" }
        let rows = try await client.selectRows("app_documents", select: "collection,id,data,updated_at,deleted_at",
                                               filters: filters, order: "updated_at")
        guard !rows.isEmpty else { return 0 }

        var database = store.databaseSnapshot()
        var localHashes: [String: [String: String]] = [:]
        for collection in AppCollection.all(of: database) {
            localHashes[collection.name] = try Dictionary(
                uniqueKeysWithValues: collection.documents.map { ($0.id, try Self.hash($0.value)) }
            )
        }

        var applied = 0
        var unreadable = 0
        for row in rows {
            if let updatedAt = row["updated_at"] as? String { state.documentsPulledUntil = updatedAt }
            guard let collection = row["collection"] as? String, let id = row["id"] as? String else { continue }
            let isDeleted = !(row["deleted_at"] is NSNull || row["deleted_at"] == nil)
            let synced = state.documentHashes[collection]?[id]
            let local = localHashes[collection]?[id]
            do {
                // The platform's version, as the app would hash it (nil = deleted there).
                let incoming: Any? = isDeleted ? nil : row["data"]
                let serverHash = try incoming.map { try Self.hash(ofDocument: $0, in: collection) }
                // Nothing new (typically the app's own last push), or the app changed it too:
                // the app wins.
                guard serverHash != synced, local == synced else { continue }
                // The record is gone everywhere already: nothing to apply.
                if serverHash == nil && local == nil { continue }
                try Self.apply(incoming, id: id, collection: collection, to: &database)
                state.documentHashes[collection, default: [:]][id] = serverHash
                applied += 1
            } catch {
                unreadable += 1
            }
        }
        if applied > 0 { store.applyRemoteChanges(database) }
        if unreadable > 0 {
            warnings.append("\(unreadable) registos vindos do dashboard não puderam ser lidos e foram ignorados.")
        }
        return applied
    }

    /// The hash the app would give `data` (a document of `collection`) — decoded into the app's
    /// model and re-encoded, so formatting differences don't count as changes.
    private static func hash(ofDocument data: Any, in collection: String) throws -> String {
        var scratch = AppDatabase(version: AppDatabase.currentVersion, exportedAt: .now, settings: .default,
                                  entries: [], foodItems: [], recipes: [], stores: [], supplementCategories: [],
                                  supplements: [], supplementLogs: [], stockLocations: [], mealPlans: [],
                                  nutritionPlans: [], bodyMeasurements: [], progressPhotos: [])
        let id = (data as? [String: Any])?["id"] as? String ?? "current"
        try apply(data, id: id, collection: collection, to: &scratch)
        guard let document = AppCollection.all(of: scratch).first(where: { $0.name == collection })?.documents.first else {
            throw PlatformSyncError.unreadableDocument
        }
        return try hash(document.value)
    }

    /// Inserts/replaces (`data`) or removes (`nil`) one document of `collection` in `database`.
    private static func apply(_ data: Any?, id: String, collection: String, to database: inout AppDatabase) throws {
        func merge<T: Decodable & Identifiable>(_ items: inout [T], _ type: T.Type) throws where T.ID == UUID {
            guard let uuid = UUID(uuidString: id) else { throw PlatformSyncError.unreadableDocument }
            guard let data else {
                items.removeAll { $0.id == uuid }
                return
            }
            let value = try SupabaseClient.jsonDecoder.decode(T.self, from: JSONSerialization.data(withJSONObject: data))
            guard value.id == uuid else { throw PlatformSyncError.unreadableDocument }
            if let index = items.firstIndex(where: { $0.id == uuid }) {
                items[index] = value
            } else {
                items.append(value)
            }
        }
        switch collection {
        case AppCollection.entries: try merge(&database.entries, FoodEntry.self)
        case AppCollection.foodItems: try merge(&database.foodItems, FoodItem.self)
        case AppCollection.foodCategories: try merge(&database.foodCategories, FoodCategory.self)
        case AppCollection.recipes: try merge(&database.recipes, Recipe.self)
        case AppCollection.stores: try merge(&database.stores, Store.self)
        case AppCollection.supplementCategories: try merge(&database.supplementCategories, SupplementCategory.self)
        case AppCollection.supplements: try merge(&database.supplements, Supplement.self)
        case AppCollection.supplementLogs: try merge(&database.supplementLogs, SupplementLogEntry.self)
        case AppCollection.stockLocations: try merge(&database.stockLocations, StockLocation.self)
        case AppCollection.bodyMeasurements: try merge(&database.bodyMeasurements, BodyMeasurement.self)
        case AppCollection.progressPhotos: try merge(&database.progressPhotos, ProgressPhoto.self)
        case AppCollection.mealPlan: try merge(&database.mealPlans, MealPlan.self)
        case AppCollection.settings:
            // One document; it can't be deleted, only replaced.
            guard let data else { return }
            database.settings = try SupabaseClient.jsonDecoder.decode(UserSettings.self,
                                                                    from: JSONSerialization.data(withJSONObject: data))
        default:
            throw PlatformSyncError.unreadableDocument
        }
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

        // When the typed rows gain columns (e.g. food_items.photo_path), every record is re-sent
        // once — their contents didn't change, so the hashes alone would skip them.
        let resendTypedRows = (state.typedRowsVersion ?? 0) < PlatformSyncState.currentTypedRowsVersion

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
            let typed = resendTypedRows && collection.name != AppCollection.entries ? collection.documents : changed

            // Typed rows first, so the dashboard has them even if the backup part fails.
            switch collection.name {
            case AppCollection.entries:
                let foods = Dictionary(database.foodItems.map { ($0.id, $0) }) { first, _ in first }
                let rows = typed.compactMap { $0.value as? FoodEntry }.map { Self.foodEntryRow($0, foods: foods) }
                for batch in rows.chunked(into: Self.batchSize) {
                    try await client.upsert("food_entries", rows: batch, onConflict: "id")
                }
                try await softDelete("food_entries", ids: deleted)
            case AppCollection.foodItems:
                let rows = typed.compactMap { $0.value as? FoodItem }.map(Self.foodItemRow)
                for batch in rows.chunked(into: Self.batchSize) {
                    try await client.upsert("food_items", rows: batch, onConflict: "id")
                }
                try await softDelete("food_items", ids: deleted)
            case AppCollection.progressPhotos:
                let rows = typed.compactMap { $0.value as? ProgressPhoto }.map(Self.progressPhotoRow)
                for batch in rows.chunked(into: Self.batchSize) {
                    try await client.upsert("progress_photos", rows: batch, onConflict: "id")
                }
                try await softDelete("progress_photos", ids: deleted)
            case AppCollection.supplements:
                let rows = typed.compactMap { $0.value as? Supplement }.map { Self.supplementRow($0, in: database) }
                for batch in rows.chunked(into: Self.batchSize) {
                    try await client.upsert("supplements", rows: batch, onConflict: "id")
                }
                try await softDelete("supplements", ids: deleted)
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
        state.typedRowsVersion = PlatformSyncState.currentTypedRowsVersion
        return counts
    }

    // MARK: Photos (up)

    static let photoBucket = "athlete-photos"

    /// Every photo the database points at, by its path in the bucket (`<kind>/<photo id>.jpg`).
    /// The folder decides who may see it on the dashboard (see the `athlete_photos` migration).
    private static func photoPaths(in database: AppDatabase) -> [String: UUID] {
        var paths: [String: UUID] = [:]
        func add(_ kind: String, _ ids: [UUID?]) {
            for id in ids.compactMap({ $0 }) { paths[photoPath(kind, id)] = id }
        }
        add("food", database.foodItems.map(\.photoID))
        add("recipe", database.recipes.map(\.photoID))
        add("supplement", database.supplements.map(\.photoID))
        add("progress", database.progressPhotos.map(\.photoID))
        // Nutrition-label photos go in the same folder as their record's photo, so the dashboard
        // shows them to exactly the same people.
        add("food", database.foodItems.flatMap(\.labelPhotoIDs))
        add("recipe", database.recipes.flatMap(\.labelPhotoIDs))
        add("supplement", database.supplements.flatMap(\.labelPhotoIDs))
        return paths
    }

    private static func photoPath(_ kind: String, _ id: UUID) -> String {
        "\(kind)/\(id.uuidString).jpg"
    }

    /// Uploads the photos not sent yet, downloads the ones missing on this iPhone and deletes the
    /// ones no record uses any more. A photo id never changes its image (a new photo gets a new
    /// id), so "sent once" is enough.
    private func pushPhotos(_ database: AppDatabase,
                            state: inout PlatformSyncState) async throws -> (uploaded: Int, deleted: Int) {
        let wanted = Self.photoPaths(in: database)
        var sent = Set(state.uploadedPhotoPaths ?? [])
        var counts = (uploaded: 0, deleted: 0)

        for (path, id) in wanted.sorted(by: { $0.key < $1.key }) where !sent.contains(path) {
            guard let data = PhotoStore.data(id) else {
                // Not on this iPhone (e.g. its download failed at sign-in): fetch it if the platform
                // has it, so a failed download is retried on every sync instead of staying missing.
                if let remote = try? await client.downloadObject(Self.photoBucket, path: path),
                   (try? PhotoStore.write(remote, id: id)) != nil {
                    sent.insert(path)
                    state.uploadedPhotoPaths = Array(sent)
                    state.save()
                }
                continue
            }
            try await client.uploadObject(Self.photoBucket, path: path, data: data, contentType: "image/jpeg")
            sent.insert(path)
            counts.uploaded += 1
            state.uploadedPhotoPaths = Array(sent)
            state.save()
        }

        let stale = sent.subtracting(wanted.keys).sorted()
        for batch in stale.chunked(into: Self.idsPerFilter) {
            try await client.deleteObjects(Self.photoBucket, paths: batch)
            sent.subtract(batch)
            counts.deleted += batch.count
            state.uploadedPhotoPaths = Array(sent)
            state.save()
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
    /// `foods`: the catalog, to point the row at the food it was logged from (food_item_id) with
    /// the amount eaten in g / ml / units.
    private static func foodEntryRow(_ entry: FoodEntry, foods: [UUID: FoodItem]) -> [String: Any] {
        let food = entry.foodItemID.flatMap { foods[$0] }
        let amount = food.flatMap { food in entry.quantity.map { $0 * food.baseDoseAmount } }
        let amountUnit: String? = food.map { food in
            switch food.unit.baseUnit {
            case .milliliter: return "ml"
            case .unit: return "unit"
            default: return "g"
            }
        }
        return [
            "id": entry.id.uuidString,
            "eaten_at": SupabaseClient.timestamp(entry.date),
            "meal": entry.mealType.rawValue,
            "name": entry.name,
            "kcal": clamp(Double(entry.calories), max: 99_999),
            "protein_g": clamp(entry.protein ?? 0, max: 9_999),
            "carbs_g": clamp(entry.carbs ?? 0, max: 9_999),
            "fat_g": clamp(entry.fat ?? 0, max: 9_999),
            "fiber_g": clamp(entry.fiber ?? 0, max: 9_999),
            // The rest of the label: null when it wasn't stated (not the same as 0).
            "saturated_fat_g": entry.saturatedFat.map { clamp($0, max: 9_999) } ?? NSNull(),
            "sugars_g": entry.sugars.map { clamp($0, max: 9_999) } ?? NSNull(),
            "salt_g": entry.salt.map { clamp($0, max: 9_999) } ?? NSNull(),
            "micronutrients": (entry.micronutrients ?? [:]).filter { $0.value.isFinite && $0.value >= 0 },
            "food_item_id": food?.id.uuidString ?? NSNull(),
            "quantity": amount.flatMap { $0 > 0 ? clamp($0, max: 999_999) : nil } ?? NSNull(),
            "unit": amount.flatMap { $0 > 0 ? amountUnit : nil } ?? NSNull(),
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
            "fiber_g_per_100": clamp((item.fiber ?? 0) * factor, max: 9_999),
            "saturated_fat_g_per_100": item.saturatedFat.map { clamp($0 * factor, max: 9_999) } ?? NSNull(),
            "sugars_g_per_100": item.sugars.map { clamp($0 * factor, max: 9_999) } ?? NSNull(),
            "salt_g_per_100": item.salt.map { clamp($0 * factor, max: 9_999) } ?? NSNull(),
            "micronutrients_per_100": item.micronutrients
                .filter { $0.value.isFinite && $0.value >= 0 }
                .mapValues { $0 * factor },
            "photo_path": item.photoID.map { photoPath("food", $0) } ?? NSNull(),
            "source": "ios_app",
            "deleted_at": NSNull()
        ]
    }

    /// A supplement as the dashboard's `supplements` row — what someone with the supplements
    /// category sees: stock per location (by name) and in total, and what one dose holds.
    private static func supplementRow(_ supplement: Supplement, in database: AppDatabase) -> [String: Any] {
        let unit: String = switch supplement.unit.baseUnit {
        case .milliliter: "ml"
        case .unit: "unit"
        default: "g"
        }
        let toBase = supplement.unit.baseMultiplier
        let locationName = Dictionary(database.stockLocations.map { ($0.id, $0.name) }) { first, _ in first }
        let stocks = supplement.stocks.map { stock -> [String: Any] in
            ["location": locationName[stock.locationID] ?? "?", "remaining": max(stock.remaining * toBase, 0)]
        }
        let dose = supplement.nutrition(quantity: 1)
        func grams(_ value: Double?) -> Any { value.map { clamp($0, max: 9_999) } ?? NSNull() }
        return [
            "id": supplement.id.uuidString,
            "name": supplement.name,
            "category": database.supplementCategories.first { $0.id == supplement.categoryID }?.name ?? NSNull(),
            "unit": unit,
            "package_size": clamp(supplement.totalSize * toBase, max: 99_999_999),
            "dose_size": clamp(supplement.doseSize * toBase, max: 99_999_999),
            "stocks": stocks,
            "stock_total": clamp(supplement.totalRemaining * toBase, max: 99_999_999),
            "low_stock_threshold": supplement.lowStockThreshold.map { clamp($0 * toBase, max: 99_999_999) } ?? NSNull(),
            "kcal_per_dose": supplement.calories == nil ? NSNull() : clamp(dose.calories, max: 99_999) as Any,
            "protein_g_per_dose": grams(dose.protein),
            "carbs_g_per_dose": grams(dose.carbs),
            "sugars_g_per_dose": grams(dose.sugars),
            "fat_g_per_dose": grams(dose.fat),
            "salt_g_per_dose": grams(dose.salt),
            "micronutrients_per_dose": dose.micronutrients.stored.filter { $0.value.isFinite && $0.value >= 0 },
            "photo_path": supplement.photoID.map { photoPath("supplement", $0) } ?? NSNull(),
            "source": "ios_app",
            "deleted_at": NSNull()
        ]
    }

    /// A physical-progress photo as the dashboard's `progress_photos` row (the image itself goes to
    /// Storage in `pushPhotos`).
    private static func progressPhotoRow(_ photo: ProgressPhoto) -> [String: Any] {
        let notes = photo.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "id": photo.id.uuidString,
            "taken_on": dayString(photo.date),
            "pose": photo.pose.rawValue,
            "storage_path": photoPath("progress", photo.photoID),
            "notes": notes.flatMap { $0.isEmpty ? nil : String($0.prefix(1000)) } ?? NSNull(),
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
    static let foodCategories = "foodCategories"
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
            // Foods before the diary: an entry's typed row points at its food's (food_item_id).
            AppCollection(foodItems, database.foodItems),
            AppCollection(entries, database.entries),
            AppCollection(foodCategories, database.foodCategories),
            AppCollection(recipes, database.recipes),
            AppCollection(stores, database.stores),
            AppCollection(supplementCategories, database.supplementCategories),
            AppCollection(supplements, database.supplements),
            AppCollection(supplementLogs, database.supplementLogs),
            AppCollection(stockLocations, database.stockLocations),
            AppCollection(bodyMeasurements, database.bodyMeasurements),
            // The metadata (date, pose, photo id); the images go to Storage in `pushPhotos`.
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
    /// `updated_at` of the newest `app_documents` row taken in (the platform's own timestamp text,
    /// so no precision is lost). Optional like the fields below.
    var documentsPulledUntil: String?
    // Optional: state files written before these existed must still decode (a failed decode
    // would look like a first sync).
    /// Photo paths already in the bucket.
    var uploadedPhotoPaths: [String]?
    /// Version of the typed-row mapping last sent (see `currentTypedRowsVersion`).
    var typedRowsVersion: Int?

    /// Bump when `foodItemRow`/`foodEntryRow`/`progressPhotoRow` gain columns, to re-send every
    /// record once. 1: food_items.photo_path and progress_photos. 2: the full nutrition label
    /// (sugars, saturated fat, fibre, salt, micronutrients — migration nutrition_details).
    /// 3: supplements (migration supplements_catalog) and food_entries.food_item_id/quantity.
    static let currentTypedRowsVersion = 3

    /// One file per server: a Debug build (local Supabase) and a Release build (the VPS) on the
    /// same iPhone must not share what they think was already sent.
    private static var url: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let server = SupabaseConfig.current.map { "\($0.url.host() ?? "")\($0.url.port.map { ":\($0)" } ?? "")" } ?? "none"
        let suffix = SHA256.hash(data: Data(server.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
        return support.appendingPathComponent("CalorieBuddy/platform_sync_state-\(suffix).json")
    }

    /// Forgets everything synced with this server (after signing out and erasing the data).
    static func erase() {
        try? FileManager.default.removeItem(at: url)
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
