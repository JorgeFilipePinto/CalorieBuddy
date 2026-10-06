import Foundation
import Observation
import UserNotifications

enum DataStoreError: LocalizedError {
    case noBackupAvailable
    case invalidFile(String)
    case invalidMealPlanFile(String)

    var errorDescription: String? {
        switch self {
        case .noBackupAvailable:
            return "Não existe nenhuma base de dados de backup para restaurar ou descarregar."
        case .invalidFile(let reason):
            return "O ficheiro selecionado não é uma base de dados válida da CalorieBuddy (\(reason))."
        case .invalidMealPlanFile(let reason):
            return "O ficheiro selecionado não é um plano alimentar válido da CalorieBuddy (\(reason))."
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
    private(set) var foodCategories: [FoodCategory] = []
    private(set) var recipes: [Recipe] = []
    private(set) var stores: [Store] = []
    private(set) var supplementCategories: [SupplementCategory] = []
    private(set) var supplements: [Supplement] = []
    private(set) var supplementLogs: [SupplementLogEntry] = []
    private(set) var stockLocations: [StockLocation] = []
    private(set) var mealPlans: [MealPlan] = []
    private(set) var nutritionPlans: [NutritionPlan] = []
    private(set) var bodyMeasurements: [BodyMeasurement] = []
    private(set) var progressPhotos: [ProgressPhoto] = []
    private(set) var pantryLocations: [PantryLocation] = []
    private(set) var pantryLots: [PantryLot] = []
    private(set) var cookingYields: [CookingYield] = []
    private(set) var mealPreps: [MealPrep] = []
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
        removeOrphanPhotos()
        linkDiaryEntriesToFoodsIfNeeded()
        if moveMealPlansToMealStages() { persistActive() }
    }

    /// Meal plans written when the diary only had four meals filed mid-morning, evening and
    /// training meals under `.snack`; by their name they move to the stage that now exists
    /// ("Meio da Manhã" → mid-morning, "Noite"/"Ceia" → supper, "Pré-/Pós-treino"). Idempotent;
    /// returns whether anything changed (the caller persists).
    @discardableResult
    private func moveMealPlansToMealStages() -> Bool {
        var changed = false
        for planIndex in mealPlans.indices {
            for mealIndex in mealPlans[planIndex].meals.indices where mealPlans[planIndex].meals[mealIndex].mealType == .snack {
                let name = SearchMatch.normalized(mealPlans[planIndex].meals[mealIndex].name)
                let stage: MealType? = if name.contains("meio da manha") || name.contains("manha") {
                    .morningSnack
                } else if name.contains("noite") || name.contains("ceia") {
                    .supper
                } else if name.contains("pre-treino") || name.contains("pre treino") {
                    .preWorkout
                } else if name.contains("pos-treino") || name.contains("pos treino") {
                    .postWorkout
                } else {
                    nil
                }
                if let stage {
                    mealPlans[planIndex].meals[mealIndex].mealType = stage
                    changed = true
                }
            }
        }
        return changed
    }

    /// Entries logged before they recorded their food: once, link each one to the catalog food of
    /// the same name when some quantity of it reproduces the entry's kcal and macros — so editing
    /// that food updates them too. Values aren't touched here; anything ambiguous stays unlinked.
    private func linkDiaryEntriesToFoodsIfNeeded() {
        let key = "CalorieBuddy.hasLinkedDiaryEntries"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        if linkUnlinkedDiaryEntries() > 0 { persistActive() }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Links what it can (see `linkDiaryEntriesToFoodsIfNeeded`) and returns how many; the caller
    /// persists. Also run on a database adopted from elsewhere (restore, import).
    @discardableResult
    private func linkUnlinkedDiaryEntries() -> Int {
        var linked = 0
        let foodsByName = Dictionary(grouping: foodItems) { $0.name.trimmingCharacters(in: .whitespaces).lowercased() }
        for index in entries.indices where entries[index].foodItemID == nil {
            let entry = entries[index]
            guard let candidates = foodsByName[entry.name.trimmingCharacters(in: .whitespaces).lowercased()],
                  candidates.count == 1, let food = candidates.first else { continue }
            let perDose = food.nutrition(quantity: 1)
            guard perDose.calories > 0, entry.calories > 0 else { continue }
            let quantity = Double(entry.calories) / perDose.calories
            func matches(_ stated: Double?, _ perDose: Double?) -> Bool {
                guard let stated, let perDose else { return true }
                return abs(stated - perDose * quantity) <= max(1, stated * 0.05)
            }
            guard matches(entry.protein, perDose.protein), matches(entry.carbs, perDose.carbs),
                  matches(entry.fat, perDose.fat) else { continue }
            entries[index].foodItemID = food.id
            entries[index].quantity = (quantity * 1000).rounded() / 1000
            linked += 1
        }
        return linked
    }

    /// Deletes photo files no record points at — neither in the active database nor in the
    /// backup (so "Restaurar Backup" still finds its photos). Done once at launch rather than on
    /// every delete; it also clears photos taken in an editor that was then cancelled.
    private func removeOrphanPhotos() {
        var referenced = Self.photoIDs(in: currentDatabase())
        if let data = try? Data(contentsOf: backupURL), let backup = try? decoder.decode(AppDatabase.self, from: data) {
            referenced.formUnion(Self.photoIDs(in: backup))
        }
        for id in PhotoStore.storedIDs().subtracting(referenced) {
            PhotoStore.delete(id)
        }
    }

    /// Bumped on every change the user makes (adding a food, logging a dose, a new photo…), so the
    /// app syncs right away and the platform — and the dashboard — never lag behind. Records that
    /// came from elsewhere (the platform, a file, the backup) or a wipe don't count.
    private(set) var localChangeCount = 0

    private static func photoIDs(in database: AppDatabase) -> Set<UUID> {
        Set(database.foodItems.compactMap(\.photoID)
            + database.recipes.compactMap(\.photoID)
            + database.supplements.compactMap(\.photoID)
            + database.progressPhotos.map(\.photoID)
            + database.foodItems.flatMap(\.labelPhotoIDs)
            + database.recipes.flatMap(\.labelPhotoIDs)
            + database.supplements.flatMap(\.labelPhotoIDs))
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
    private static let hasSeededNutritionPlanKey = "CalorieBuddy.hasSeededNutritionPlan"
    private static let hasSeededFoodCategoriesKey = "CalorieBuddy.hasSeededFoodCategories"

    private func seedExampleDataIfNeeded() {
        // With a platform configured, the data comes from it at sign-in: example foods, supplements
        // and the June meal plan would only end up duplicated there.
        if SupabaseConfig.current == nil {
            seedFoodGuideIfNeeded()
            seedTestSupplementsIfNeeded()
            seedMealPlanIfNeeded()
        }
        seedNutritionPlanIfNeeded()
        seedFoodCategoriesIfNeeded()
    }

    /// Default food categories (all editable), and a first sort of the existing catalog: each
    /// uncategorised food goes to the category of its dominant macro (protein, carbs or fat).
    /// Runs once; foods it can't place stay uncategorised.
    private func seedFoodCategoriesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.hasSeededFoodCategoriesKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasSeededFoodCategoriesKey)
        guard foodCategories.isEmpty else { return }

        let protein = FoodCategory(name: "Proteína")
        let carbs = FoodCategory(name: "Hidratos de carbono")
        let fat = FoodCategory(name: "Gordura")
        foodCategories = [
            protein, carbs, fat,
            FoodCategory(name: "Gordura saturada"),
            FoodCategory(name: "Fruta"),
            FoodCategory(name: "Vegetais"),
            FoodCategory(name: "Laticínios"),
            FoodCategory(name: "Outros")
        ]
        for index in foodItems.indices where foodItems[index].categoryID == nil {
            switch foodItems[index].dominantMacro {
            case .protein: foodItems[index].categoryID = protein.id
            case .carbs: foodItems[index].categoryID = carbs.id
            case .fat: foodItems[index].categoryID = fat.id
            case .calories: break
            }
        }
        persistActive()
    }

    /// Seeds one initial nutrition plan carrying over whatever daily goals were already set (the
    /// app didn't distinguish training/rest before), so training and rest targets start out the
    /// same and `DayView` always has a plan in effect from the very first day.
    private func seedNutritionPlanIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.hasSeededNutritionPlanKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasSeededNutritionPlanKey)
        guard nutritionPlans.isEmpty else { return }

        let targets = NutritionTargets(
            kcal: max(settings.dailyCalorieGoal, 500),
            proteinG: Int(settings.proteinGoal ?? 150),
            carbsG: Int(settings.carbsGoal ?? 250),
            fatG: Int(settings.fatGoal ?? 70),
            waterML: settings.dailyWaterGoalML ?? 2000
        )
        nutritionPlans = [
            NutritionPlan(name: "Plano Inicial", startsOn: .distantPast, training: targets, rest: targets)
        ]
        persistActive()
    }

    /// Seeds the June 2026 meal plan (see `MealPlanSeed`) with its recipes and the catalog foods
    /// they use, reusing any catalog food that already exists under the same name.
    private func seedMealPlanIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.hasSeededMealPlanKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasSeededMealPlanKey)
        guard mealPlans.isEmpty else { return }

        let seed = MealPlanSeed.build(existingFoods: foodItems)
        foodItems.append(contentsOf: seed.newFoods)
        recipes.append(contentsOf: seed.recipes)
        var plan = seed.plan
        plan.startsOn = plan.prescribedAt ?? .distantPast
        mealPlans = [plan]
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

    func supplement(forBarcode barcode: String) -> Supplement? {
        supplements.first { $0.barcodes.contains(barcode) }
    }

    /// Adds a scanned barcode to an existing supplement (e.g. the first time its package is
    /// scanned), so the next scan finds it straight away. Returns the updated supplement.
    @discardableResult
    func addBarcode(_ barcode: String, toSupplement supplementID: UUID) -> Supplement? {
        guard let index = supplements.firstIndex(where: { $0.id == supplementID }) else { return nil }
        if !supplements[index].barcodes.contains(barcode) {
            supplements[index].barcodes.append(barcode)
            persistActive()
        }
        return supplements[index]
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

    /// The whole nutrition label of a list of catalog foods and their quantities (a recipe).
    func fullNutrition(of items: [RecipeItem]) -> NutritionAmounts {
        items.reduce(.zero) { total, item in
            guard let food = foodItems.first(where: { $0.id == item.foodItemID }) else { return total }
            return total + food.nutrition(quantity: item.quantity)
        }
    }

    /// How much food `items` add up to, per kind of unit: "350 g · 200 ml · 2 unidades".
    func amountSummary(of items: [RecipeItem]) -> String {
        var totals: [MeasurementUnit: Double] = [:]
        for item in items {
            guard let food = foodItems.first(where: { $0.id == item.foodItemID }) else { continue }
            totals[food.unit.baseUnit, default: 0] += item.quantity * food.doseSize * food.unit.baseMultiplier
        }
        return [MeasurementUnit.gram, .milliliter, .unit].compactMap { unit in
            guard let amount = totals[unit], amount > 0 else { return nil }
            let number = RecipeIngredientEditorView.number(amount)
            return unit == .unit ? "\(number) \(amount == 1 ? "unidade" : "unidades")" : "\(number) \(unit.shortLabel)"
        }
        .joined(separator: " · ")
    }

    /// Everything eaten on `date`: the diary entries plus the supplement intakes.
    func fullNutrition(on date: Date) -> NutritionAmounts {
        let eaten = entries(on: date).reduce(NutritionAmounts.zero) { $0 + $1.nutrition }
        return supplementLogs(on: date).reduce(eaten) { total, log in
            guard let supplement = supplement(withID: log.supplementID) else { return total }
            return total + supplement.nutrition(quantity: log.quantity)
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

    // MARK: - Body measurements

    /// Every value of `metric`, most recent first.
    func bodyMeasurements(of metric: BodyMetric) -> [BodyMeasurement] {
        bodyMeasurements.filter { $0.metric == metric }.sorted { $0.date > $1.date }
    }

    // MARK: - Progress photos

    /// Every progress photo, most recent first.
    var progressPhotosByDate: [ProgressPhoto] {
        progressPhotos.sorted { $0.date > $1.date }
    }

    func addProgressPhotos(_ photos: [ProgressPhoto]) {
        progressPhotos.append(contentsOf: photos)
        persistActive()
    }

    func deleteProgressPhoto(_ photo: ProgressPhoto) {
        progressPhotos.removeAll { $0.id == photo.id }
        persistActive()
    }

    func addBodyMeasurements(_ measurements: [BodyMeasurement]) {
        bodyMeasurements.append(contentsOf: measurements)
        persistActive()
    }

    func deleteBodyMeasurement(_ measurement: BodyMeasurement) {
        bodyMeasurements.removeAll { $0.id == measurement.id }
        persistActive()
    }

    func addSupplementCategory(_ category: SupplementCategory) {
        supplementCategories.append(category)
        persistActive()
    }

    func addSupplement(_ supplement: Supplement) {
        supplements.append(supplement)
        persistActive()
    }

    /// The category named `name` (case-insensitive), created if it doesn't exist yet — so an
    /// AI-imported supplement lands in the user's own category rather than a duplicate of it.
    /// An empty name falls back to "Outros".
    func supplementCategory(named name: String?) -> SupplementCategory {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespaces)
        let wanted = trimmed.isEmpty ? "Outros" : trimmed
        if let existing = supplementCategories.first(where: { $0.name.matchesImportedName(wanted) }) {
            return existing
        }
        let category = SupplementCategory(name: wanted)
        addSupplementCategory(category)
        return category
    }

    /// The supplement an AI-imported one stands for: an existing one with the same name
    /// (case-insensitive), kept as it is, or else a new one added in its category.
    @discardableResult
    func catalogSupplement(for payload: SupplementImportPayload) -> Supplement {
        let name = payload.name.trimmingCharacters(in: .whitespaces)
        if let existing = supplements.first(where: { $0.name.matchesImportedName(name) }) {
            return existing
        }
        let supplement = payload.makeSupplement(categoryID: supplementCategory(named: payload.category).id)
        addSupplement(supplement)
        return supplement
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

    /// Removes an intake (e.g. logged by mistake) and gives its doses back to the stock they were
    /// taken from, if that stock still exists.
    func deleteSupplementLog(_ log: SupplementLogEntry) {
        supplementLogs.removeAll { $0.id == log.id }
        if let stockID = log.stockID,
           let supplementIndex = supplements.firstIndex(where: { $0.id == log.supplementID }),
           let stockIndex = supplements[supplementIndex].stocks.firstIndex(where: { $0.id == stockID }) {
            supplements[supplementIndex].stocks[stockIndex].remaining += log.quantity * supplements[supplementIndex].doseSize
        }
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

    /// Logs several catalog foods at once (`items`: food + doses), in one save.
    func logFoodItems(_ items: [RecipeItem], mealType: MealType, date: Date) {
        let newEntries: [FoodEntry] = items.compactMap { line in
            guard line.quantity > 0, let item = foodItems.first(where: { $0.id == line.foodItemID }) else { return nil }
            var entry = FoodEntry(name: item.name, nutrition: item.nutrition(quantity: line.quantity), mealType: mealType,
                                  date: date, barcode: item.barcodes.first)
            entry.foodItemID = item.id
            entry.quantity = line.quantity
            return entry
        }
        guard !newEntries.isEmpty else { return }
        entries.append(contentsOf: newEntries)
        persistActive()
    }

    /// Logs one dose-scaled entry from a catalog food item.
    func logFoodItem(_ item: FoodItem, quantity: Double, mealType: MealType, date: Date) {
        var entry = FoodEntry(
            name: item.name,
            nutrition: item.nutrition(quantity: quantity),
            mealType: mealType,
            date: date,
            barcode: item.barcodes.first
        )
        entry.foodItemID = item.id
        entry.quantity = quantity
        addEntry(entry)
    }

    /// Logs a recipe: one entry per ingredient, tagged with a shared group and linked to the
    /// recipe. `items` are the amounts actually eaten (the recipe's own amounts are only the
    /// defaults); an ingredient at 0 is left out.
    func logRecipe(_ recipe: Recipe, items: [RecipeItem]? = nil, mealType: MealType, date: Date) {
        logFoods((items ?? recipe.items).filter { $0.quantity > 0 }, groupName: recipe.name, mealType: mealType,
                 date: date, recipeID: recipe.id)
    }

    /// The entries of one logged recipe (or meal-plan option), oldest first.
    func entries(inGroup groupID: UUID) -> [FoodEntry] {
        entries.filter { $0.groupID == groupID }.sorted { $0.date < $1.date }
    }

    /// Logs a recipe group again with new amounts, meal or time, in place (same group); an entry
    /// whose food is still there keeps its id. An ingredient at 0 is removed.
    func relogRecipe(_ recipe: Recipe, group groupID: UUID, items: [RecipeItem], mealType: MealType, date: Date) {
        let old = entries(inGroup: groupID)
        guard !old.isEmpty else { return }
        var replaced = linkedEntries(for: items.filter { $0.quantity > 0 }, groupID: groupID, groupName: recipe.name,
                                     mealType: mealType, date: date, recipeID: recipe.id)
        for index in replaced.indices {
            if let previous = old.first(where: { $0.foodItemID == replaced[index].foodItemID }) {
                replaced[index].id = previous.id
                replaced[index].barcode = previous.barcode
            }
        }
        entries.removeAll { $0.groupID == groupID }
        entries.append(contentsOf: replaced)
        persistActive()
    }

    /// Logs a list of catalog foods at once (e.g. a recipe with some foods swapped), tagged with
    /// a shared group named `groupName`.
    /// `recipeID`: the recipe they were logged from, so the day can reopen its amounts and a
    /// rename follows.
    func logFoods(_ items: [RecipeItem], groupName: String, mealType: MealType, date: Date, recipeID: UUID? = nil) {
        let newEntries = linkedEntries(for: items, groupID: UUID(), groupName: groupName, mealType: mealType,
                                       date: date, recipeID: recipeID)
        guard !newEntries.isEmpty else { return }
        entries.append(contentsOf: newEntries)
        persistActive()
    }

    /// One entry per catalog food of `items`, linked to its food (and recipe).
    private func linkedEntries(for items: [RecipeItem], groupID: UUID, groupName: String, mealType: MealType,
                               date: Date, recipeID: UUID?) -> [FoodEntry] {
        items.compactMap { recipeItem in
            guard let food = foodItems.first(where: { $0.id == recipeItem.foodItemID }) else { return nil }
            var entry = FoodEntry(
                name: food.name,
                nutrition: food.nutrition(quantity: recipeItem.quantity),
                mealType: mealType,
                date: date,
                barcode: food.barcodes.first,
                groupID: groupID,
                groupName: groupName
            )
            entry.foodItemID = food.id
            entry.quantity = recipeItem.quantity
            entry.recipeID = recipeID
            return entry
        }
    }

    /// After `food` changed: every diary entry logged from it gets its current values (and name),
    /// so the day — and the dashboard — never show a stale version of the same food.
    private func refreshEntries(linkedTo food: FoodItem) {
        for index in entries.indices where entries[index].foodItemID == food.id {
            guard let quantity = entries[index].quantity else { continue }
            let old = entries[index]
            var updated = FoodEntry(name: food.name, nutrition: food.nutrition(quantity: quantity),
                                    mealType: old.mealType, date: old.date, barcode: old.barcode,
                                    groupID: old.groupID, groupName: old.groupName)
            updated.id = old.id
            updated.foodItemID = old.foodItemID
            updated.quantity = quantity
            updated.recipeID = old.recipeID
            entries[index] = updated
        }
    }

    /// After `recipe` changed: what was logged from it keeps its amounts (they're what was eaten,
    /// and each ingredient already follows its food) — only the group name follows a rename.
    private func renameEntries(loggedFrom recipe: Recipe) {
        for index in entries.indices where entries[index].recipeID == recipe.id && entries[index].groupName != recipe.name {
            entries[index].groupName = recipe.name
        }
    }

    /// Adds a batch of pre-built entries at once (e.g. from AI-generated JSON pasted into the
    /// app), tagged with the given group so they're recognizable as belonging together, the same
    /// way a logged recipe's entries are.
    func addImportedEntries(_ newEntries: [FoodEntry], groupName: String) {
        guard !newEntries.isEmpty else { return }
        var entriesToAdd = newEntries
        let trimmedGroupName = groupName.trimmingCharacters(in: .whitespaces)
        if !trimmedGroupName.isEmpty {
            let groupID = UUID()
            for index in entriesToAdd.indices {
                entriesToAdd[index].groupID = groupID
                entriesToAdd[index].groupName = trimmedGroupName
            }
        }
        entries.append(contentsOf: entriesToAdd)
        persistActive()
    }

    // MARK: - Food catalog

    func addFoodItem(_ item: FoodItem) {
        foodItems.append(item)
        persistActive()
    }

    /// The catalog food an AI-imported food stands for: an existing one with its barcode or the
    /// same name (case-insensitive), so the same ingredient showing up in several imports isn't duplicated,
    /// or else a new one, added to the catalog.
    @discardableResult
    func catalogFood(for payload: FoodImportPayload) -> FoodItem {
        if let barcode = payload.resolvedBarcode, let existing = foodItem(forBarcode: barcode) {
            return existing
        }
        if let existing = existingCatalogFood(named: payload.name) {
            return existing
        }
        var newItem = payload.makeFoodItem()
        newItem.categoryID = foodCategory(named: payload.category)?.id
        if let barcode = payload.resolvedBarcode, foodItem(forBarcode: barcode) == nil {
            newItem.barcodes = [barcode]
        }
        addFoodItem(newItem)
        return newItem
    }

    /// The food category called `name` (ignoring case and accents), if there is one.
    func foodCategory(named name: String?) -> FoodCategory? {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let wanted = SearchMatch.normalized(name).trimmingCharacters(in: .whitespaces)
        return foodCategories.first { SearchMatch.normalized($0.name).trimmingCharacters(in: .whitespaces) == wanted }
    }

    /// The ingredients of an AI-imported recipe (`recipeItem(for:)` each); an ingredient the AI
    /// listed twice becomes one, with the amounts added up.
    func recipeItems(for payloads: [RecipeItemImportPayload]) -> [RecipeItem] {
        var merged: [RecipeItem] = []
        for item in payloads.map(recipeItem(for:)) {
            if let index = merged.firstIndex(where: { $0.foodItemID == item.foodItemID }) {
                merged[index].quantity += item.quantity
            } else {
                merged.append(item)
            }
        }
        return merged
    }

    /// One ingredient of an AI-imported recipe, backed by `catalogFood(for:)`. The AI gives the
    /// amount for one portion in g / ml / units (`amount`; older answers: doses of *its*
    /// `doseSize`). It's stored in doses of the catalog food actually used — converted when an
    /// existing food with a different dose is reused (e.g. 150 g of rice vs. a 100 g dose), as long
    /// as both share a base unit (g, ml or units).
    func recipeItem(for payload: RecipeItemImportPayload) -> RecipeItem {
        let importedDose = payload.food.makeFoodItem().baseDoseAmount
        let quantity: Double
        if let amount = payload.amount, amount > 0, importedDose > 0 {
            quantity = amount / importedDose
        } else {
            quantity = payload.quantity ?? 1
        }
        guard let existing = existingCatalogFood(named: payload.food.name) else {
            return RecipeItem(foodItemID: catalogFood(for: payload.food).id, quantity: quantity)
        }
        let imported = payload.food.makeFoodItem()
        guard existing.unit.baseUnit == imported.unit.baseUnit, existing.baseDoseAmount > 0 else {
            return RecipeItem(foodItemID: existing.id, quantity: quantity)
        }
        let converted = quantity * imported.baseDoseAmount / existing.baseDoseAmount
        // Enough decimals that adding up two lines of the same food keeps the grams exact.
        return RecipeItem(foodItemID: existing.id, quantity: (converted * 10_000).rounded() / 10_000)
    }

    private func existingCatalogFood(named name: String) -> FoodItem? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return foodItems.first { $0.name.matchesImportedName(trimmed) }
    }

    func updateFoodItem(_ item: FoodItem) {
        guard let index = foodItems.firstIndex(where: { $0.id == item.id }) else { return }
        foodItems[index] = item
        refreshEntries(linkedTo: item)
        refreshPreparations(of: item)
        persistActive()
    }

    /// A preparation of a raw food, added or changed: its label is (re)worked out from the raw food.
    @discardableResult
    func savePreparation(of base: FoodItem, method: FoodPreparation, change: Double, name: String,
                         categoryID: UUID?, existing: FoodItem?) -> FoodItem {
        var item = base.prepared(method, change: change, updating: existing)
        item.name = name
        item.categoryID = categoryID
        if let index = foodItems.firstIndex(where: { $0.id == item.id }) {
            foodItems[index] = item
            refreshEntries(linkedTo: item)
        } else {
            foodItems.append(item)
        }
        persistActive()
        return item
    }

    /// A raw food changed: its preparations' labels follow it (and what was logged from them).
    private func refreshPreparations(of base: FoodItem) {
        for index in foodItems.indices where foodItems[index].baseFoodID == base.id {
            let current = foodItems[index]
            foodItems[index] = base.prepared(current.preparation ?? .boiled, change: current.cookingWeightChange ?? 0, updating: current)
            refreshEntries(linkedTo: foodItems[index])
        }
    }

    func deleteFoodItem(_ item: FoodItem) {
        deleteFoodItems(withIDs: [item.id])
    }

    /// Deletes several foods at once (and takes them out of every recipe), in one save.
    func deleteFoodItems(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        foodItems.removeAll { ids.contains($0.id) }
        for index in recipes.indices {
            recipes[index].items.removeAll { ids.contains($0.foodItemID) }
        }
        pantryLots.removeAll { ids.contains($0.foodItemID) }
        // Preparations of a removed food keep their values, as foods of their own.
        for index in foodItems.indices where foodItems[index].baseFoodID.map(ids.contains) == true {
            foodItems[index].baseFoodID = nil
        }
        persistActive()
    }

    // MARK: - Food categories

    func foodCategory(withID id: UUID?) -> FoodCategory? {
        guard let id else { return nil }
        return foodCategories.first { $0.id == id }
    }

    func addFoodCategory(_ category: FoodCategory) {
        foodCategories.append(category)
        persistActive()
    }

    func renameFoodCategory(_ category: FoodCategory, to name: String) {
        guard let index = foodCategories.firstIndex(where: { $0.id == category.id }) else { return }
        foodCategories[index].name = name
        persistActive()
    }

    /// Moves a category under another one (a subcategory) or back to the top (`nil`).
    func setParent(of category: FoodCategory, to parentID: UUID?) {
        guard let index = foodCategories.firstIndex(where: { $0.id == category.id }), parentID != category.id else { return }
        foodCategories[index].parentID = parentID
        // Two levels only: its own subcategories move up with it.
        if parentID != nil {
            for child in foodCategories.indices where foodCategories[child].parentID == category.id {
                foodCategories[child].parentID = parentID
            }
        }
        persistActive()
    }

    /// Removes a category. Its foods go to its parent category (uncategorised for a top-level one)
    /// and its subcategories become top-level categories.
    func deleteFoodCategory(_ category: FoodCategory) {
        foodCategories.removeAll { $0.id == category.id }
        for index in foodItems.indices where foodItems[index].categoryID == category.id {
            foodItems[index].categoryID = category.parentID
        }
        for index in foodCategories.indices where foodCategories[index].parentID == category.id {
            foodCategories[index].parentID = nil
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
        renameEntries(loggedFrom: recipe)
        persistActive()
    }

    func deleteRecipe(_ recipe: Recipe) {
        deleteRecipes(withIDs: [recipe.id])
    }

    /// Deletes several recipes at once, in one save.
    func deleteRecipes(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        recipes.removeAll { ids.contains($0.id) }
        for index in mealPreps.indices {
            mealPreps[index].items.removeAll { ids.contains($0.recipeID) }
        }
        persistActive()
    }

    func toggleFavorite(_ recipe: Recipe) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[index].isFavorite.toggle()
        persistActive()
    }

    // MARK: - Meal plan

    /// The meal plan in effect on `date` (highest priority among those covering it).
    func mealPlan(on date: Date) -> MealPlan? {
        mealPlans.inEffect(on: date)
    }

    /// Links one option of a meal plan to `recipeID` (or unlinks it, with `nil`).
    func linkMealPlanOption(_ optionID: UUID, inMeal mealID: UUID, ofPlan planID: UUID, toRecipe recipeID: UUID?) {
        guard let planIndex = mealPlans.firstIndex(where: { $0.id == planID }),
              let mealIndex = mealPlans[planIndex].meals.firstIndex(where: { $0.id == mealID }),
              let optionIndex = mealPlans[planIndex].meals[mealIndex].options.firstIndex(where: { $0.id == optionID }) else { return }
        mealPlans[planIndex].meals[mealIndex].options[optionIndex].recipeID = recipeID
        persistActive()
    }

    /// Updates a meal plan's name, dates and priority (its meals stay as they are).
    func updateMealPlanSchedule(_ planID: UUID, name: String, startsOn: Date, endsOn: Date?, priority: Int) {
        guard let index = mealPlans.firstIndex(where: { $0.id == planID }) else { return }
        mealPlans[index].name = name
        mealPlans[index].startsOn = startsOn
        mealPlans[index].endsOn = endsOn
        mealPlans[index].priority = priority
        persistActive()
    }

    /// Removes a meal plan. Its recipes and foods stay in the catalog.
    func deleteMealPlan(_ plan: MealPlan) {
        mealPlans.removeAll { $0.id == plan.id }
        persistActive()
    }

    /// Writes `plan`, plus every recipe it links to and every food those recipes use, to a
    /// temporary JSON file and returns its URL, ready to be handed to a file mover.
    func exportMealPlanURL(_ plan: MealPlan) throws -> URL {
        let recipeIDs = Set(plan.meals.flatMap(\.options).compactMap(\.recipeID))
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
            plan: plan,
            recipes: linkedRecipes,
            foodItems: linkedFoods
        )
        return try writeTempSnapshot(data: encoder.encode(file), name: "PlanoAlimentar")
    }

    /// Reads a meal plan file without applying it, so the caller can ask before replacing a plan.
    func readMealPlanFile(at url: URL) throws -> MealPlanFile {
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
        return file
    }

    /// Adds the plan in `file`, or replaces the one with the same ID. Recipes and foods in the
    /// file are added to the catalog unless one with the same ID already exists, in which case the
    /// existing one is kept (so re-importing a plan never overwrites edits made in the app).
    func importMealPlan(_ file: MealPlanFile) {
        let existingFoodIDs = Set(foodItems.map(\.id))
        foodItems.append(contentsOf: file.foodItems.filter { !existingFoodIDs.contains($0.id) })
        let existingRecipeIDs = Set(recipes.map(\.id))
        recipes.append(contentsOf: file.recipes.filter { !existingRecipeIDs.contains($0.id) })
        if let index = mealPlans.firstIndex(where: { $0.id == file.plan.id }) {
            mealPlans[index] = file.plan
        } else {
            mealPlans.append(file.plan)
        }
        persistActive()
    }

    // MARK: - Nutrition plans

    /// The plan in effect on `date`: the most recent live plan that had already started by then.
    func nutritionPlan(on date: Date) -> NutritionPlan? {
        nutritionPlans.plan(on: date)
    }

    /// Creates or updates a plan (matched by `id`).
    func saveNutritionPlan(_ plan: NutritionPlan) {
        var plan = plan
        plan.updatedAt = Date()
        if let index = nutritionPlans.firstIndex(where: { $0.id == plan.id }) {
            nutritionPlans[index] = plan
        } else {
            nutritionPlans.append(plan)
        }
        persistActive()
    }

    /// Soft-deletes a plan (kept, flagged, so it can still be looked back on): days it covered
    /// fall back to whichever plan applied before it.
    func deleteNutritionPlan(_ plan: NutritionPlan) {
        guard let index = nutritionPlans.firstIndex(where: { $0.id == plan.id }) else { return }
        nutritionPlans[index].deletedAt = Date()
        nutritionPlans[index].updatedAt = Date()
        persistActive()
    }

    /// Applies plans pulled from the platform (created or edited on the dashboard), replacing the
    /// local ones with the same id as they are — `updatedAt` included, so the sync doesn't treat
    /// them as local edits and send them back.
    func applyRemoteNutritionPlans(_ plans: [NutritionPlan]) {
        guard !plans.isEmpty else { return }
        for plan in plans {
            if let index = nutritionPlans.firstIndex(where: { $0.id == plan.id }) {
                nutritionPlans[index] = plan
            } else {
                nutritionPlans.append(plan)
            }
        }
        persistActive(countingChange: false)
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

    // MARK: - Food stock (pantry)

    func addPantryLocation(_ location: PantryLocation) {
        pantryLocations.append(location)
        persistActive()
    }

    func renamePantryLocation(_ location: PantryLocation, to name: String) {
        guard let index = pantryLocations.firstIndex(where: { $0.id == location.id }) else { return }
        pantryLocations[index].name = name
        persistActive()
    }

    /// Removes the location with everything stocked there; meal preps cooked from it fall back to
    /// every location.
    func deletePantryLocation(_ location: PantryLocation) {
        pantryLocations.removeAll { $0.id == location.id }
        pantryLots.removeAll { $0.locationID == location.id }
        for index in mealPreps.indices where mealPreps[index].locationID == location.id {
            mealPreps[index].locationID = nil
        }
        persistActive()
    }

    /// Stock coming in (e.g. after shopping), in one save.
    func addPantryLots(_ lots: [PantryLot]) {
        guard !lots.isEmpty else { return }
        pantryLots.append(contentsOf: lots)
        persistActive()
    }

    /// A lot changed by hand (amount, location, expiry); at 0 or less it's gone.
    func updatePantryLot(_ lot: PantryLot) {
        guard let index = pantryLots.firstIndex(where: { $0.id == lot.id }) else { return }
        if lot.remaining <= 0 {
            pantryLots.remove(at: index)
        } else {
            pantryLots[index] = lot
        }
        persistActive()
    }

    func deletePantryLots(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pantryLots.removeAll { ids.contains($0.id) }
        persistActive()
    }

    /// Takes `amounts` (base units by food) out of the stock at `locationID` (`nil` = anywhere),
    /// the lots that expire first going first; emptied lots disappear. Expired lots aren't used.
    /// Returns what couldn't be taken (not enough in stock).
    @discardableResult
    func takeFromPantry(_ amounts: [UUID: Double], locationID: UUID?) -> [UUID: Double] {
        let missing = consumePantry(amounts, locationID: locationID)
        persistActive()
        return missing
    }

    private func consumePantry(_ amounts: [UUID: Double], locationID: UUID?) -> [UUID: Double] {
        var missing: [UUID: Double] = [:]
        let today = Calendar.current.startOfDay(for: .now)
        for (foodID, amount) in amounts where amount > 0 {
            var left = amount
            let order = pantryLots.indices
                .filter { index in
                    let lot = pantryLots[index]
                    return lot.foodItemID == foodID && (locationID == nil || lot.locationID == locationID)
                        && (lot.expiresOn.map { $0 >= today } ?? true)
                }
                .sorted { (pantryLots[$0].expiresOn ?? .distantFuture) < (pantryLots[$1].expiresOn ?? .distantFuture) }
            for index in order where left > 0 {
                let taken = min(pantryLots[index].remaining, left)
                pantryLots[index].remaining -= taken
                left -= taken
            }
            if left > 0.0001 { missing[foodID] = left }
        }
        pantryLots.removeAll { $0.remaining <= 0.0001 }
        return missing
    }

    // MARK: - Cooking yields

    /// The reference table starts with `CookingYield.defaults` (also after a wipe, or on an
    /// account restored before it existed).
    func seedCookingYieldsIfEmpty() {
        if cookingYields.isEmpty {
            cookingYields = CookingYield.defaults
            UserDefaults.standard.set(true, forKey: Self.hasSeededCookingMethodsKey)
            persistActive()
            return
        }
        // Tables made before values per way of cooking existed get those, once.
        guard !UserDefaults.standard.bool(forKey: Self.hasSeededCookingMethodsKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasSeededCookingMethodsKey)
        guard !cookingYields.contains(where: { $0.method != nil }) else { return }
        let existing = Set(cookingYields.map(Self.yieldKey))
        cookingYields += CookingYield.defaults.filter { $0.method != nil && !existing.contains(Self.yieldKey($0)) }
        persistActive()
    }

    private static let hasSeededCookingMethodsKey = "CalorieBuddy.hasSeededCookingMethods"

    func saveCookingYield(_ yield: CookingYield) {
        if let index = cookingYields.firstIndex(where: { $0.id == yield.id }) {
            cookingYields[index] = yield
        } else {
            cookingYields.append(yield)
        }
        persistActive()
    }

    func deleteCookingYields(withIDs ids: Set<UUID>) {
        cookingYields.removeAll { ids.contains($0.id) }
        persistActive()
    }

    /// Puts back the reference values (keeps the ones the user added under other names).
    func resetCookingYields() {
        let defaultKeys = Set(CookingYield.defaults.map(Self.yieldKey))
        cookingYields = CookingYield.defaults + cookingYields.filter { !defaultKeys.contains(Self.yieldKey($0)) }
        persistActive()
    }

    nonisolated private static func yieldKey(_ yield: CookingYield) -> String {
        SearchMatch.normalized(yield.name) + "|" + (yield.method?.rawValue ?? "")
    }

    // MARK: - Meal prep

    func saveMealPrep(_ prep: MealPrep) {
        if let index = mealPreps.firstIndex(where: { $0.id == prep.id }) {
            mealPreps[index] = prep
        } else {
            mealPreps.append(prep)
        }
        persistActive()
    }

    func deleteMealPrep(_ prep: MealPrep) {
        mealPreps.removeAll { $0.id == prep.id }
        persistActive()
    }

    /// Marks it as cooked and takes the raw ingredients out of its stock (what's there of them).
    /// Returns what was missing from the stock.
    @discardableResult
    func markMealPrepCooked(_ prep: MealPrep) -> [UUID: Double] {
        var cooked = prep
        cooked.cookedAt = .now
        if let index = mealPreps.firstIndex(where: { $0.id == prep.id }) {
            mealPreps[index] = cooked
        } else {
            mealPreps.append(cooked)
        }
        let needed = mealPrepPlan(for: prep).requirements.reduce(into: [UUID: Double]()) { $0[$1.food.id] = $1.rawAmount }
        let missing = consumePantry(needed, locationID: prep.locationID)
        persistActive()
        return missing
    }

    // MARK: - Load / persist active database

    private func loadActive() {
        guard let data = try? Data(contentsOf: activeURL),
              let database = try? decoder.decode(AppDatabase.self, from: data) else { return }
        entries = database.entries
        settings = database.settings
        foodItems = database.foodItems
        foodCategories = database.foodCategories
        recipes = database.recipes
        stores = database.stores
        supplementCategories = database.supplementCategories
        supplements = database.supplements
        supplementLogs = database.supplementLogs
        stockLocations = database.stockLocations
        mealPlans = database.mealPlans
        nutritionPlans = database.nutritionPlans
        bodyMeasurements = database.bodyMeasurements
        progressPhotos = database.progressPhotos
        pantryLocations = database.pantryLocations
        pantryLots = database.pantryLots
        cookingYields = database.cookingYields
        mealPreps = database.mealPreps
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
            mealPlans: mealPlans,
            nutritionPlans: nutritionPlans,
            bodyMeasurements: bodyMeasurements,
            progressPhotos: progressPhotos,
            foodCategories: foodCategories,
            pantryLocations: pantryLocations,
            pantryLots: pantryLots,
            cookingYields: cookingYields,
            mealPreps: mealPreps
        )
    }

    /// `countingChange: false` for data that came from elsewhere (the platform, a file, the
    /// backup) or a wipe: only the user's own edits should trigger a sync.
    private func persistActive(countingChange: Bool = true) {
        if countingChange { localChangeCount += 1 }
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

    // MARK: - Platform sync

    /// The whole database as a value, e.g. for syncing it to the platform.
    func databaseSnapshot() -> AppDatabase {
        currentDatabase()
    }

    /// Replaces the active database with `database` (e.g. restored from the platform). The database
    /// that was active until now is preserved as the backup first, like importing a file.
    func replaceDatabase(with database: AppDatabase) {
        adoptAsActive(database)
    }

    /// Takes in records changed elsewhere (the dashboard), already merged into `database` by the
    /// platform sync. Unlike `replaceDatabase`, this is an ordinary edit: the backup isn't touched.
    func applyRemoteChanges(_ database: AppDatabase) {
        entries = database.entries
        settings = database.settings
        foodItems = database.foodItems
        foodCategories = database.foodCategories
        recipes = database.recipes
        stores = database.stores
        supplementCategories = database.supplementCategories
        supplements = database.supplements
        supplementLogs = database.supplementLogs
        stockLocations = database.stockLocations
        mealPlans = database.mealPlans
        bodyMeasurements = database.bodyMeasurements
        progressPhotos = database.progressPhotos
        pantryLocations = database.pantryLocations
        pantryLots = database.pantryLots
        cookingYields = database.cookingYields
        mealPreps = database.mealPreps
        persistActive(countingChange: false)
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
        foodCategories = database.foodCategories
        recipes = database.recipes
        stores = database.stores
        supplementCategories = database.supplementCategories
        supplements = database.supplements
        supplementLogs = database.supplementLogs
        stockLocations = database.stockLocations
        mealPlans = database.mealPlans
        nutritionPlans = database.nutritionPlans
        bodyMeasurements = database.bodyMeasurements
        progressPhotos = database.progressPhotos
        pantryLocations = database.pantryLocations
        pantryLots = database.pantryLots
        cookingYields = database.cookingYields
        mealPreps = database.mealPreps
        linkUnlinkedDiaryEntries()
        moveMealPlansToMealStages()
        persistActive(countingChange: false)
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
        foodCategories = restoredDatabase.foodCategories
        recipes = restoredDatabase.recipes
        stores = restoredDatabase.stores
        supplementCategories = restoredDatabase.supplementCategories
        supplements = restoredDatabase.supplements
        supplementLogs = restoredDatabase.supplementLogs
        stockLocations = restoredDatabase.stockLocations
        mealPlans = restoredDatabase.mealPlans
        nutritionPlans = restoredDatabase.nutritionPlans
        bodyMeasurements = restoredDatabase.bodyMeasurements
        progressPhotos = restoredDatabase.progressPhotos
        pantryLocations = restoredDatabase.pantryLocations
        pantryLots = restoredDatabase.pantryLots
        cookingYields = restoredDatabase.cookingYields
        mealPreps = restoredDatabase.mealPreps
        persistActive(countingChange: false)
        refreshBackupTimestamp()
    }

    // MARK: - Delete everything

    /// Whether this iPhone holds records of its own (not just settings, categories or the
    /// initial nutrition plan) — signing in sends them to the platform before downloading.
    var hasUserData: Bool {
        !entries.isEmpty || !foodItems.isEmpty || !recipes.isEmpty || !supplements.isEmpty
            || !supplementLogs.isEmpty || !mealPlans.isEmpty || !bodyMeasurements.isEmpty || !progressPhotos.isEmpty
            || !pantryLots.isEmpty || !mealPreps.isEmpty
    }

    /// Wipes every piece of data this app stores locally — entries, catalog, recipes, meal plan,
    /// stores, supplements and settings — including the on-disk backup. Does not touch Apple Health.
    func deleteEverything() {
        entries = []
        foodItems = []
        foodCategories = []
        recipes = []
        stores = []
        supplementCategories = []
        supplements = []
        supplementLogs = []
        stockLocations = []
        mealPlans = []
        nutritionPlans = []
        bodyMeasurements = []
        progressPhotos = []
        pantryLocations = []
        pantryLots = []
        cookingYields = []
        mealPreps = []
        settings = .default
        try? fileManager.removeItem(at: backupURL)
        PhotoStore.deleteAll()
        backupTimestamp = nil
        persistActive(countingChange: false)
    }
}

private extension String {
    /// Whether this catalog name and one written by an AI are the same thing — ignoring case and
    /// accents, since an AI may well write "Gel Energetico" for the user's "Gel Energético".
    func matchesImportedName(_ other: String) -> Bool {
        compare(other, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
