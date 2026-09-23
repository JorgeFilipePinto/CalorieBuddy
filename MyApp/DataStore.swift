import Foundation
import Observation

enum DataStoreError: LocalizedError {
    case noBackupAvailable
    case invalidFile(String)

    var errorDescription: String? {
        switch self {
        case .noBackupAvailable:
            return "Não existe nenhuma base de dados de backup para restaurar ou descarregar."
        case .invalidFile(let reason):
            return "O ficheiro selecionado não é uma base de dados válida da CalorieBuddy (\(reason))."
        }
    }
}

/// Single source of truth for the app's data.
///
/// The "database" is simply a JSON file on disk (`active_database.json`). There is at most one
/// backup copy (`backup_database.json`), which is only ever written by `importDatabase(from:)`
/// (before overwriting the active database) and by `restoreBackup()` (which swaps the two files).
@Observable
final class DataStore {
    private(set) var entries: [FoodEntry] = []
    private(set) var foodItems: [FoodItem] = []
    private(set) var recipes: [Recipe] = []
    var settings: UserSettings = .default

    private(set) var backupTimestamp: Date?

    private let fileManager = FileManager.default
    private let activeURL: URL
    private let backupURL: URL

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("CalorieBuddy", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        activeURL = directory.appendingPathComponent("active_database.json")
        backupURL = directory.appendingPathComponent("backup_database.json")

        loadActive()
        refreshBackupTimestamp()
    }

    var hasBackup: Bool {
        fileManager.fileExists(atPath: backupURL.path)
    }

    // MARK: - Queries

    func entries(on date: Date) -> [FoodEntry] {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func totalCalories(on date: Date) -> Int {
        entries(on: date).reduce(0) { $0 + $1.calories }
    }

    /// Distinct calendar days that have at least one entry, most recent first.
    var allDays: [Date] {
        let calendar = Calendar.current
        let uniqueDays = Set(entries.map { calendar.startOfDay(for: $0.date) })
        return uniqueDays.sorted(by: >)
    }

    func foodItem(forBarcode barcode: String) -> FoodItem? {
        foodItems.first { $0.barcode == barcode }
    }

    func totalCalories(for recipe: Recipe) -> Int {
        recipe.items.reduce(0) { partial, item in
            guard let food = foodItems.first(where: { $0.id == item.foodItemID }) else { return partial }
            return partial + Int((Double(food.calories) * item.quantity).rounded())
        }
    }

    // MARK: - Mutations (auto-persisted to the active database)

    func addEntry(_ entry: FoodEntry) {
        entries.append(entry)
        persistActive()
    }

    func updateEntry(_ entry: FoodEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        persistActive()
    }

    func deleteEntry(_ entry: FoodEntry) {
        entries.removeAll { $0.id == entry.id }
        persistActive()
    }

    func updateSettings(_ newSettings: UserSettings) {
        settings = newSettings
        persistActive()
    }

    /// Logs one serving-scaled entry from a catalog food item.
    func logFoodItem(_ item: FoodItem, quantity: Double, mealType: MealType, date: Date) {
        let entry = FoodEntry(
            name: item.name,
            calories: Int((Double(item.calories) * quantity).rounded()),
            protein: item.protein.map { $0 * quantity },
            carbs: item.carbs.map { $0 * quantity },
            fat: item.fat.map { $0 * quantity },
            mealType: mealType,
            date: date,
            barcode: item.barcode
        )
        addEntry(entry)
    }

    /// Logs every food in a recipe at once, tagged with a shared group so they're recognizable
    /// as having come from the same recipe.
    func logRecipe(_ recipe: Recipe, mealType: MealType, date: Date) {
        let groupID = UUID()
        let newEntries: [FoodEntry] = recipe.items.compactMap { recipeItem in
            guard let food = foodItems.first(where: { $0.id == recipeItem.foodItemID }) else { return nil }
            return FoodEntry(
                name: food.name,
                calories: Int((Double(food.calories) * recipeItem.quantity).rounded()),
                protein: food.protein.map { $0 * recipeItem.quantity },
                carbs: food.carbs.map { $0 * recipeItem.quantity },
                fat: food.fat.map { $0 * recipeItem.quantity },
                mealType: mealType,
                date: date,
                barcode: food.barcode,
                groupID: groupID,
                groupName: recipe.name
            )
        }
        guard !newEntries.isEmpty else { return }
        entries.append(contentsOf: newEntries)
        persistActive()
    }

    // MARK: - Food catalog

    func addFoodItem(_ item: FoodItem) {
        foodItems.append(item)
        persistActive()
    }

    func updateFoodItem(_ item: FoodItem) {
        guard let index = foodItems.firstIndex(where: { $0.id == item.id }) else { return }
        foodItems[index] = item
        persistActive()
    }

    func deleteFoodItem(_ item: FoodItem) {
        foodItems.removeAll { $0.id == item.id }
        for index in recipes.indices {
            recipes[index].items.removeAll { $0.foodItemID == item.id }
        }
        persistActive()
    }

    // MARK: - Recipes

    func addRecipe(_ recipe: Recipe) {
        recipes.append(recipe)
        persistActive()
    }

    func updateRecipe(_ recipe: Recipe) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[index] = recipe
        persistActive()
    }

    func deleteRecipe(_ recipe: Recipe) {
        recipes.removeAll { $0.id == recipe.id }
        persistActive()
    }

    // MARK: - Load / persist active database

    private func loadActive() {
        guard let data = try? Data(contentsOf: activeURL),
              let database = try? decoder.decode(AppDatabase.self, from: data) else { return }
        entries = database.entries
        settings = database.settings
        foodItems = database.foodItems
        recipes = database.recipes
    }

    private func currentDatabase() -> AppDatabase {
        AppDatabase(
            version: AppDatabase.currentVersion,
            exportedAt: Date(),
            settings: settings,
            entries: entries,
            foodItems: foodItems,
            recipes: recipes
        )
    }

    private func persistActive() {
        guard let data = try? encoder.encode(currentDatabase()) else { return }
        try? data.write(to: activeURL, options: .atomic)
    }

    private func refreshBackupTimestamp() {
        guard let attributes = try? fileManager.attributesOfItem(atPath: backupURL.path),
              let modified = attributes[.modificationDate] as? Date else {
            backupTimestamp = nil
            return
        }
        backupTimestamp = modified
    }

    // MARK: - Export (download)

    /// Writes a temporary copy of the active database and returns its URL, ready to be
    /// handed to a file mover / share sheet.
    func exportActiveSnapshotURL() throws -> URL {
        try writeTempSnapshot(data: encoder.encode(currentDatabase()), name: "CalorieBuddy")
    }

    /// Writes a temporary copy of the backup database and returns its URL. Throws if there is
    /// no backup yet.
    func exportBackupSnapshotURL() throws -> URL {
        guard hasBackup else { throw DataStoreError.noBackupAvailable }
        let data = try Data(contentsOf: backupURL)
        return try writeTempSnapshot(data: data, name: "CalorieBuddy-Backup")
    }

    private func writeTempSnapshot(data: Data, name: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("\(name)-\(formatter.string(from: Date()))")
            .appendingPathExtension("json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Import (upload) / Restore

    /// Overwrites the active database with the contents of `url`. The database that was active
    /// until now is preserved as the backup (overwriting any previous backup).
    func importDatabase(from url: URL) throws {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }

        let importedData = try Data(contentsOf: url)
        let importedDatabase: AppDatabase
        do {
            importedDatabase = try decoder.decode(AppDatabase.self, from: importedData)
        } catch {
            throw DataStoreError.invalidFile(error.localizedDescription)
        }

        if fileManager.fileExists(atPath: activeURL.path) {
            let currentActiveData = try Data(contentsOf: activeURL)
            try currentActiveData.write(to: backupURL, options: .atomic)
        }

        entries = importedDatabase.entries
        settings = importedDatabase.settings
        foodItems = importedDatabase.foodItems
        recipes = importedDatabase.recipes
        persistActive()
        refreshBackupTimestamp()
    }

    /// Swaps the active and backup databases in place: the backup becomes the active database,
    /// and what used to be active becomes the new backup.
    func restoreBackup() throws {
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw DataStoreError.noBackupAvailable
        }

        let backupData = try Data(contentsOf: backupURL)
        let restoredDatabase: AppDatabase
        do {
            restoredDatabase = try decoder.decode(AppDatabase.self, from: backupData)
        } catch {
            throw DataStoreError.invalidFile(error.localizedDescription)
        }

        let activeData: Data
        if fileManager.fileExists(atPath: activeURL.path) {
            activeData = try Data(contentsOf: activeURL)
        } else {
            activeData = try encoder.encode(currentDatabase())
        }
        try activeData.write(to: backupURL, options: .atomic)

        entries = restoredDatabase.entries
        settings = restoredDatabase.settings
        foodItems = restoredDatabase.foodItems
        recipes = restoredDatabase.recipes
        persistActive()
        refreshBackupTimestamp()
    }
}
