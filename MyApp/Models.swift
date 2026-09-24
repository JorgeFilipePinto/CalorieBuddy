import Foundation

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: return "Pequeno-almoço"
        case .lunch: return "Almoço"
        case .dinner: return "Jantar"
        case .snack: return "Snack"
        }
    }

    var symbolName: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "carrot"
        }
    }

    /// A reasonable default meal for the time of day, used to pre-select the meal when
    /// logging an entry so the user usually doesn't have to change it.
    static func suggested(for date: Date) -> MealType {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<19: return .snack
        default: return .dinner
        }
    }
}

struct FoodEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var calories: Int
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var mealType: MealType
    var date: Date
    /// Barcode this entry was logged from, if any.
    var barcode: String? = nil
    /// Shared by every entry logged at once from the same recipe, so they can be recognized
    /// as belonging together (e.g. shown with the recipe's name).
    var groupID: UUID? = nil
    var groupName: String? = nil
}

/// A place where a food item can be bought, and at what price.
struct Store: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
}

/// A unit a food can be measured or priced in. `kilogram`/`liter` are just convenient input
/// units for `gram`/`milliliter` — everything is converted to a common base unit (grams,
/// millilitres, or a plain count) for any actual math, via `baseUnit`/`baseMultiplier`.
enum MeasurementUnit: String, Codable, CaseIterable, Identifiable {
    case gram, kilogram, milliliter, liter, unit

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .gram: return "g"
        case .kilogram: return "kg"
        case .milliliter: return "ml"
        case .liter: return "L"
        case .unit: return "unidade"
        }
    }

    /// The canonical unit this one is expressed in for storage/math: grams for weight,
    /// millilitres for volume, or a plain count.
    var baseUnit: MeasurementUnit {
        switch self {
        case .gram, .kilogram: return .gram
        case .milliliter, .liter: return .milliliter
        case .unit: return .unit
        }
    }

    /// How many `baseUnit`s one of this unit is worth (e.g. 1 kg = 1000 g).
    var baseMultiplier: Double {
        switch self {
        case .kilogram, .liter: return 1000
        case .gram, .milliliter, .unit: return 1
        }
    }

    /// Units that make sense for pricing/measuring a food whose own unit is `unit` — e.g. a
    /// food measured in grams can reasonably be priced per gram or per kilogram.
    static func compatible(with unit: MeasurementUnit) -> [MeasurementUnit] {
        switch unit.baseUnit {
        case .gram: return [.gram, .kilogram]
        case .milliliter: return [.milliliter, .liter]
        default: return [.unit]
        }
    }
}

/// Whether a food's nutrition values are given per 100 (g/ml) — the usual nutrition-label
/// convention — or per one dose/serving as defined by the food itself.
enum NutritionBasis: String, Codable, CaseIterable, Identifiable {
    case per100, perDose

    var id: String { rawValue }

    var label: String {
        switch self {
        case .per100: return "Por 100"
        case .perDose: return "Por dose"
        }
    }
}

/// A single named amount of a mineral or vitamin (e.g. "Cálcio", 120, "mg").
struct NutrientValue: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var amount: Double
    var unit: String
}

/// The price of a food item at a particular store, for a given package size. `price` is what
/// was actually paid; when it was a promotional price, `regularPrice` keeps the normal
/// (non-promo) price for reference.
///
/// Uses a custom decoder so prices saved before `packageSize`/`packageUnit`/`isPromotion`/
/// `regularPrice` existed still import cleanly.
struct PriceEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var storeID: UUID
    var price: Double
    /// The package this price is for, e.g. 1 kg for a 1 kg bag — not necessarily the food's
    /// own dose size, so the cost of a dose can be recalculated as a fraction of the package.
    var packageSize: Double
    var packageUnit: MeasurementUnit
    var isPromotion: Bool
    var regularPrice: Double?

    init(
        id: UUID = UUID(),
        storeID: UUID,
        price: Double,
        packageSize: Double = 1,
        packageUnit: MeasurementUnit = .unit,
        isPromotion: Bool = false,
        regularPrice: Double? = nil
    ) {
        self.id = id
        self.storeID = storeID
        self.price = price
        self.packageSize = packageSize
        self.packageUnit = packageUnit
        self.isPromotion = isPromotion
        self.regularPrice = regularPrice
    }

    private enum CodingKeys: String, CodingKey {
        case id, storeID, price, packageSize, packageUnit, isPromotion, regularPrice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        storeID = try container.decode(UUID.self, forKey: .storeID)
        price = try container.decode(Double.self, forKey: .price)
        packageSize = try container.decodeIfPresent(Double.self, forKey: .packageSize) ?? 1
        packageUnit = try container.decodeIfPresent(MeasurementUnit.self, forKey: .packageUnit) ?? .unit
        isPromotion = try container.decodeIfPresent(Bool.self, forKey: .isPromotion) ?? false
        regularPrice = try container.decodeIfPresent(Double.self, forKey: .regularPrice)
    }
}

/// Something priced by the dose, in a given `unit` — shared by `FoodItem` and `Supplement` so
/// "cost of N doses" is computed identically for both, correctly handling a dose and its
/// package price being given in different (but compatible) units.
protocol Doseable {
    var unit: MeasurementUnit { get }
    var doseSize: Double { get }
    var prices: [PriceEntry] { get }
}

extension Doseable {
    /// The cheapest known price, across every store this has been priced at.
    var cheapestPrice: PriceEntry? {
        prices.min { $0.price < $1.price }
    }

    /// Cost of `quantity` doses, using the cheapest known price.
    func cost(quantity: Double) -> Double? {
        guard let cheapest = cheapestPrice else { return nil }
        let doseBaseAmount = doseSize * unit.baseMultiplier * quantity
        let packageBaseAmount = cheapest.packageSize * cheapest.packageUnit.baseMultiplier
        guard packageBaseAmount > 0 else { return nil }
        return (cheapest.price / packageBaseAmount) * doseBaseAmount
    }

    /// A short label for one dose, e.g. "30 g" or "1 unidade".
    var doseLabel: String {
        let trimmed = doseSize.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(doseSize))
            : String(format: "%.1f", doseSize)
        return "\(trimmed) \(unit.shortLabel)"
    }
}

/// Something that can be favorited and sorted by name or by when it was added — shared by
/// `FoodItem`, `Recipe` and `Supplement` so their list screens filter/sort identically.
protocol Favoritable {
    var name: String { get }
    var isFavorite: Bool { get set }
    var createdAt: Date { get }
}

/// How a list of `Favoritable` items can be sorted.
enum ItemSortOrder: String, CaseIterable, Identifiable {
    case dateAdded, name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateAdded: return "Data de Inserção"
        case .name: return "Nome"
        }
    }
}

extension Array where Element: Favoritable {
    /// Keeps items whose name *contains* `searchText` (not an exact match), case-insensitively,
    /// then sorts by the given order.
    func filteredAndSorted(searchText: String, order: ItemSortOrder) -> [Element] {
        let filtered = searchText.isEmpty ? self : filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        switch order {
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .dateAdded:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        }
    }
}

/// A reusable food definition (e.g. from the catalog or a barcode scan) that can be logged
/// directly, or combined with others into a `Recipe`.
///
/// Uses a custom decoder so that catalog items saved before `unit`/`doseSize`/`nutritionBasis`/
/// `minerals`/`vitamins`/`isFavorite`/`createdAt` existed still import cleanly, with sensible
/// defaults.
struct FoodItem: Identifiable, Codable, Hashable, Doseable, Favoritable {
    var id: UUID
    var name: String
    var brand: String?
    /// The unit this food is measured/bought in.
    var unit: MeasurementUnit
    /// Size of one dose/serving, in `unit`.
    var doseSize: Double
    /// Whether `calories`/`protein`/`carbs`/`fat` below are per 100 (g/ml) or per one dose.
    var nutritionBasis: NutritionBasis
    var calories: Int
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var minerals: [NutrientValue]
    var vitamins: [NutrientValue]
    /// Every barcode that identifies this item — lets near-identical variants of the same
    /// product (different pack sizes, regional printings, minor recipe tweaks) share one
    /// catalog entry instead of being duplicated.
    var barcodes: [String]
    /// Price of this item at each store it's been priced at.
    var prices: [PriceEntry]
    var isFavorite: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        unit: MeasurementUnit = .gram,
        doseSize: Double = 100,
        nutritionBasis: NutritionBasis = .per100,
        calories: Int,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        minerals: [NutrientValue] = [],
        vitamins: [NutrientValue] = [],
        barcodes: [String] = [],
        prices: [PriceEntry] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.unit = unit
        self.doseSize = doseSize
        self.nutritionBasis = nutritionBasis
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.minerals = minerals
        self.vitamins = vitamins
        self.barcodes = barcodes
        self.prices = prices
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, brand, unit, doseSize, nutritionBasis, calories, protein, carbs, fat,
             minerals, vitamins, barcodes, prices, isFavorite, createdAt
    }

    /// Only for reading the old singular `barcode` field from databases saved before this was
    /// a list — never encoded.
    private enum LegacyCodingKeys: String, CodingKey {
        case barcode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        unit = try container.decodeIfPresent(MeasurementUnit.self, forKey: .unit) ?? .gram
        doseSize = try container.decodeIfPresent(Double.self, forKey: .doseSize) ?? 100
        nutritionBasis = try container.decodeIfPresent(NutritionBasis.self, forKey: .nutritionBasis) ?? .perDose
        calories = try container.decode(Int.self, forKey: .calories)
        protein = try container.decodeIfPresent(Double.self, forKey: .protein)
        carbs = try container.decodeIfPresent(Double.self, forKey: .carbs)
        fat = try container.decodeIfPresent(Double.self, forKey: .fat)
        minerals = try container.decodeIfPresent([NutrientValue].self, forKey: .minerals) ?? []
        vitamins = try container.decodeIfPresent([NutrientValue].self, forKey: .vitamins) ?? []
        // `barcodes` (plural, current) takes priority; fall back to the old singular `barcode`.
        if let list = try container.decodeIfPresent([String].self, forKey: .barcodes) {
            barcodes = list
        } else if let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self),
                  let single = try legacyContainer.decodeIfPresent(String.self, forKey: .barcode) {
            barcodes = [single]
        } else {
            barcodes = []
        }
        prices = try container.decodeIfPresent([PriceEntry].self, forKey: .prices) ?? []
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
    }

    /// Multiplier turning the stored nutrition values into "nutrition for one dose".
    private var nutritionScale: Double {
        switch nutritionBasis {
        case .perDose: return 1
        case .per100: return (doseSize * unit.baseMultiplier) / 100
        }
    }

    func scaledCalories(quantity: Double) -> Int {
        Int((Double(calories) * nutritionScale * quantity).rounded())
    }

    func scaledProtein(quantity: Double) -> Double? { protein.map { $0 * nutritionScale * quantity } }
    func scaledCarbs(quantity: Double) -> Double? { carbs.map { $0 * nutritionScale * quantity } }
    func scaledFat(quantity: Double) -> Double? { fat.map { $0 * nutritionScale * quantity } }
}

/// The nutrient two foods are matched on when one is swapped for an "equivalent" other.
enum Macro: String, CaseIterable {
    case protein, carbs, fat, calories

    var displayName: String {
        switch self {
        case .protein: return "proteína"
        case .carbs: return "hidratos de carbono"
        case .fat: return "gordura"
        case .calories: return "calorias"
        }
    }

    var unitLabel: String { self == .calories ? "kcal" : "g" }
}

extension FoodItem {
    /// Amount of `macro` in `quantity` doses, or `nil` if the food doesn't state it.
    func amount(of macro: Macro, quantity: Double) -> Double? {
        switch macro {
        case .protein: return scaledProtein(quantity: quantity)
        case .carbs: return scaledCarbs(quantity: quantity)
        case .fat: return scaledFat(quantity: quantity)
        case .calories: return Double(calories) * nutritionScale * quantity
        }
    }

    /// The macro that contributes most of this food's energy (4 kcal/g protein and carbs,
    /// 9 kcal/g fat) — what defines which foods count as its equivalents. Falls back to
    /// calories for foods without macros.
    var dominantMacro: Macro {
        let energy: [(Macro, Double)] = [
            (.protein, (protein ?? 0) * 4),
            (.carbs, (carbs ?? 0) * 4),
            (.fat, (fat ?? 0) * 9)
        ]
        guard let best = energy.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return .calories }
        return best.0
    }

    /// Size of one dose in the base unit (g, ml or units).
    var baseDoseAmount: Double { doseSize * unit.baseMultiplier }

    /// How many doses of this food provide the same amount of `macro` as `quantity` doses of
    /// `other`, rounded to a practical amount (5 g/ml steps, or half units). `nil` when this food
    /// has none of that macro.
    func equivalentQuantity(to other: FoodItem, quantity: Double, matching macro: Macro) -> Double? {
        guard let target = other.amount(of: macro, quantity: quantity),
              let perDose = amount(of: macro, quantity: 1), perDose > 0, baseDoseAmount > 0 else { return nil }
        return roundedQuantity(target / perDose)
    }

    /// Share (0–1) of this food's energy that comes from `macro`.
    func energyShare(of macro: Macro) -> Double {
        let macroEnergy = (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9
        let total = max(Double(calories), macroEnergy)
        guard total > 0 else { return 0 }
        switch macro {
        case .protein: return (protein ?? 0) * 4 / total
        case .carbs: return (carbs ?? 0) * 4 / total
        case .fat: return (fat ?? 0) * 9 / total
        case .calories: return 1
        }
    }

    /// The amount of this food that sensibly replaces `quantity` doses of `other`, matching
    /// `other`'s main macro — or `nil` if this food isn't a real equivalent: it must be a genuine
    /// source of that macro (≥ 40% of its energy), the amount must be a realistic serving (at
    /// most 4 of its own doses) and the calories must stay within half/double of the original.
    func practicalEquivalentQuantity(to other: FoodItem, quantity: Double) -> Double? {
        let macro = other.dominantMacro
        guard dominantMacro == macro, energyShare(of: macro) >= 0.4,
              let equivalent = equivalentQuantity(to: other, quantity: quantity, matching: macro),
              equivalent <= 4 else { return nil }
        let originalCalories = Double(max(other.scaledCalories(quantity: quantity), 1))
        let ratio = Double(scaledCalories(quantity: equivalent)) / originalCalories
        return (0.5...2).contains(ratio) ? equivalent : nil
    }

    /// `quantity` doses, rounded so the base amount is a practical one to weigh or count.
    func roundedQuantity(_ quantity: Double) -> Double {
        let base = quantity * baseDoseAmount
        let step: Double = unit == .unit ? 0.5 : (base >= 20 ? 5 : 1)
        let rounded = max((base / step).rounded() * step, step)
        return rounded / baseDoseAmount
    }
}

/// A user-extensible category for supplements (e.g. "Proteína", "Gel Energético").
struct SupplementCategory: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
}

/// A physical place supplement stock is kept (e.g. "Casa", "Trabalho") — a shared entity like
/// `Store`, so the same location is managed once and reused across every supplement instead of
/// being retyped (and possibly mistyped) in each one.
struct StockLocation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
}

/// One supplement's stock at a particular `StockLocation`, tracked independently so consuming a
/// dose decrements the right one.
struct SupplementStock: Identifiable, Codable, Hashable {
    var id: UUID
    var locationID: UUID
    /// Remaining amount, in the supplement's own `unit`.
    var remaining: Double

    init(id: UUID = UUID(), locationID: UUID, remaining: Double) {
        self.id = id
        self.locationID = locationID
        self.remaining = remaining
    }
}

/// A sports supplement (protein, energy gel, isotonic, electrolytes, ...), priced and stocked
/// the same way as a `FoodItem`, but always logged per whole dose (no per-100 basis) and with
/// its own stock tracking across multiple locations.
///
/// Uses a custom decoder so supplements saved before `stocks`/`lowStockThreshold`/`isFavorite`/
/// `createdAt` existed still import cleanly, defaulting to no stock tracking.
struct Supplement: Identifiable, Codable, Hashable, Doseable, Favoritable {
    var id: UUID
    var name: String
    var categoryID: UUID
    /// The unit this supplement's package and doses are measured in.
    var unit: MeasurementUnit
    /// Total amount in the package, in `unit`.
    var totalSize: Double
    /// Amount of one dose, in `unit`.
    var doseSize: Double
    var calories: Int?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var prices: [PriceEntry]
    var stocks: [SupplementStock]
    /// Once a stock's remaining amount drops to or below this (in `unit`), it needs restocking.
    var lowStockThreshold: Double?
    var isFavorite: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        categoryID: UUID,
        unit: MeasurementUnit = .gram,
        totalSize: Double,
        doseSize: Double,
        calories: Int? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        prices: [PriceEntry] = [],
        stocks: [SupplementStock] = [],
        lowStockThreshold: Double? = nil,
        isFavorite: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.categoryID = categoryID
        self.unit = unit
        self.totalSize = totalSize
        self.doseSize = doseSize
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.prices = prices
        self.stocks = stocks
        self.lowStockThreshold = lowStockThreshold
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, categoryID, unit, totalSize, doseSize, calories, protein, carbs, fat,
             prices, stocks, lowStockThreshold, isFavorite, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        categoryID = try container.decode(UUID.self, forKey: .categoryID)
        unit = try container.decodeIfPresent(MeasurementUnit.self, forKey: .unit) ?? .gram
        totalSize = try container.decodeIfPresent(Double.self, forKey: .totalSize) ?? 1
        doseSize = try container.decodeIfPresent(Double.self, forKey: .doseSize) ?? 1
        calories = try container.decodeIfPresent(Int.self, forKey: .calories)
        protein = try container.decodeIfPresent(Double.self, forKey: .protein)
        carbs = try container.decodeIfPresent(Double.self, forKey: .carbs)
        fat = try container.decodeIfPresent(Double.self, forKey: .fat)
        prices = try container.decodeIfPresent([PriceEntry].self, forKey: .prices) ?? []
        // Stocks saved before locations were a shared entity had a freeform `name` instead of
        // `locationID`; rather than fail the whole database decode over that, just drop them —
        // they're recreated in the supplement editor.
        stocks = (try? container.decodeIfPresent([SupplementStock].self, forKey: .stocks)).flatMap { $0 } ?? []
        lowStockThreshold = try container.decodeIfPresent(Double.self, forKey: .lowStockThreshold)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
    }

    /// Number of doses the whole package yields, for information/display only.
    var doseCount: Double { doseSize > 0 ? totalSize / doseSize : 0 }

    func scaledCalories(quantity: Double) -> Int { Int((Double(calories ?? 0) * quantity).rounded()) }
    func scaledProtein(quantity: Double) -> Double? { protein.map { $0 * quantity } }
    func scaledCarbs(quantity: Double) -> Double? { carbs.map { $0 * quantity } }
    func scaledFat(quantity: Double) -> Double? { fat.map { $0 * quantity } }
}

/// One logged consumption of a supplement — `quantity` is in doses (e.g. 1.5 = one and a half).
struct SupplementLogEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var supplementID: UUID
    /// Which stock was decremented when this was logged, if any.
    var stockID: UUID?
    var quantity: Double
    var date: Date
}

/// One food item and how many doses of it a recipe uses.
struct RecipeItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var foodItemID: UUID
    var quantity: Double
}

/// A named group of previously-catalogued foods, so a whole meal can be logged in one action.
///
/// Uses a custom decoder so recipes saved before `isFavorite`/`createdAt` existed still import
/// cleanly, defaulting to not favorited.
struct Recipe: Identifiable, Codable, Equatable, Favoritable {
    var id: UUID
    var name: String
    var items: [RecipeItem]
    var isFavorite: Bool
    var createdAt: Date

    init(id: UUID = UUID(), name: String, items: [RecipeItem], isFavorite: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.items = items
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, items, isFavorite, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        items = try container.decode([RecipeItem].self, forKey: .items)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
    }
}

/// One alternative for a planned meal (e.g. "Batido proteico" or "Dias de treino"), linked to
/// the recipe that is logged when this option is chosen.
struct MealPlanOption: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    /// Free text straight from the plan, e.g. "2 ovos + 100g claras + 1 fatia pão integral".
    var details: String?
    /// The recipe logged for this option. `nil` (or pointing at a recipe that no longer exists)
    /// means it still has to be linked in the app before it can be logged.
    var recipeID: UUID?
}

/// One meal of a `MealPlan` (e.g. "Almoço"), with its macro targets and the options that can
/// fulfil it.
struct PlannedMeal: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// Which daily-log meal its options are logged under.
    var mealType: MealType
    var proteinTarget: Double?
    var carbsTarget: Double?
    var fatTarget: Double?
    var notes: String?
    var options: [MealPlanOption]
}

/// A nutritionist-style meal plan: a list of meals, each with one or more recipe-backed options.
struct MealPlan: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var author: String?
    var prescribedAt: Date?
    /// General guidance that isn't tied to a single meal (water, intra-workout, ...).
    var notes: String?
    var meals: [PlannedMeal]
}

/// A meal plan as exported/imported on its own. Self-contained: it carries every recipe the plan
/// links to and every catalog food those recipes use, so it can be imported into any database.
struct MealPlanFile: Codable {
    static let formatIdentifier = "CalorieBuddy.MealPlan"
    static let currentVersion = 1

    var format: String
    var version: Int
    var exportedAt: Date
    var plan: MealPlan
    var recipes: [Recipe]
    var foodItems: [FoodItem]
}

/// Calories and macros of a recipe (or anything else summed from catalog foods).
struct NutritionTotals: Equatable {
    var calories: Int = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
}

struct UserSettings: Codable, Equatable {
    var dailyCalorieGoal: Int
    var proteinGoal: Double?
    var carbsGoal: Double?
    var fatGoal: Double?
    var dailyWaterGoalML: Int?

    static let `default` = UserSettings(
        dailyCalorieGoal: 2000,
        proteinGoal: nil,
        carbsGoal: nil,
        fatGoal: nil,
        dailyWaterGoalML: 2000
    )
}

/// The full contents of a CalorieBuddy database, as exported/imported via JSON.
///
/// Uses a custom decoder so that databases exported before `foodItems`/`recipes`/`mealPlan`
/// existed (version 1) still import cleanly, with those collections defaulting to empty.
struct AppDatabase: Codable {
    static let currentVersion = 2

    var version: Int
    var exportedAt: Date
    var settings: UserSettings
    var entries: [FoodEntry]
    var foodItems: [FoodItem]
    var recipes: [Recipe]
    var stores: [Store]
    var supplementCategories: [SupplementCategory]
    var supplements: [Supplement]
    var supplementLogs: [SupplementLogEntry]
    var stockLocations: [StockLocation]
    var mealPlan: MealPlan?

    init(
        version: Int,
        exportedAt: Date,
        settings: UserSettings,
        entries: [FoodEntry],
        foodItems: [FoodItem],
        recipes: [Recipe],
        stores: [Store],
        supplementCategories: [SupplementCategory] = [],
        supplements: [Supplement] = [],
        supplementLogs: [SupplementLogEntry] = [],
        stockLocations: [StockLocation] = [],
        mealPlan: MealPlan? = nil
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.settings = settings
        self.entries = entries
        self.foodItems = foodItems
        self.recipes = recipes
        self.stores = stores
        self.supplementCategories = supplementCategories
        self.supplements = supplements
        self.supplementLogs = supplementLogs
        self.stockLocations = stockLocations
        self.mealPlan = mealPlan
    }

    private enum CodingKeys: String, CodingKey {
        case version, exportedAt, settings, entries, foodItems, recipes, stores,
             supplementCategories, supplements, supplementLogs, stockLocations, mealPlan
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        settings = try container.decode(UserSettings.self, forKey: .settings)
        entries = try container.decode([FoodEntry].self, forKey: .entries)
        foodItems = try container.decodeIfPresent([FoodItem].self, forKey: .foodItems) ?? []
        recipes = try container.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
        stores = try container.decodeIfPresent([Store].self, forKey: .stores) ?? []
        supplementCategories = try container.decodeIfPresent([SupplementCategory].self, forKey: .supplementCategories) ?? []
        supplements = try container.decodeIfPresent([Supplement].self, forKey: .supplements) ?? []
        supplementLogs = try container.decodeIfPresent([SupplementLogEntry].self, forKey: .supplementLogs) ?? []
        stockLocations = try container.decodeIfPresent([StockLocation].self, forKey: .stockLocations) ?? []
        mealPlan = try container.decodeIfPresent(MealPlan.self, forKey: .mealPlan)
    }
}
