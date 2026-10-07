import Foundation

extension FoodItem {
    /// A preparation (subgroup) of another food: Frango → grelhado, cozido…
    var isPreparation: Bool { baseFoodID != nil }

    /// Foods counted in units (eggs, yogurts…) have no weight change to work from.
    var canHavePreparations: Bool { unit.baseUnit != .unit && !isPreparation }

    /// The food's name without a "cru" marker: "Peito de Frango (cru)" → "Peito de Frango".
    var nameWithoutRawMarker: String {
        var name = name
        for marker in ["(cru)", "(crua)", "(crus)", "(cruas)"] {
            name = name.replacingOccurrences(of: marker, with: "", options: [.caseInsensitive, .diacriticInsensitive])
        }
        let words = name.split(separator: " ")
        let trimmed = words.last.map { ["cru", "crua", "crus", "cruas"].contains(SearchMatch.normalized(String($0))) } == true
            ? words.dropLast()
            : words[...]
        return trimmed.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// The name a new preparation gets: "Peito de Frango (grelhado)".
    func preparationName(_ method: FoodPreparation) -> String {
        "\(nameWithoutRawMarker) (\(method.nameSuffix))"
    }

    /// `method` of this (raw) food with a weight change of `change` % — or `existing` (an earlier
    /// version of the same preparation) brought up to date. Cooking adds or loses mostly water, so
    /// the nutrients of 100 g raw end up in 100 × (1 + change) g: the label per 100 g/ml cooked is
    /// the raw one divided by (1 + change). Its own name, category, photo, barcodes and prices are
    /// kept; the label always follows the raw food.
    func prepared(_ method: FoodPreparation, change: Double, updating existing: FoodItem? = nil) -> FoodItem {
        let factor = max(1 + change / 100, 0.01)
        // Stored values → per 100 g/ml of the raw food → per 100 g/ml cooked.
        let toPer100 = nutritionBasis == .per100 ? 1 : (baseDoseAmount > 0 ? 100 / baseDoseAmount : 0)
        let scale = toPer100 / factor
        var item = existing ?? FoodItem(name: preparationName(method), calories: 0)
        item.unit = unit.baseUnit
        item.nutritionBasis = .per100
        if existing == nil {
            // One dose: a raw dose once cooked, rounded to whole grams/millilitres.
            item.doseSize = max((baseDoseAmount * factor).rounded(), 1)
            item.categoryID = categoryID
        }
        item.calories = Int((Double(calories) * scale).rounded())
        item.protein = protein.map { $0 * scale }
        item.carbs = carbs.map { $0 * scale }
        item.fat = fat.map { $0 * scale }
        item.saturatedFat = saturatedFat.map { $0 * scale }
        item.sugars = sugars.map { $0 * scale }
        item.fiber = fiber.map { $0 * scale }
        item.salt = salt.map { $0 * scale }
        item.micronutrients = micronutrients.mapValues { $0 * scale }
        item.minerals = []
        item.vitamins = []
        item.baseFoodID = id
        item.preparation = method
        item.cookingWeightChange = change
        return item
    }
}

extension Array where Element == FoodItem {
    /// The foods with each one's preparations right after it (as they're listed under the raw food);
    /// a preparation whose raw food isn't in the list stays where it is.
    func withPreparationsUnderBase() -> [(item: FoodItem, isNested: Bool)] {
        let ids = Set(map(\.id))
        var result: [(item: FoodItem, isNested: Bool)] = []
        for item in self where !(item.baseFoodID.map(ids.contains) ?? false) {
            result.append((item, false))
            for preparation in self where preparation.baseFoodID == item.id {
                result.append((preparation, true))
            }
        }
        return result
    }
}
