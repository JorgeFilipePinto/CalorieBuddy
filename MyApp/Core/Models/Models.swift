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
    /// The rest of the label for what was eaten (absolute amounts; `nil` = not stated).
    var saturatedFat: Double? = nil
    var sugars: Double? = nil
    var fiber: Double? = nil
    var salt: Double? = nil
    /// `[Micronutrient.rawValue: amount]`, in each nutrient's unit.
    var micronutrients: [String: Double]? = nil
    /// The catalog food this was logged from and how many of its doses — while set, editing that
    /// food rewrites this entry's values (one source of truth). `nil` = typed in by hand.
    var foodItemID: UUID? = nil
    var quantity: Double? = nil
    /// The recipe this was logged from (as part of `groupID`): editing the recipe regenerates the
    /// group. `nil` when logged otherwise (including a meal-plan option with swapped foods).
    var recipeID: UUID? = nil

    var nutrition: NutritionAmounts {
        NutritionAmounts(
            calories: Double(calories),
            protein: protein,
            carbs: carbs,
            sugars: sugars,
            fat: fat,
            saturatedFat: saturatedFat,
            fiber: fiber,
            salt: salt,
            micronutrients: (micronutrients ?? [:]).typedMicronutrients
        )
    }

    /// Sets everything but energy and the three macros from `nutrition`.
    var extraNutrition: NutritionAmounts {
        get { nutrition }
        set {
            saturatedFat = newValue.saturatedFat
            sugars = newValue.sugars
            fiber = newValue.fiber
            salt = newValue.salt
            micronutrients = newValue.micronutrients.isEmpty ? nil : newValue.micronutrients.stored
        }
    }
}

extension FoodEntry {
    /// An entry for `nutrition` (e.g. a scaled catalog food). In an extension so the memberwise
    /// initializer stays available.
    init(name: String, nutrition: NutritionAmounts, mealType: MealType, date: Date, barcode: String? = nil,
         groupID: UUID? = nil, groupName: String? = nil) {
        self.init(name: name, calories: Int(nutrition.calories.rounded()), protein: nutrition.protein,
                  carbs: nutrition.carbs, fat: nutrition.fat, mealType: mealType, date: date, barcode: barcode,
                  groupID: groupID, groupName: groupName)
        extraNutrition = nutrition
    }
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
    /// What a search looks in (the name; foods add their brand and barcodes).
    var searchFields: [String] { get }
}

extension Favoritable {
    var searchFields: [String] { [name] }
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
    /// Keeps items matching `searchText` (every word, anywhere in `searchFields`, ignoring case and
    /// accents), then sorts by the given order.
    func filteredAndSorted(searchText: String, order: ItemSortOrder) -> [Element] {
        let filtered = searchText.isEmpty ? self : filter { SearchMatch.matches(searchText, in: $0.searchFields) }
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
/// A user-editable group for catalog foods (e.g. "Proteína", "Hidratos de carbono", "Gordura
/// saturada"), so the catalog can be browsed by what each food is for.
struct FoodCategory: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
}

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
    /// Free-text minerals/vitamins from before `micronutrients`: only names the fixed list doesn't
    /// know stay here (the rest move to `micronutrients` when decoded).
    var minerals: [NutrientValue]
    var vitamins: [NutrientValue]
    /// The rest of the nutrition label, on the same basis as the macros (grams; `micronutrients`
    /// as `[Micronutrient.rawValue: amount]` in each nutrient's unit). `nil` = not stated.
    var saturatedFat: Double?
    var sugars: Double?
    var fiber: Double?
    var salt: Double?
    var micronutrients: [String: Double] = [:]
    /// Every barcode that identifies this item — lets near-identical variants of the same
    /// product (different pack sizes, regional printings, minor recipe tweaks) share one
    /// catalog entry instead of being duplicated.
    var barcodes: [String]
    /// Price of this item at each store it's been priced at.
    var prices: [PriceEntry]
    var isFavorite: Bool
    var createdAt: Date
    /// The item's photo in `PhotoStore` (`nil` = none).
    var photoID: UUID?
    /// Photos of its nutrition label, in `PhotoStore` (front, back…), for checking the values.
    var labelPhotoIDs: [UUID] = []
    /// Its `FoodCategory` (`nil` = uncategorised).
    var categoryID: UUID?

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
        createdAt: Date = Date(),
        photoID: UUID? = nil,
        categoryID: UUID? = nil
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
        self.photoID = photoID
        self.categoryID = categoryID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, brand, unit, doseSize, nutritionBasis, calories, protein, carbs, fat,
             minerals, vitamins, barcodes, prices, isFavorite, createdAt, photoID, categoryID, labelPhotoIDs,
             saturatedFat, sugars, fiber, salt, micronutrients
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
        saturatedFat = try container.decodeIfPresent(Double.self, forKey: .saturatedFat)
        sugars = try container.decodeIfPresent(Double.self, forKey: .sugars)
        fiber = try container.decodeIfPresent(Double.self, forKey: .fiber)
        salt = try container.decodeIfPresent(Double.self, forKey: .salt)
        micronutrients = try container.decodeIfPresent([String: Double].self, forKey: .micronutrients) ?? [:]
        // Free-text vitamins/minerals the fixed list knows move to `micronutrients`.
        var micros = micronutrients
        minerals = Self.adopt(minerals, into: &micros)
        vitamins = Self.adopt(vitamins, into: &micros)
        micronutrients = micros
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
        photoID = try container.decodeIfPresent(UUID.self, forKey: .photoID)
        categoryID = try container.decodeIfPresent(UUID.self, forKey: .categoryID)
        labelPhotoIDs = try container.decodeIfPresent([UUID].self, forKey: .labelPhotoIDs) ?? []
    }

    /// Moves the free-text `values` the fixed list knows into `micros` (in their own unit) and
    /// returns the ones it doesn't.
    static func adopt(_ values: [NutrientValue], into micros: inout [String: Double]) -> [NutrientValue] {
        values.filter { value in
            guard let nutrient = Micronutrient.matching(value.name),
                  let amount = nutrient.convert(value.amount, from: value.unit) else { return true }
            micros[nutrient.rawValue, default: 0] += amount
            return false
        }
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

    /// Everything in `quantity` doses.
    func nutrition(quantity: Double) -> NutritionAmounts {
        NutritionAmounts(
            calories: Double(calories),
            protein: protein,
            carbs: carbs,
            sugars: sugars,
            fat: fat,
            saturatedFat: saturatedFat,
            fiber: fiber,
            salt: salt,
            micronutrients: micronutrients.typedMicronutrients
        ).scaled(by: nutritionScale * quantity)
    }
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

    var searchFields: [String] { [name, brand ?? ""] + barcodes }

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
    /// Whether the nutrition values are per 100 (g/ml) or per one dose (older supplements: per dose).
    var nutritionBasis: NutritionBasis = .perDose
    var calories: Int?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    /// The rest of the nutrition label, on the same basis as the macros (grams; `micronutrients`
    /// as `[Micronutrient.rawValue: amount]` in each nutrient's unit). `nil` = not stated.
    var saturatedFat: Double?
    var sugars: Double?
    var fiber: Double?
    var salt: Double?
    var micronutrients: [String: Double] = [:]
    var prices: [PriceEntry]
    var stocks: [SupplementStock]
    /// Once a stock's remaining amount drops to or below this (in `unit`), it needs restocking.
    var lowStockThreshold: Double?
    var isFavorite: Bool
    var createdAt: Date
    /// The supplement's photo in `PhotoStore` (`nil` = none).
    var photoID: UUID?
    /// Barcodes of its packages: scanning one from a day's "+" logs this supplement.
    var barcodes: [String]
    /// Photos of its nutrition label, in `PhotoStore` (front, back…), for checking the values.
    var labelPhotoIDs: [UUID] = []

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
        createdAt: Date = Date(),
        photoID: UUID? = nil,
        barcodes: [String] = []
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
        self.photoID = photoID
        self.barcodes = barcodes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, categoryID, unit, totalSize, doseSize, calories, protein, carbs, fat,
             prices, stocks, lowStockThreshold, isFavorite, createdAt, photoID, barcodes, labelPhotoIDs,
             nutritionBasis, saturatedFat, sugars, fiber, salt, micronutrients
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
        photoID = try container.decodeIfPresent(UUID.self, forKey: .photoID)
        barcodes = try container.decodeIfPresent([String].self, forKey: .barcodes) ?? []
        labelPhotoIDs = try container.decodeIfPresent([UUID].self, forKey: .labelPhotoIDs) ?? []
        nutritionBasis = try container.decodeIfPresent(NutritionBasis.self, forKey: .nutritionBasis) ?? .perDose
        saturatedFat = try container.decodeIfPresent(Double.self, forKey: .saturatedFat)
        sugars = try container.decodeIfPresent(Double.self, forKey: .sugars)
        fiber = try container.decodeIfPresent(Double.self, forKey: .fiber)
        salt = try container.decodeIfPresent(Double.self, forKey: .salt)
        micronutrients = try container.decodeIfPresent([String: Double].self, forKey: .micronutrients) ?? [:]
    }

    /// Multiplier turning the stored nutrition values into "nutrition for one dose".
    private var nutritionScale: Double {
        switch nutritionBasis {
        case .perDose: return 1
        case .per100: return (doseSize * unit.baseMultiplier) / 100
        }
    }

    /// Number of doses the whole package yields, for information/display only.
    var doseCount: Double { doseSize > 0 ? totalSize / doseSize : 0 }

    /// What's left across every stock location, in `unit` (logging a dose from a stock lowers it).
    var totalRemaining: Double { stocks.reduce(0) { $0 + $1.remaining } }

    /// How many doses `amount` (in `unit`) holds.
    func doses(in amount: Double) -> Double { doseSize > 0 ? amount / doseSize : 0 }

    func scaledCalories(quantity: Double) -> Int { Int((Double(calories ?? 0) * nutritionScale * quantity).rounded()) }
    func scaledProtein(quantity: Double) -> Double? { protein.map { $0 * nutritionScale * quantity } }
    func scaledCarbs(quantity: Double) -> Double? { carbs.map { $0 * nutritionScale * quantity } }
    func scaledFat(quantity: Double) -> Double? { fat.map { $0 * nutritionScale * quantity } }

    /// Everything in `quantity` doses.
    func nutrition(quantity: Double) -> NutritionAmounts {
        NutritionAmounts(
            calories: Double(calories ?? 0),
            protein: protein,
            carbs: carbs,
            sugars: sugars,
            fat: fat,
            saturatedFat: saturatedFat,
            fiber: fiber,
            salt: salt,
            micronutrients: micronutrients.typedMicronutrients
        ).scaled(by: nutritionScale * quantity)
    }
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
    /// The recipe's photo in `PhotoStore` (`nil` = none).
    var photoID: UUID?
    /// Photos of its nutrition label, in `PhotoStore` (front, back…), for checking the values.
    var labelPhotoIDs: [UUID] = []

    init(id: UUID = UUID(), name: String, items: [RecipeItem], isFavorite: Bool = false, createdAt: Date = Date(), photoID: UUID? = nil) {
        self.id = id
        self.name = name
        self.items = items
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.photoID = photoID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, items, isFavorite, createdAt, photoID, labelPhotoIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        items = try container.decode([RecipeItem].self, forKey: .items)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        photoID = try container.decodeIfPresent(UUID.self, forKey: .photoID)
        labelPhotoIDs = try container.decodeIfPresent([UUID].self, forKey: .labelPhotoIDs) ?? []
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
/// Several can exist, each covering `startsOn` through `endsOn` (`nil` = open-ended); when more
/// than one covers a day, the highest `priority` applies — the same rule as `NutritionPlan`, so a
/// temporary plan (e.g. race week) can run alongside the normal one.
struct MealPlan: Identifiable, Codable, Equatable, PrioritizedPlan {
    var id: UUID = UUID()
    var name: String
    var author: String?
    var prescribedAt: Date?
    /// General guidance that isn't tied to a single meal (water, intra-workout, ...).
    var notes: String?
    var meals: [PlannedMeal]
    var startsOn: Date = .distantPast
    /// `nil` = open-ended.
    var endsOn: Date?
    var priority: Int = 1
}

extension MealPlan {
    /// Plans saved before the schedule existed start on their prescription date (or "always").
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        prescribedAt = try container.decodeIfPresent(Date.self, forKey: .prescribedAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        meals = try container.decode([PlannedMeal].self, forKey: .meals)
        startsOn = try container.decodeIfPresent(Date.self, forKey: .startsOn) ?? prescribedAt ?? .distantPast
        endsOn = try container.decodeIfPresent(Date.self, forKey: .endsOn)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 1
    }
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

/// Which kind of day a nutrition target applies to. A day counts as `training` when it has at
/// least one logged workout, `rest` otherwise — decided from the day's data, never stored.
enum DayType: String, Codable, CaseIterable, Identifiable {
    case training, rest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .training: return "Treino"
        case .rest: return "Descanso"
        }
    }

    var symbolName: String {
        switch self {
        case .training: return "figure.run"
        case .rest: return "bed.double"
        }
    }
}

/// Daily targets for one `DayType`.
struct NutritionTargets: Codable, Equatable {
    var kcal: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var waterML: Int

    /// Energy implied by the macros (protein/carbs 4 kcal/g, fat 9 kcal/g).
    var macroKcal: Int { proteinG * 4 + carbsG * 4 + fatG * 9 }

    /// Whether the macros disagree with `kcal` by more than 10% — usually a typo.
    var hasMacroMismatch: Bool {
        guard kcal > 0 else { return false }
        return abs(Double(macroKcal - kcal)) / Double(kcal) > 0.1
    }
}

/// A nutritionist-set plan of daily targets, covering `startsOn` through `endsOn` (`nil` =
/// open-ended, the normal case). When more than one live plan covers a day, `priority` (1–5,
/// higher wins) decides which one applies — lets a temporary, higher-priority plan (e.g. for a
/// race) run alongside the normal open-ended one. Soft-deleted (kept, flagged) rather than removed
/// outright, so history isn't lost.
struct NutritionPlan: Identifiable, Codable, Equatable, PrioritizedPlan {
    var id: UUID = UUID()
    var name: String
    var startsOn: Date
    /// `nil` = open-ended.
    var endsOn: Date?
    var priority: Int = 1
    var notes: String?
    var training: NutritionTargets
    var rest: NutritionTargets
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, name, startsOn, endsOn, priority, notes, training, rest, createdAt, updatedAt, deletedAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        startsOn: Date,
        endsOn: Date? = nil,
        priority: Int = 1,
        notes: String? = nil,
        training: NutritionTargets,
        rest: NutritionTargets,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.startsOn = startsOn
        self.endsOn = endsOn
        self.priority = priority
        self.notes = notes
        self.training = training
        self.rest = rest
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        startsOn = try container.decode(Date.self, forKey: .startsOn)
        endsOn = try container.decodeIfPresent(Date.self, forKey: .endsOn)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 1
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        training = try container.decode(NutritionTargets.self, forKey: .training)
        rest = try container.decode(NutritionTargets.self, forKey: .rest)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

/// Whether a plan's date range covers today, is still ahead, or has already ended. Plans can
/// overlap, so this alone doesn't say which one applies — see `inEffect`.
enum PlanStatus {
    case scheduled, active, ended
}

/// One plan with its computed status. `inEffect` is true for at most one plan: the active plan
/// actually applied today (highest `priority`; ties favour the plan that started most recently).
/// Other active plans are still shown, just overridden.
struct ClassifiedPlan<Plan: PrioritizedPlan>: Identifiable {
    var plan: Plan
    var status: PlanStatus
    var inEffect: Bool
    var id: UUID { plan.id }
}

typealias ClassifiedNutritionPlan = ClassifiedPlan<NutritionPlan>

/// A plan with a date range and a priority: nutrition plans (daily targets) and meal plans
/// (meals and options). Both follow the platform's rule for which one applies on a day.
protocol PrioritizedPlan: Identifiable where ID == UUID {
    var startsOn: Date { get }
    var endsOn: Date? { get }
    var priority: Int { get }
}

extension Array where Element: PrioritizedPlan {
    /// The plan in effect on `day`: among those whose date range covers it, the highest
    /// `priority`, ties broken by the most recent `startsOn` — the rule the platform's
    /// `daily_summary` uses.
    func inEffect(on day: Date) -> Element? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        return filter { calendar.startOfDay(for: $0.startsOn) <= startOfDay
                && ($0.endsOn.map { calendar.startOfDay(for: $0) >= startOfDay } ?? true) }
            .sorted { a, b in a.priority != b.priority ? a.priority > b.priority : a.startsOn > b.startsOn }
            .first
    }

    /// Every plan with its status against `today` — from its own dates only (`scheduled` hasn't
    /// started, `ended` passed its `endsOn`, otherwise `active`) — and `inEffect` on the single
    /// active plan that wins the priority tie-break. Ordered by start date.
    func classifiedPlans(today: Date) -> [ClassifiedPlan<Element>] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: today)
        let winnerID = inEffect(on: today)?.id
        return sorted { $0.startsOn < $1.startsOn }.map { plan in
            let status: PlanStatus
            if calendar.startOfDay(for: plan.startsOn) > startOfToday {
                status = .scheduled
            } else if let endsOn = plan.endsOn, calendar.startOfDay(for: endsOn) < startOfToday {
                status = .ended
            } else {
                status = .active
            }
            return ClassifiedPlan(plan: plan, status: status, inEffect: plan.id == winnerID)
        }
    }
}

extension Array where Element == NutritionPlan {
    /// Plans that haven't been (soft-)deleted, ordered by start date.
    var live: [NutritionPlan] {
        filter { $0.deletedAt == nil }.sorted { $0.startsOn < $1.startsOn }
    }

    /// The plan in effect on `day` (see `inEffect(on:)`), ignoring deleted plans.
    func plan(on day: Date) -> NutritionPlan? {
        live.inEffect(on: day)
    }

    /// Every live plan with its status against `today` (see `classifiedPlans(today:)`).
    func classified(today: Date) -> [ClassifiedNutritionPlan] {
        live.classifiedPlans(today: today)
    }
}

/// A body-composition value or body measurement entered in the app. Apple Health has no type for
/// most of these (visceral fat, muscle mass, most circumferences), so they live in the app's own
/// database; weight, body fat %, BMI and lean mass still come from Apple Health.
enum BodyMetric: String, Codable, CaseIterable, Identifiable {
    case bodyFat, muscleMass, leanMass, visceralFat
    case neck, chest, arm, waist, hip, thigh, calf

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bodyFat: return "Massa Gorda"
        case .muscleMass: return "Massa Muscular"
        case .leanMass: return "Massa Magra"
        case .visceralFat: return "Gordura Visceral"
        case .neck: return "Pescoço"
        case .chest: return "Peito"
        case .arm: return "Braço"
        case .waist: return "Cintura"
        case .hip: return "Anca"
        case .thigh: return "Coxa"
        case .calf: return "Gémeo"
        }
    }

    /// "%", "kg", "" (visceral fat is a unitless level) or "cm".
    var unitLabel: String {
        switch self {
        case .bodyFat: return "%"
        case .muscleMass, .leanMass: return "kg"
        case .visceralFat: return ""
        default: return "cm"
        }
    }

    var symbolName: String {
        switch self {
        case .bodyFat: return "percent"
        case .muscleMass: return "figure.strengthtraining.traditional"
        case .leanMass: return "figure.walk"
        case .visceralFat: return "circle.dashed.inset.filled"
        default: return "ruler"
        }
    }

    var isCircumference: Bool {
        switch self {
        case .bodyFat, .muscleMass, .leanMass, .visceralFat: return false
        default: return true
        }
    }

    /// Kept in Apple Health rather than in the app's database — the types Health has. Writing them
    /// there makes them visible to every other health app (and synced via the Health sync).
    var isHealthKitWritable: Bool {
        switch self {
        case .bodyFat, .leanMass, .waist: return true
        default: return false
        }
    }

    /// Accepted values when entering one, to catch typos (e.g. 850 cm instead of 85,0).
    var validRange: ClosedRange<Double> {
        switch self {
        case .bodyFat: return 2...70
        case .muscleMass: return 5...150
        case .leanMass: return 20...150
        case .visceralFat: return 1...59
        case .neck: return 20...70
        case .chest: return 50...200
        case .arm: return 15...70
        case .waist: return 40...200
        case .hip: return 50...200
        case .thigh: return 25...100
        case .calf: return 20...70
        }
    }

    /// How to take the measurement, shown next to the figure in the guide.
    var howToMeasure: String {
        switch self {
        case .bodyFat:
            return "Lê o valor numa balança de bioimpedância ou numa avaliação (ex.: DEXA). Mede sempre nas mesmas condições: de manhã, em jejum, depois de ir à casa de banho."
        case .muscleMass:
            return "Só o músculo (sobretudo esquelético). Lê o valor de massa muscular da balança de bioimpedância ou da avaliação (DEXA), sempre da mesma fonte. Mede nas mesmas condições do peso: de manhã, em jejum."
        case .leanMass:
            return "Tudo o que não é gordura — músculo, ossos, órgãos e água —, ou seja peso − massa gorda. É sempre maior do que a massa muscular. Lê-o da balança ou da avaliação, nas mesmas condições do peso."
        case .visceralFat:
            return "Nível de gordura visceral (1–59) indicado pela balança de bioimpedância. Até 12 é considerado saudável na maioria das balanças."
        case .neck:
            return "Fita logo abaixo da maçã de Adão, ligeiramente inclinada para a frente e para baixo. Olha em frente, ombros relaxados."
        case .chest:
            return "Fita à volta da parte mais larga do peito, à altura dos mamilos, por baixo das axilas. Mede no fim de uma expiração normal."
        case .arm:
            return "Braço relaxado ao lado do corpo. Fita a meio caminho entre o ombro e o cotovelo (no ponto mais largo do bíceps)."
        case .waist:
            return "Fita a meio caminho entre a última costela e o topo da anca (normalmente à altura do umbigo), paralela ao chão. Mede no fim de uma expiração normal, sem encolher a barriga."
        case .hip:
            return "Pés juntos. Fita à volta da parte mais saliente dos glúteos, paralela ao chão."
        case .thigh:
            return "De pé, peso nas duas pernas. Fita à volta da parte mais larga da coxa, logo abaixo do glúteo."
        case .calf:
            return "De pé, peso nas duas pernas. Fita à volta da parte mais larga do gémeo."
        }
    }

    /// Where the measuring tape goes on a standing figure, as fractions of its width/height:
    /// `y` from the top, `x`/`width` from the left (`nil` for the non-tape metrics).
    var tapePosition: (y: Double, x: Double, width: Double)? {
        switch self {
        case .neck: return (0.215, 0.41, 0.16)
        case .chest: return (0.34, 0.28, 0.44)
        case .arm: return (0.38, 0.07, 0.21)
        case .waist: return (0.47, 0.30, 0.40)
        case .hip: return (0.57, 0.28, 0.44)
        case .thigh: return (0.70, 0.26, 0.23)
        case .calf: return (0.85, 0.27, 0.21)
        default: return nil
        }
    }
}

/// One value of a `BodyMetric` on a given date.
struct BodyMeasurement: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var metric: BodyMetric
    var value: Double
    var date: Date
}

/// Which way the body faces in a progress photo — photos are compared pose by pose.
enum ProgressPose: String, Codable, CaseIterable, Identifiable {
    case front, side, back

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .front: return "Frente"
        case .side: return "Perfil"
        case .back: return "Costas"
        }
    }

    var symbolName: String {
        switch self {
        case .front: return "figure.stand"
        case .side: return "figure.walk"
        case .back: return "figure.stand.line.dotted.figure.stand"
        }
    }
}

/// One photo of the physical-progress log. The image itself lives in `PhotoStore` (keyed by
/// `photoID`), not in the JSON database.
struct ProgressPhoto: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var pose: ProgressPose
    var photoID: UUID
    var notes: String?
}

/// The full contents of a CalorieBuddy database, as exported/imported via JSON.
///
/// Uses a custom decoder so that databases exported before `foodItems`/`recipes`/`mealPlans`
/// existed (version 1) still import cleanly, with those collections defaulting to empty.
struct AppDatabase: Codable {
    static let currentVersion = 2

    var version: Int
    var exportedAt: Date
    var settings: UserSettings
    var entries: [FoodEntry]
    var foodItems: [FoodItem]
    var foodCategories: [FoodCategory]
    var recipes: [Recipe]
    var stores: [Store]
    var supplementCategories: [SupplementCategory]
    var supplements: [Supplement]
    var supplementLogs: [SupplementLogEntry]
    var stockLocations: [StockLocation]
    var mealPlans: [MealPlan]
    var nutritionPlans: [NutritionPlan]
    var bodyMeasurements: [BodyMeasurement]
    var progressPhotos: [ProgressPhoto]

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
        mealPlans: [MealPlan] = [],
        nutritionPlans: [NutritionPlan] = [],
        bodyMeasurements: [BodyMeasurement] = [],
        progressPhotos: [ProgressPhoto] = [],
        foodCategories: [FoodCategory] = []
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.settings = settings
        self.entries = entries
        self.foodItems = foodItems
        self.foodCategories = foodCategories
        self.recipes = recipes
        self.stores = stores
        self.supplementCategories = supplementCategories
        self.supplements = supplements
        self.supplementLogs = supplementLogs
        self.stockLocations = stockLocations
        self.mealPlans = mealPlans
        self.nutritionPlans = nutritionPlans
        self.bodyMeasurements = bodyMeasurements
        self.progressPhotos = progressPhotos
    }

    private enum CodingKeys: String, CodingKey {
        case version, exportedAt, settings, entries, foodItems, recipes, stores,
             supplementCategories, supplements, supplementLogs, stockLocations, mealPlans, nutritionPlans,
             bodyMeasurements, progressPhotos, foodCategories
    }

    /// Databases written before several meal plans existed had at most one, under `mealPlan`.
    private enum LegacyCodingKeys: String, CodingKey {
        case mealPlan
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        settings = try container.decode(UserSettings.self, forKey: .settings)
        entries = try container.decode([FoodEntry].self, forKey: .entries)
        foodItems = try container.decodeIfPresent([FoodItem].self, forKey: .foodItems) ?? []
        foodCategories = try container.decodeIfPresent([FoodCategory].self, forKey: .foodCategories) ?? []
        recipes = try container.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
        stores = try container.decodeIfPresent([Store].self, forKey: .stores) ?? []
        supplementCategories = try container.decodeIfPresent([SupplementCategory].self, forKey: .supplementCategories) ?? []
        supplements = try container.decodeIfPresent([Supplement].self, forKey: .supplements) ?? []
        supplementLogs = try container.decodeIfPresent([SupplementLogEntry].self, forKey: .supplementLogs) ?? []
        stockLocations = try container.decodeIfPresent([StockLocation].self, forKey: .stockLocations) ?? []
        if let plans = try container.decodeIfPresent([MealPlan].self, forKey: .mealPlans) {
            mealPlans = plans
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            mealPlans = try legacy.decodeIfPresent(MealPlan.self, forKey: .mealPlan).map { [$0] } ?? []
        }
        nutritionPlans = try container.decodeIfPresent([NutritionPlan].self, forKey: .nutritionPlans) ?? []
        bodyMeasurements = try container.decodeIfPresent([BodyMeasurement].self, forKey: .bodyMeasurements) ?? []
        progressPhotos = try container.decodeIfPresent([ProgressPhoto].self, forKey: .progressPhotos) ?? []
    }
}
