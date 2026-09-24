import Foundation
import Observation
import UserNotifications

enum DataStoreError: LocalizedError {
    case noBackupAvailable
    case invalidFile(String)
    case invalidMealPlanFile(String)
    case noMealPlan

    var errorDescription: String? {
        switch self {
        case .noBackupAvailable:
            return "Não existe nenhuma base de dados de backup para restaurar ou descarregar."
        case .invalidFile(let reason):
            return "O ficheiro selecionado não é uma base de dados válida da CalorieBuddy (\(reason))."
        case .invalidMealPlanFile(let reason):
            return "O ficheiro selecionado não é um plano alimentar válido da CalorieBuddy (\(reason))."
        case .noMealPlan:
            return "Ainda não existe nenhum plano alimentar para exportar."
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
    private(set) var stores: [Store] = []
    private(set) var supplementCategories: [SupplementCategory] = []
    private(set) var supplements: [Supplement] = []
    private(set) var supplementLogs: [SupplementLogEntry] = []
    private(set) var stockLocations: [StockLocation] = []
    private(set) var mealPlan: MealPlan?
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
        seedExampleDataIfNeeded()
    }

    /// Seeds one example recipe and its ingredients on the very first launch, as a guide for
    /// how the catalog/recipe feature works, plus a handful of example supplements with stock
    /// in "Casa"/"Trabalho" so the supplements/stocks screens have something to show.
    ///
    /// Each batch has its *own* one-shot flag rather than sharing a single one: a feature added
    /// later (like the supplements) still gets seeded on the next launch even for an install
    /// that already passed the original food/recipe seed, instead of silently never running.
    private static let hasSeededExampleDataKey = "CalorieBuddy.hasSeededExampleData"
    // "V2" because supplement stocks moved from a freeform name to a shared `StockLocation`;
    // bumping the key makes the seed run once more for anyone who already got the V1 seed.
    private static let hasSeededTestSupplementsKey = "CalorieBuddy.hasSeededTestSupplementsV2"
    private static let hasSeededMealPlanKey = "CalorieBuddy.hasSeededMealPlanJune26"

    private func seedExampleDataIfNeeded() {
        seedFoodGuideIfNeeded()
        seedTestSupplementsIfNeeded()
        seedMealPlanIfNeeded()
    }

    /// Seeds the June 2026 meal plan (see `MealPlanSeed`) with its recipes and the catalog foods
    /// they use, reusing any catalog food that already exists under the same name.
    private func seedMealPlanIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.hasSeededMealPlanKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasSeededMealPlanKey)
        guard mealPlan == nil else { return }

        let seed = MealPlanSeed.build(existingFoods: foodItems)
        foodItems.append(contentsOf: seed.newFoods)
        recipes.append(contentsOf: seed.recipes)
        mealPlan = seed.plan
        persistActive()
    }

    private func seedFoodGuideIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.hasSeededExampleDataKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasSeededExampleDataKey)
        guard foodItems.isEmpty, recipes.isEmpty else { return }

        let supermarket = Store(name: "Continente")
        stores.append(supermarket)

        // Aveia: nutrition per 100 g, dose of 40 g, bought as a 1 kg bag for €1.79.
        let oats = FoodItem(
            name: "Aveia", brand: "Quaker", unit: .gram, doseSize: 40, nutritionBasis: .per100,
            calories: 370, protein: 13, carbs: 60, fat: 7,
            prices: [PriceEntry(storeID: supermarket.id, price: 1.79, packageSize: 1, packageUnit: .kilogram)]
        )
        // Banana: nutrition per dose (1 unidade), bought individually at €0.25 each.
        let banana = FoodItem(
            name: "Banana", unit: .unit, doseSize: 1, nutritionBasis: .perDose,
            calories: 105, protein: 1.3, carbs: 27, fat: 0.3,
            prices: [PriceEntry(storeID: supermarket.id, price: 0.25, packageSize: 1, packageUnit: .unit)]
        )
        // Leite meio-gordo: nutrition per 100 ml, dose of 200 ml, bought as a 1 L pack for €0.89.
        let milk = FoodItem(
            name: "Leite Meio-Gordo", brand: "Mimosa", unit: .milliliter, doseSize: 200, nutritionBasis: .per100,
            calories: 48, protein: 3.4, carbs: 4.8, fat: 1.8,
            prices: [PriceEntry(storeID: supermarket.id, price: 0.89, packageSize: 1, packageUnit: .liter)]
        )
        foodItems.append(contentsOf: [oats, banana, milk])

        recipes.append(
            Recipe(
                name: "Papas de Aveia com Banana",
                items: [
                    RecipeItem(foodItemID: oats.id, quantity: 1),
                    RecipeItem(foodItemID: banana.id, quantity: 1),
                    RecipeItem(foodItemID: milk.id, quantity: 1)
                ]
            )
        )

        persistActive()
    }

    private func seedTestSupplementsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.hasSeededTestSupplementsKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasSeededTestSupplementsKey)
        guard supplementCategories.isEmpty, supplements.isEmpty else { return }

        let proteinCategory = SupplementCategory(name: "Proteína")
        let gelCategory = SupplementCategory(name: "Gel Energético")
        let isotonicCategory = SupplementCategory(name: "Isotónico")
        let electrolyteCategory = SupplementCategory(name: "Eletrólitos")
        supplementCategories.append(contentsOf: [proteinCategory, gelCategory, isotonicCategory, electrolyteCategory])

        let sportsStore = Store(name: "Prozis")
        stores.append(sportsStore)

        // Shared stock locations — every supplement below reuses these same two, instead of
        // each having its own separate "Casa"/"Trabalho" text.
        let home = StockLocation(name: "Casa")
        let work = StockLocation(name: "Trabalho")
        stockLocations.append(contentsOf: [home, work])

        // Whey Protein: 900 g tub, 30 g scoop, bought at Prozis for €24.99. Trabalho stock is
        // below its threshold, so it shows the "buy more" flag.
        let whey = Supplement(
            name: "Whey Protein", categoryID: proteinCategory.id, unit: .gram, totalSize: 900, doseSize: 30,
            calories: 120, protein: 24, carbs: 2, fat: 1.5,
            prices: [PriceEntry(storeID: sportsStore.id, price: 24.99, packageSize: 900, packageUnit: .gram)],
            stocks: [
                SupplementStock(locationID: home.id, remaining: 450),
                SupplementStock(locationID: work.id, remaining: 120)
            ],
            lowStockThreshold: 150
        )

        // Gel Energético: box of 5, 1 gel per dose, bought at Prozis for €7.50. Trabalho is
        // almost out, so it shows the "buy more" flag too.
        let gel = Supplement(
            name: "Gel de Cafeína", categoryID: gelCategory.id, unit: .unit, totalSize: 5, doseSize: 1,
            calories: 100, protein: 0, carbs: 22, fat: 0,
            prices: [PriceEntry(storeID: sportsStore.id, price: 7.50, packageSize: 5, packageUnit: .unit)],
            stocks: [
                SupplementStock(locationID: home.id, remaining: 8),
                SupplementStock(locationID: work.id, remaining: 1)
            ],
            lowStockThreshold: 2
        )

        // Isotónico em pó: 1 kg tub, 25 g scoop per serving, bought at Prozis for €15.90.
        let isotonic = Supplement(
            name: "Isotónico em Pó", categoryID: isotonicCategory.id, unit: .gram, totalSize: 1000, doseSize: 25,
            calories: 90, protein: 0, carbs: 21, fat: 0,
            prices: [PriceEntry(storeID: sportsStore.id, price: 15.90, packageSize: 1, packageUnit: .kilogram)],
            stocks: [
                SupplementStock(locationID: home.id, remaining: 600),
                SupplementStock(locationID: work.id, remaining: 200)
            ],
            lowStockThreshold: 150
        )

        // Comprimidos de eletrólitos: tube of 20, bought at Prozis for €9.99.
        let electrolytes = Supplement(
            name: "Eletrólitos", categoryID: electrolyteCategory.id, unit: .unit, totalSize: 20, doseSize: 1,
            calories: 5, protein: 0, carbs: 1, fat: 0,
            prices: [PriceEntry(storeID: sportsStore.id, price: 9.99, packageSize: 20, packageUnit: .unit)],
            stocks: [
                SupplementStock(locationID: home.id, remaining: 15),
                SupplementStock(locationID: work.id, remaining: 15)
            ],
            lowStockThreshold: 5
        )

        supplements = [whey, gel, isotonic, electrolytes]

        persistActive()
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
        foodItems.first { $0.barcodes.contains(barcode) }
    }

    func totalCalories(for recipe: Recipe) -> Int {
        recipe.items.reduce(0) { partial, item in
            guard let food = foodItems.first(where: { $0.id == item.foodItemID }) else { return partial }
            return partial + food.scaledCalories(quantity: item.quantity)
        }
    }

    func recipe(withID id: UUID) -> Recipe? {
        recipes.first { $0.id == id }
    }

    /// Calories and macros of one serving of `recipe`, summed over its catalog foods.
    func nutrition(for recipe: Recipe) -> NutritionTotals {
        nutrition(of: recipe.items)
    }

    /// Calories and macros of a list of catalog foods and their quantities.
    func nutrition(of items: [RecipeItem]) -> NutritionTotals {
        items.reduce(into: NutritionTotals()) { totals, item in
            guard let food = foodItems.first(where: { $0.id == item.foodItemID }) else { return }
            totals.calories += food.scaledCalories(quantity: item.quantity)
            totals.protein += food.scaledProtein(quantity: item.quantity) ?? 0
            totals.carbs += food.scaledCarbs(quantity: item.quantity) ?? 0
            totals.fat += food.scaledFat(quantity: item.quantity) ?? 0
        }
    }

    func store(withID id: UUID) -> Store? {
        stores.first { $0.id == id }
    }

    /// The cheapest known price for `item`, across every store it's priced at.
    func cheapestPrice(for item: any Doseable) -> PriceEntry? {
        item.cheapestPrice
    }

    /// Cost of `quantity` doses of `item`, using its cheapest known price. Correctly accounts
    /// for the item's dose size vs. the price's package size, even when entered in different
    /// but compatible units (e.g. a 40 g dose priced per kilogram).
    func cost(for item: any Doseable, quantity: Double) -> Double? {
        item.cost(quantity: quantity)
    }

    /// Estimated cost of one serving of `recipe`, using the cheapest known price for each
    /// ingredient. Ingredients with no price are simply left out of the total.
    func totalCost(for recipe: Recipe) -> Double {
        recipe.items.reduce(0) { partial, recipeItem in
            guard let food = foodItems.first(where: { $0.id == recipeItem.foodItemID }),
                  let itemCost = cost(for: food, quantity: recipeItem.quantity) else { return partial }
            return partial + itemCost
        }
    }

    // MARK: - Supplements

    func supplementCategory(withID id: UUID) -> SupplementCategory? {
        supplementCategories.first { $0.id == id }
    }

    func supplement(withID id: UUID) -> Supplement? {
        supplements.first { $0.id == id }
    }

    func supplementLogs(on date: Date) -> [SupplementLogEntry] {
        supplementLogs.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func stockLocation(withID id: UUID) -> StockLocation? {
        stockLocations.first { $0.id == id }
    }

    func addStockLocation(_ location: StockLocation) {
        stockLocations.append(location)
        persistActive()
    }

    func totalSupplementCalories(on date: Date) -> Int {
        supplementLogs(on: date).reduce(0) { partial, log in
            guard let supplement = supplement(withID: log.supplementID) else { return partial }
            return partial + supplement.scaledCalories(quantity: log.quantity)
        }
    }

    func totalSupplementProtein(on date: Date) -> Double {
        supplementLogs(on: date).reduce(0) { partial, log in
            guard let supplement = supplement(withID: log.supplementID) else { return partial }
            return partial + (supplement.scaledProtein(quantity: log.quantity) ?? 0)
        }
    }

    func totalSupplementCarbs(on date: Date) -> Double {
        supplementLogs(on: date).reduce(0) { partial, log in
            guard let supplement = supplement(withID: log.supplementID) else { return partial }
            return partial + (supplement.scaledCarbs(quantity: log.quantity) ?? 0)
        }
    }

    func totalSupplementFat(on date: Date) -> Double {
        supplementLogs(on: date).reduce(0) { partial, log in
            guard let supplement = supplement(withID: log.supplementID) else { return partial }
            return partial + (supplement.scaledFat(quantity: log.quantity) ?? 0)
        }
    }

    func addSupplementCategory(_ category: SupplementCategory) {
        supplementCategories.append(category)
        persistActive()
    }

    func addSupplement(_ supplement: Supplement) {
        supplements.append(supplement)
        persistActive()
    }

    func updateSupplement(_ supplement: Supplement) {
        guard let index = supplements.firstIndex(where: { $0.id == supplement.id }) else { return }
        supplements[index] = supplement
        persistActive()
    }

    func deleteSupplement(_ supplement: Supplement) {
        supplements.removeAll { $0.id == supplement.id }
        supplementLogs.removeAll { $0.supplementID == supplement.id }
        persistActive()
    }

    func toggleFavorite(_ supplement: Supplement) {
        guard let index = supplements.firstIndex(where: { $0.id == supplement.id }) else { return }
        supplements[index].isFavorite.toggle()
        persistActive()
    }

    func deleteSupplementLog(_ log: SupplementLogEntry) {
        supplementLogs.removeAll { $0.id == log.id }
        persistActive()
    }

    /// Logs `quantity` doses of `supplement`, decrementing `stockID`'s remaining amount if given.
    /// Returns `true` if that stock has now dropped to or below the supplement's low-stock
    /// threshold, in which case a local notification is also fired.
    @discardableResult
    func logSupplement(_ supplement: Supplement, stockID: UUID?, quantity: Double, date: Date) -> Bool {
        supplementLogs.append(SupplementLogEntry(supplementID: supplement.id, stockID: stockID, quantity: quantity, date: date))

        var isLowStock = false
        var lowStockLocationName = ""
        if let stockID,
           let supplementIndex = supplements.firstIndex(where: { $0.id == supplement.id }),
           let stockIndex = supplements[supplementIndex].stocks.firstIndex(where: { $0.id == stockID }) {
            supplements[supplementIndex].stocks[stockIndex].remaining -= quantity * supplement.doseSize
            if let threshold = supplement.lowStockThreshold,
               supplements[supplementIndex].stocks[stockIndex].remaining <= threshold {
                isLowStock = true
                let locationID = supplements[supplementIndex].stocks[stockIndex].locationID
                lowStockLocationName = stockLocation(withID: locationID)?.name ?? "stock"
            }
        }
        persistActive()
        if isLowStock {
            sendLowStockNotification(supplementName: supplement.name, locationName: lowStockLocationName)
        }
        return isLowStock
    }

    /// Fires a local notification so a low-stock warning reaches the user even outside the app
    /// (lock screen / notification center), not just the in-app alert shown right after logging.
    private func sendLowStockNotification(supplementName: String, locationName: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Stock Baixo"
            content.body = "\(supplementName) (\(locationName)) está a acabar — talvez seja altura de comprar mais."
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
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

    /// Logs one dose-scaled entry from a catalog food item.
    func logFoodItem(_ item: FoodItem, quantity: Double, mealType: MealType, date: Date) {
        let entry = FoodEntry(
            name: item.name,
            calories: item.scaledCalories(quantity: quantity),
            protein: item.scaledProtein(quantity: quantity),
            carbs: item.scaledCarbs(quantity: quantity),
            fat: item.scaledFat(quantity: quantity),
            mealType: mealType,
            date: date,
            barcode: item.barcodes.first
        )
        addEntry(entry)
    }

    /// Logs every food in a recipe at once, tagged with a shared group so they're recognizable
    /// as having come from the same recipe.
    func logRecipe(_ recipe: Recipe, mealType: MealType, date: Date) {
        logFoods(recipe.items, groupName: recipe.name, mealType: mealType, date: date)
    }

    /// Logs a list of catalog foods at once (e.g. a recipe with some foods swapped), tagged with
    /// a shared group named `groupName`.
    func logFoods(_ items: [RecipeItem], groupName: String, mealType: MealType, date: Date) {
        let groupID = UUID()
        let newEntries: [FoodEntry] = items.compactMap { recipeItem in
            guard let food = foodItems.first(where: { $0.id == recipeItem.foodItemID }) else { return nil }
            return FoodEntry(
                name: food.name,
                calories: food.scaledCalories(quantity: recipeItem.quantity),
                protein: food.scaledProtein(quantity: recipeItem.quantity),
                carbs: food.scaledCarbs(quantity: recipeItem.quantity),
                fat: food.scaledFat(quantity: recipeItem.quantity),
                mealType: mealType,
                date: date,
                barcode: food.barcodes.first,
                groupID: groupID,
                groupName: groupName
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

    func toggleFavorite(_ item: FoodItem) {
        guard let index = foodItems.firstIndex(where: { $0.id == item.id }) else { return }
        foodItems[index].isFavorite.toggle()
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

    func toggleFavorite(_ recipe: Recipe) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[index].isFavorite.toggle()
        persistActive()
    }

    // MARK: - Meal plan

    /// Links one option of the meal plan to `recipeID` (or unlinks it, with `nil`).
    func linkMealPlanOption(_ optionID: UUID, inMeal mealID: UUID, toRecipe recipeID: UUID?) {
        guard let mealIndex = mealPlan?.meals.firstIndex(where: { $0.id == mealID }),
              let optionIndex = mealPlan?.meals[mealIndex].options.firstIndex(where: { $0.id == optionID }) else { return }
        mealPlan?.meals[mealIndex].options[optionIndex].recipeID = recipeID
        persistActive()
    }

    /// Removes the meal plan. Its recipes and foods stay in the catalog.
    func deleteMealPlan() {
        mealPlan = nil
        persistActive()
    }

    /// Writes the meal plan, plus every recipe it links to and every food those recipes use, to
    /// a temporary JSON file and returns its URL, ready to be handed to a file mover.
    func exportMealPlanURL() throws -> URL {
        guard let mealPlan else { throw DataStoreError.noMealPlan }
        let recipeIDs = Set(mealPlan.meals.flatMap(\.options).compactMap(\.recipeID))
        let linkedRecipes = recipes.filter { recipeIDs.contains($0.id) }
        let foodIDs = Set(linkedRecipes.flatMap(\.items).map(\.foodItemID))
        // Prices point at stores that won't exist in another database, so they're left out.
        let linkedFoods = foodItems.filter { foodIDs.contains($0.id) }.map { food in
            var food = food
            food.prices = []
            return food
        }
        let file = MealPlanFile(
            format: MealPlanFile.formatIdentifier,
            version: MealPlanFile.currentVersion,
            exportedAt: Date(),
            plan: mealPlan,
            recipes: linkedRecipes,
            foodItems: linkedFoods
        )
        return try writeTempSnapshot(data: encoder.encode(file), name: "PlanoAlimentar")
    }

    /// Replaces the meal plan with the one in `url`. Recipes and foods in the file are added to
    /// the catalog unless one with the same ID already exists, in which case the existing one
    /// is kept (so re-importing a plan never overwrites edits made in the app).
    func importMealPlan(from url: URL) throws {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let file: MealPlanFile
        do {
            file = try decoder.decode(MealPlanFile.self, from: data)
        } catch {
            throw DataStoreError.invalidMealPlanFile(error.localizedDescription)
        }
        guard file.format == MealPlanFile.formatIdentifier else {
            throw DataStoreError.invalidMealPlanFile("formato \"\(file.format)\" desconhecido")
        }

        let existingFoodIDs = Set(foodItems.map(\.id))
        foodItems.append(contentsOf: file.foodItems.filter { !existingFoodIDs.contains($0.id) })
        let existingRecipeIDs = Set(recipes.map(\.id))
        recipes.append(contentsOf: file.recipes.filter { !existingRecipeIDs.contains($0.id) })
        mealPlan = file.plan
        persistActive()
    }

    // MARK: - Stores

    func addStore(_ store: Store) {
        stores.append(store)
        persistActive()
    }

    func updateStore(_ store: Store) {
        guard let index = stores.firstIndex(where: { $0.id == store.id }) else { return }
        stores[index] = store
        persistActive()
    }

    func deleteStore(_ store: Store) {
        stores.removeAll { $0.id == store.id }
        for index in foodItems.indices {
            foodItems[index].prices.removeAll { $0.storeID == store.id }
        }
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
        stores = database.stores
        supplementCategories = database.supplementCategories
        supplements = database.supplements
        supplementLogs = database.supplementLogs
        stockLocations = database.stockLocations
        mealPlan = database.mealPlan
    }

    /// Re-reads the active database file from disk and updates in-memory state to match it.
    ///
    /// Every mutation in this class already updates in-memory state directly and persists it,
    /// so under normal use this is a no-op. It exists as a manual refresh (pull-to-refresh) so
    /// there's always a way to force the UI back in sync with what's actually on disk.
    func reloadFromDisk() {
        loadActive()
        refreshBackupTimestamp()
    }

    private func currentDatabase() -> AppDatabase {
        AppDatabase(
            version: AppDatabase.currentVersion,
            exportedAt: Date(),
            settings: settings,
            entries: entries,
            foodItems: foodItems,
            recipes: recipes,
            stores: stores,
            supplementCategories: supplementCategories,
            supplements: supplements,
            supplementLogs: supplementLogs,
            stockLocations: stockLocations,
            mealPlan: mealPlan
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

    // MARK: - View / edit raw JSON

    /// The active database as pretty-printed JSON, exactly as it would be exported.
    func activeDatabaseJSON() throws -> String {
        let data = try encoder.encode(currentDatabase())
        guard let string = String(data: data, encoding: .utf8) else {
            throw DataStoreError.invalidFile("codificação de texto inválida")
        }
        return string
    }

    /// Parses `json` and replaces the active database with it, exactly like importing a file:
    /// the database that was active until now is preserved as the backup first.
    func applyEditedJSON(_ json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw DataStoreError.invalidFile("codificação de texto inválida")
        }
        let editedDatabase: AppDatabase
        do {
            editedDatabase = try decoder.decode(AppDatabase.self, from: data)
        } catch {
            throw DataStoreError.invalidFile(error.localizedDescription)
        }
        adoptAsActive(editedDatabase)
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

        adoptAsActive(importedDatabase)
    }

    /// Backs up the current active database (if any) and adopts `database` as the new active one.
    private func adoptAsActive(_ database: AppDatabase) {
        if fileManager.fileExists(atPath: activeURL.path),
           let currentActiveData = try? Data(contentsOf: activeURL) {
            try? currentActiveData.write(to: backupURL, options: .atomic)
        }

        entries = database.entries
        settings = database.settings
        foodItems = database.foodItems
        recipes = database.recipes
        stores = database.stores
        supplementCategories = database.supplementCategories
        supplements = database.supplements
        supplementLogs = database.supplementLogs
        stockLocations = database.stockLocations
        mealPlan = database.mealPlan
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
        stores = restoredDatabase.stores
        supplementCategories = restoredDatabase.supplementCategories
        supplements = restoredDatabase.supplements
        supplementLogs = restoredDatabase.supplementLogs
        stockLocations = restoredDatabase.stockLocations
        mealPlan = restoredDatabase.mealPlan
        persistActive()
        refreshBackupTimestamp()
    }

    // MARK: - Delete everything

    /// Wipes every piece of data this app stores locally — entries, catalog, recipes, meal plan,
    /// stores, supplements and settings — including the on-disk backup. Does not touch Apple Health.
    func deleteEverything() {
        entries = []
        foodItems = []
        recipes = []
        stores = []
        supplementCategories = []
        supplements = []
        supplementLogs = []
        stockLocations = []
        mealPlan = nil
        settings = .default
        try? fileManager.removeItem(at: backupURL)
        backupTimestamp = nil
        persistActive()
    }
}
