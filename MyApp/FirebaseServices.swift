import Foundation
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import FirebaseCore
import FirebaseAnalytics
import FirebaseAuth
import FirebaseFirestore
import CryptoKit
import OSLog

/// Starts Firebase — but only when `GoogleService-Info.plist` is in the app bundle, so the app
/// still builds and runs normally (with analytics and cloud backup simply unavailable) until
/// the Firebase project is set up.
enum FirebaseSetup {
    private(set) static var isConfigured = false

    static func configureIfAvailable() {
        guard !isConfigured,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
        isConfigured = true
        Analytics.setAnalyticsCollectionEnabled(AppAnalytics.isEnabled)
    }
}

// MARK: - Analytics

/// Usage events sent to Firebase Analytics, whose console turns them into charts.
///
/// Deliberately never includes nutrition values, body measurements or anything read from Apple
/// Health — only *what kind* of action happened (e.g. "a recipe was logged at lunch"). HealthKit
/// data must not be shared with third-party analytics.
enum AppEvent {
    enum EntrySource: String {
        case manual, barcode, catalog, recipe, mealPlan = "meal_plan", supplement
    }

    case entryLogged(source: EntrySource, mealType: MealType?)
    case mealPlanOptionLogged(meal: String, option: String, substitutions: Int, amountChanges: Int)
    case foodSubstituted(macro: Macro)
    case mealPlanImported
    case mealPlanExported
    case databaseImported
    case databaseExported
    case personalRecordsViewed
    case cloudBackup(automatic: Bool, succeeded: Bool)
    case cloudRestore(succeeded: Bool)

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
        case .cloudBackup: return "cloud_backup"
        case .cloudRestore: return "cloud_restore"
        }
    }

    var parameters: [String: Any]? {
        switch self {
        case .entryLogged(let source, let mealType):
            var parameters: [String: Any] = ["source": source.rawValue]
            if let mealType { parameters["meal_type"] = mealType.rawValue }
            return parameters
        case .mealPlanOptionLogged(let meal, let option, let substitutions, let amountChanges):
            return ["meal": meal, "option": option, "substitutions": substitutions, "amount_changes": amountChanges]
        case .foodSubstituted(let macro):
            return ["macro": macro.rawValue]
        case .cloudBackup(let automatic, let succeeded):
            return ["automatic": automatic ? 1 : 0, "succeeded": succeeded ? 1 : 0]
        case .cloudRestore(let succeeded):
            return ["succeeded": succeeded ? 1 : 0]
        case .mealPlanImported, .mealPlanExported, .databaseImported, .databaseExported, .personalRecordsViewed:
            return nil
        }
    }
}

enum AppAnalytics {
    private static let enabledKey = "CalorieBuddy.analyticsEnabled"

    /// Whether usage statistics are sent. On by default; can be turned off in Definições.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if FirebaseSetup.isConfigured {
                Analytics.setAnalyticsCollectionEnabled(newValue)
            }
        }
    }

    static func log(_ event: AppEvent) {
        guard FirebaseSetup.isConfigured, isEnabled else { return }
        Analytics.logEvent(event.name, parameters: event.parameters)
    }

    static func logScreen(_ name: String) {
        guard FirebaseSetup.isConfigured, isEnabled else { return }
        // An explicit screen class stops Firebase from filling in SwiftUI's (over-long) hosting
        // controller class name.
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: name,
            AnalyticsParameterScreenClass: "SwiftUI"
        ])
    }
}

extension View {
    /// Reports this screen to Firebase Analytics each time it appears (SwiftUI screens aren't
    /// tracked automatically).
    func trackScreen(_ name: String) -> some View {
        onAppear { AppAnalytics.logScreen(name) }
    }
}

// MARK: - Cloud backup

enum CloudBackupError: LocalizedError {
    case notConfigured
    case noBackupFound
    /// Something missing in the Firebase console, with the steps to fix it.
    case consoleSetup(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "A Firebase ainda não está configurada nesta app (falta o GoogleService-Info.plist)."
        case .noBackupFound:
            return "Ainda não existe nenhum backup na nuvem."
        case .consoleSetup(let steps):
            return steps
        }
    }
}

/// Backs the whole database up to Cloud Firestore as plain, readable documents, so it can be
/// browsed in the Firebase console and restored on another iPhone or after reinstalling.
///
/// The app has a single user, so there's no login: Firebase anonymous auth runs silently (the
/// security rules only require *a* signed-in app instance) and the data always lives under the
/// same fixed `users/owner` path, whichever install wrote it.
///
/// Layout, one document per item (document ID = the item's UUID):
/// ```
/// users/owner                         settings, schemaVersion, updatedAt
/// users/owner/entries/{id}            FoodEntry
/// users/owner/foodItems/{id}          FoodItem
/// users/owner/recipes/{id}            Recipe
/// users/owner/mealPlan/current        MealPlan
/// users/owner/stores/{id}, supplementCategories/{id}, supplements/{id},
///             supplementLogs/{id}, stockLocations/{id}
/// ```
/// Only documents that changed since the last sync are written (tracked by a hash per document
/// in a small local file), so a background backup costs a handful of writes, not the whole
/// history every time.
@Observable
final class CloudBackupManager {
    private static let autoBackupKey = "CalorieBuddy.autoCloudBackup"
    /// Firestore allows up to 500 operations per batch.
    private static let batchLimit = 450

    /// The one document all data lives under — see the type's documentation.
    private static let ownerID = "owner"

    private(set) var lastCloudBackup: Date?
    private(set) var isBusy = false

    var isAvailable: Bool { FirebaseSetup.isConfigured }

    /// Whether the database is synced automatically each time the app goes to the background.
    var autoBackupEnabled: Bool = UserDefaults.standard.object(forKey: CloudBackupManager.autoBackupKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoBackupEnabled, forKey: Self.autoBackupKey) }
    }

    /// Call once at launch: signs in anonymously (if needed) and reads the last backup date.
    func start() {
        guard isAvailable else { return }
        Task { await refreshLastBackupDate() }
    }

    /// Makes sure this install has an (anonymous) Firebase session, which the security rules
    /// require. Kept across launches by Firebase, so this only hits the network the first time.
    private func ensureSignedIn() async throws {
        try requireAvailable()
        if Auth.auth().currentUser == nil {
            _ = try await Auth.auth().signInAnonymously()
        }
    }

    // MARK: Backup

    private func userDocument() async throws -> DocumentReference {
        try await ensureSignedIn()
        return Firestore.firestore().collection("users").document(Self.ownerID)
    }

    /// Syncs the current database to Firestore: writes new/changed documents and deletes ones
    /// that no longer exist locally.
    func backUp(_ store: DataStore, automatic: Bool = false) async throws {
        do {
            try await run {
                let userReference = try await userDocument()
                let database = store.databaseSnapshot().clampedForFirestore()
                var syncState = SyncState.load()
                var operations: [(DocumentReference, [String: Any]?)] = []

                for collection in CloudCollection.all(of: database) {
                    let reference = userReference.collection(collection.name)
                    // Nothing synced from this install yet: find what's already in the cloud so
                    // documents deleted locally are deleted there too.
                    var previous = syncState.hashes[collection.name]
                    if previous == nil {
                        let snapshot = try await reference.getDocuments()
                        previous = Dictionary(uniqueKeysWithValues: snapshot.documents.map { ($0.documentID, "") })
                    }
                    var current: [String: String] = [:]
                    for (id, value) in collection.documents {
                        let hash = try Self.hash(value)
                        current[id] = hash
                        if previous?[id] != hash {
                            operations.append((reference.document(id), try Firestore.Encoder().encode(value)))
                        }
                    }
                    for id in (previous ?? [:]).keys where current[id] == nil {
                        operations.append((reference.document(id), nil))
                    }
                    syncState.hashes[collection.name] = current
                }

                operations.append((userReference, [
                    "settings": try Firestore.Encoder().encode(database.settings),
                    "schemaVersion": AppDatabase.currentVersion,
                    "updatedAt": FieldValue.serverTimestamp()
                ]))

                for start in stride(from: 0, to: operations.count, by: Self.batchLimit) {
                    let batch = Firestore.firestore().batch()
                    for (document, data) in operations[start..<min(start + Self.batchLimit, operations.count)] {
                        if let data {
                            batch.setData(data, forDocument: document)
                        } else {
                            batch.deleteDocument(document)
                        }
                    }
                    try await batch.commit()
                }
                syncState.save()
                self.lastCloudBackup = .now
            }
            AppAnalytics.log(.cloudBackup(automatic: automatic, succeeded: true))
        } catch {
            AppAnalytics.log(.cloudBackup(automatic: automatic, succeeded: false))
            throw error
        }
    }

    /// Automatic sync when the app goes to the background — silently skipped when disabled or
    /// Firebase isn't configured.
    func autoBackUpIfEnabled(_ store: DataStore) async {
        guard isAvailable, autoBackupEnabled, !isBusy else { return }
        #if canImport(UIKit)
        // Ask iOS for a little extra time so the sync can finish after the app is backgrounded.
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "CloudBackup")
        defer { Task { @MainActor in UIApplication.shared.endBackgroundTask(taskID) } }
        #endif
        try? await backUp(store, automatic: true)
    }

    // MARK: Restore

    /// Replaces the local database with the one in Firestore (the current one is kept as the
    /// local backup, exactly like importing a file).
    func restore(into store: DataStore) async throws {
        do {
            try await run {
                let userReference = try await userDocument()
                let userSnapshot = try await userReference.getDocument()
                guard userSnapshot.exists else { throw CloudBackupError.noBackupFound }
                let settings = try userSnapshot.get("settings")
                    .map { try Firestore.Decoder().decode(UserSettings.self, from: $0) } ?? .default

                func fetch<T: Decodable>(_ name: String, as type: T.Type) async throws -> [T] {
                    try await userReference.collection(name).getDocuments().documents.map { try $0.data(as: T.self) }
                }
                let database = AppDatabase(
                    version: AppDatabase.currentVersion,
                    exportedAt: .now,
                    settings: settings,
                    entries: try await fetch(CloudCollection.entries, as: FoodEntry.self),
                    foodItems: try await fetch(CloudCollection.foodItems, as: FoodItem.self),
                    recipes: try await fetch(CloudCollection.recipes, as: Recipe.self),
                    stores: try await fetch(CloudCollection.stores, as: Store.self),
                    supplementCategories: try await fetch(CloudCollection.supplementCategories, as: SupplementCategory.self),
                    supplements: try await fetch(CloudCollection.supplements, as: Supplement.self),
                    supplementLogs: try await fetch(CloudCollection.supplementLogs, as: SupplementLogEntry.self),
                    stockLocations: try await fetch(CloudCollection.stockLocations, as: StockLocation.self),
                    mealPlan: try await fetch(CloudCollection.mealPlan, as: MealPlan.self).first
                )
                store.replaceDatabase(with: database)

                // What's local now is exactly what's in the cloud.
                var syncState = SyncState()
                for collection in CloudCollection.all(of: database) {
                    syncState.hashes[collection.name] = try Dictionary(
                        uniqueKeysWithValues: collection.documents.map { ($0.id, try Self.hash($0.value)) }
                    )
                }
                syncState.save()
            }
            AppAnalytics.log(.cloudRestore(succeeded: true))
        } catch {
            AppAnalytics.log(.cloudRestore(succeeded: false))
            throw error
        }
    }

    /// Reads when the cloud copy was last updated (`nil` if there's none).
    func refreshLastBackupDate() async {
        guard let reference = try? await userDocument(),
              let snapshot = try? await reference.getDocument() else {
            lastCloudBackup = nil
            return
        }
        lastCloudBackup = (snapshot.get("updatedAt") as? Timestamp)?.dateValue()
    }

    // MARK: Helpers

    private func requireAvailable() throws {
        guard isAvailable else { throw CloudBackupError.notConfigured }
    }

    /// Runs `operation` with `isBusy` set, so the UI can show progress and avoid overlaps, turning
    /// Firebase's often opaque errors into what to fix in the console.
    private func run(_ operation: () async throws -> Void) async throws {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            throw Self.explained(error)
        }
    }

    private static let logger = Logger(subsystem: "CalorieBuddy", category: "CloudBackup")

    /// Maps the Firebase errors caused by a project that isn't fully set up to instructions.
    private static func explained(_ error: Error) -> Error {
        let nsError = error as NSError
        let details = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)
            .map { "\($0.userInfo)" } ?? "\(nsError.userInfo)"
        logger.error("Cloud backup failed: \(nsError.domain, privacy: .public) \(nsError.code) \(details, privacy: .public)")

        if nsError.domain == AuthErrorDomain {
            if nsError.code == AuthErrorCode.operationNotAllowed.rawValue
                || details.contains("ADMIN_ONLY_OPERATION") {
                return CloudBackupError.consoleSetup("Ativa o início de sessão anónimo na consola Firebase: Authentication › Sign-in method › Anonymous.")
            }
            if details.contains("CONFIGURATION_NOT_FOUND") || nsError.code == AuthErrorCode.internalError.rawValue {
                return CloudBackupError.consoleSetup("A Authentication ainda não está ativa no projeto. Na consola Firebase, abre Authentication, carrega em \"Get started\" e ativa o fornecedor Anonymous.")
            }
        }
        if nsError.domain == FirestoreErrorDomain {
            switch FirestoreErrorCode.Code(rawValue: nsError.code) {
            case .permissionDenied:
                return CloudBackupError.consoleSetup("O Firestore recusou o acesso. Na consola Firebase, em Firestore Database › Rules, publica as regras do ficheiro firebase/firestore.rules.")
            case .notFound where details.contains("database") || nsError.localizedDescription.contains("database"):
                return CloudBackupError.consoleSetup("A base de dados Firestore ainda não existe. Na consola Firebase, abre Firestore Database e carrega em \"Create database\".")
            default:
                break
            }
        }
        return error
    }

    private static let hashEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// Fingerprint of a document's contents, to tell whether it changed since the last sync.
    private static func hash(_ value: any Encodable) throws -> String {
        let data = try hashEncoder.encode(value)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppDatabase {
    /// The earliest date Firestore accepts (0001-01-01T00:00:00Z) — it *crashes* the app
    /// (`NSException "Invalid timestamp"`) on anything earlier, rather than returning an error.
    static let earliestCloudDate = Date(timeIntervalSince1970: -62_135_596_800)

    /// A copy safe to write to Firestore: every date is moved up to at least
    /// `earliestCloudDate`. Needed because items saved before `createdAt` existed decode with
    /// `.distantPast`, which is two days earlier than Firestore's minimum. They still sort as the
    /// oldest items.
    func clampedForFirestore() -> AppDatabase {
        func clamp(_ date: Date) -> Date { max(date, Self.earliestCloudDate) }
        var copy = self
        copy.entries = entries.map { var entry = $0; entry.date = clamp(entry.date); return entry }
        copy.foodItems = foodItems.map { var item = $0; item.createdAt = clamp(item.createdAt); return item }
        copy.recipes = recipes.map { var recipe = $0; recipe.createdAt = clamp(recipe.createdAt); return recipe }
        copy.supplements = supplements.map { var supplement = $0; supplement.createdAt = clamp(supplement.createdAt); return supplement }
        copy.supplementLogs = supplementLogs.map { var log = $0; log.date = clamp(log.date); return log }
        copy.mealPlan?.prescribedAt = mealPlan?.prescribedAt.map(clamp)
        return copy
    }
}

/// One Firestore subcollection of `users/owner` and the documents it should contain.
private struct CloudCollection {
    static let entries = "entries"
    static let foodItems = "foodItems"
    static let recipes = "recipes"
    static let stores = "stores"
    static let supplementCategories = "supplementCategories"
    static let supplements = "supplements"
    static let supplementLogs = "supplementLogs"
    static let stockLocations = "stockLocations"
    static let mealPlan = "mealPlan"

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

    static func all(of database: AppDatabase) -> [CloudCollection] {
        [
            CloudCollection(entries, database.entries),
            CloudCollection(foodItems, database.foodItems),
            CloudCollection(recipes, database.recipes),
            CloudCollection(stores, database.stores),
            CloudCollection(supplementCategories, database.supplementCategories),
            CloudCollection(supplements, database.supplements),
            CloudCollection(supplementLogs, database.supplementLogs),
            CloudCollection(stockLocations, database.stockLocations),
            CloudCollection(name: mealPlan, documents: database.mealPlan.map { [("current", $0)] } ?? [])
        ]
    }
}

/// What was last synced from this install: a hash per document per collection.
private struct SyncState: Codable {
    var hashes: [String: [String: String]] = [:]

    private static var url: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("CalorieBuddy/cloud_sync_state.json")
    }

    static func load() -> SyncState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SyncState.self, from: data) else { return SyncState() }
        return state
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.url, options: .atomic)
    }
}
