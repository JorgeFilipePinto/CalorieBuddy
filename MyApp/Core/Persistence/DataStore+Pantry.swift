import Foundation

/// A lot that's about to expire (or already has), for the warnings.
struct ExpiringLot: Identifiable {
    let lot: PantryLot
    let food: FoodItem
    /// Days until it expires: 0 = today, negative = already expired.
    let daysLeft: Int
    var id: UUID { lot.id }

    var label: String {
        switch daysLeft {
        case ..<0: return daysLeft == -1 ? "expirou ontem" : "expirou há \(-daysLeft) dias"
        case 0: return "expira hoje"
        case 1: return "expira amanhã"
        default: return "expira em \(daysLeft) dias"
        }
    }
}

/// What a meal prep needs: per recipe, how much of each ingredient goes in one box (raw and
/// cooked), and all together, the raw amounts against what's in the stock.
struct MealPrepPlan {
    struct Ingredient: Identifiable {
        /// What's weighed raw and taken from the stock (the raw food of a preparation).
        let food: FoodItem
        /// The recipe's preparation of it (Frango grelhado), when the recipe uses one.
        let preparedAs: FoodItem?
        /// Raw amount per box, in the food's base unit.
        let rawPerBox: Double
        /// After cooking (= raw for foods counted in units).
        let cookedPerBox: Double
        /// The weight change used, in %.
        let weightChange: Double
        var id: UUID { preparedAs?.id ?? food.id }
    }

    struct RecipePart: Identifiable {
        let item: MealPrepItem
        let recipe: Recipe
        /// Portions of the recipe (at its default amounts) in one box.
        let portionsPerBox: Double
        /// Cooked grams of one default portion (g and ml; foods in units aren't weighed).
        let cookedPortionWeight: Double
        let ingredients: [Ingredient]
        /// One box, as recipe items (doses), for its nutrition.
        let boxItems: [RecipeItem]
        /// Some ingredient is counted in units, so the cooked weight leaves it out.
        let hasUnitIngredients: Bool
        var id: UUID { item.id }
        var cookedBoxWeight: Double { cookedPortionWeight * portionsPerBox }
    }

    struct Requirement: Identifiable {
        let food: FoodItem
        /// Raw amount needed for every box, in the food's base unit.
        let rawAmount: Double
        /// In the chosen stock, not expired.
        let available: Double
        var id: UUID { food.id }
        var missing: Double { max(rawAmount - available, 0) }
        /// What to buy: whole grams/millilitres/units, rounded up.
        var toBuy: Double { (missing - 0.0001).rounded(.up) }
    }

    let recipes: [RecipePart]
    let requirements: [Requirement]

    var shoppingList: [Requirement] { requirements.filter { $0.toBuy > 0 } }
    var totalBoxes: Int { recipes.reduce(0) { $0 + $1.item.boxes } }
}

extension DataStore {
    // MARK: Stock

    func pantryLocation(withID id: UUID?) -> PantryLocation? {
        guard let id else { return nil }
        return pantryLocations.first { $0.id == id }
    }

    /// How much of `foodID` is in stock (base units) at `locationID` (`nil` = everywhere), by
    /// default leaving out what's expired.
    func pantryStock(of foodID: UUID, at locationID: UUID? = nil, includingExpired: Bool = false) -> Double {
        let today = Calendar.current.startOfDay(for: .now)
        return pantryLots
            .filter { lot in
                lot.foodItemID == foodID && (locationID == nil || lot.locationID == locationID)
                    && (includingExpired || (lot.expiresOn.map { $0 >= today } ?? true))
            }
            .reduce(0) { $0 + $1.remaining }
    }

    var expiryWarningDays: Int { settings.expiryWarningDays ?? 3 }

    /// Lots expiring within the warning window (or already expired), soonest first.
    func expiringPantryLots(withinDays days: Int? = nil) -> [ExpiringLot] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let window = days ?? expiryWarningDays
        return pantryLots.compactMap { lot in
            guard let expiresOn = lot.expiresOn, let food = foodItems.first(where: { $0.id == lot.foodItemID }) else { return nil }
            let daysLeft = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: expiresOn)).day ?? 0
            return daysLeft <= window ? ExpiringLot(lot: lot, food: food, daysLeft: daysLeft) : nil
        }
        .sorted { $0.daysLeft < $1.daysLeft }
    }

    // MARK: Cooking

    /// The weight change used for `food` when cooked (%), and the reference it came from (`nil`
    /// when the food has its own value or none applies). Foods counted in units don't change.
    func cookingWeightChange(for food: FoodItem) -> (percent: Double, reference: CookingYield?) {
        guard food.unit.baseUnit != .unit else { return (0, nil) }
        if let own = food.cookingWeightChange { return (own, nil) }
        if let reference = CookingYield.reference(for: food.name, in: cookingYields) { return (reference.weightChange, reference) }
        return (0, nil)
    }

    /// Works out `prep`: each recipe scaled so one box holds the cooked weight asked for (raw
    /// amounts = cooked / (1 + change)), then every ingredient added up and checked against the
    /// stock at the prep's location.
    func mealPrepPlan(for prep: MealPrep) -> MealPrepPlan {
        var recipesOut: [MealPrepPlan.RecipePart] = []
        var totals: [UUID: Double] = [:]
        var order: [UUID] = []

        for item in prep.items {
            guard let recipe = recipe(withID: item.recipeID) else { continue }
            // Per line: what's weighed raw (and stocked), how much raw and cooked, and the change.
            // A preparation in the recipe (Frango grelhado) is already the cooked weight: raw =
            // cooked / (1 + change), from its raw food's stock.
            let lines = recipe.items.compactMap { line -> (stock: FoodItem, preparedAs: FoodItem?, raw: Double, cooked: Double, change: Double)? in
                guard let food = foodItems.first(where: { $0.id == line.foodItemID }) else { return nil }
                let amount = line.quantity * food.baseDoseAmount
                if let base = baseFood(of: food) {
                    let change = food.cookingWeightChange ?? 0
                    return (base, food, amount / max(1 + change / 100, 0.01), amount, change)
                }
                let change = cookingWeightChange(for: food).percent
                return (food, nil, amount, amount * (1 + change / 100), change)
            }
            let cookedPortion = lines.reduce(0.0) { total, line in
                line.stock.unit.baseUnit == .unit ? total : total + line.cooked
            }
            let portionsPerBox: Double
            if let weight = item.cookedWeightPerBox, weight > 0, cookedPortion > 0 {
                portionsPerBox = weight / cookedPortion
            } else {
                portionsPerBox = 1
            }
            let ingredients = lines.map { line in
                MealPrepPlan.Ingredient(food: line.stock, preparedAs: line.preparedAs, rawPerBox: line.raw * portionsPerBox,
                                        cookedPerBox: line.cooked * portionsPerBox, weightChange: line.change)
            }
            for ingredient in ingredients {
                if totals[ingredient.food.id] == nil { order.append(ingredient.food.id) }
                totals[ingredient.food.id, default: 0] += ingredient.rawPerBox * Double(item.boxes)
            }
            recipesOut.append(MealPrepPlan.RecipePart(
                item: item,
                recipe: recipe,
                portionsPerBox: portionsPerBox,
                cookedPortionWeight: cookedPortion,
                ingredients: ingredients,
                boxItems: recipe.items.map { RecipeItem(foodItemID: $0.foodItemID, quantity: $0.quantity * portionsPerBox) },
                hasUnitIngredients: lines.contains { $0.stock.unit.baseUnit == .unit }
            ))
        }

        let requirements = order.compactMap { id -> MealPrepPlan.Requirement? in
            guard let food = foodItems.first(where: { $0.id == id }), let amount = totals[id] else { return nil }
            return MealPrepPlan.Requirement(food: food, rawAmount: amount, available: pantryStock(of: id, at: prep.locationID))
        }
        return MealPrepPlan(recipes: recipesOut, requirements: requirements)
    }

    /// The shopping list as plain text, one "- food: amount" line each — pastes into Notes (or
    /// anywhere) as a list.
    func shoppingListText(for prep: MealPrep, plan: MealPrepPlan) -> String {
        let lines = plan.shoppingList.map { requirement in
            let food = requirement.food
            let name = food.brand.map { "\(food.name) (\($0))" } ?? food.name
            return "- \(name): \(PantryFormat.amount(requirement.toBuy, unit: food.unit.baseUnit))"
        }
        return (["Lista de Compras · \(prep.name)", ""] + lines).joined(separator: "\n")
    }
}

/// Amounts in the stock, in base units, as people read them: "350 g", "1,2 kg", "2 unidades".
enum PantryFormat {
    static func amount(_ value: Double, unit: MeasurementUnit) -> String {
        switch unit.baseUnit {
        case .unit:
            return "\(number(value)) \(value == 1 ? "unidade" : "unidades")"
        case .milliliter:
            return value >= 1000 ? "\(large(value / 1000)) L" : "\(number(value)) ml"
        default:
            return value >= 1000 ? "\(large(value / 1000)) kg" : "\(number(value)) g"
        }
    }

    /// "758,8" — one decimal at most, in the user's locale (like the kg/L amounts).
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// For a text field the app parses back: "1000", "12.5" (no grouping, dot decimal).
    static func plainNumber(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(rounded)) : String(rounded)
    }

    static func percent(_ value: Double) -> String {
        let number = number(abs(value))
        return value > 0 ? "+\(number)%" : value < 0 ? "−\(number)%" : "0%"
    }

    private static func large(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

// MARK: - Food categories (two levels) and preparations

extension DataStore {
    /// The top-level categories, each followed by its subcategories (the catalog's order).
    var orderedFoodCategories: [FoodCategory] {
        let top = foodCategories.filter { $0.parentID == nil || category(withID: $0.parentID) == nil }
        return top.flatMap { parent in [parent] + foodCategories.filter { $0.parentID == parent.id } }
    }

    private func category(withID id: UUID?) -> FoodCategory? {
        guard let id else { return nil }
        return foodCategories.first { $0.id == id }
    }

    var topLevelFoodCategories: [FoodCategory] {
        foodCategories.filter { $0.parentID == nil || category(withID: $0.parentID) == nil }
    }

    func subcategories(of category: FoodCategory) -> [FoodCategory] {
        foodCategories.filter { $0.parentID == category.id }
    }

    /// "Proteína · Carne" for a subcategory, the name for a top-level one.
    func categoryTitle(_ category: FoodCategory) -> String {
        if let parent = self.category(withID: category.parentID) { return "\(parent.name) · \(category.name)" }
        return category.name
    }

    /// The preparations (subgroups) of a raw food, in the methods' order.
    func preparations(of food: FoodItem) -> [FoodItem] {
        foodItems
            .filter { $0.baseFoodID == food.id }
            .sorted { ($0.preparation.flatMap { FoodPreparation.allCases.firstIndex(of: $0) } ?? 99)
                < ($1.preparation.flatMap { FoodPreparation.allCases.firstIndex(of: $0) } ?? 99) }
    }

    func baseFood(of food: FoodItem) -> FoodItem? {
        guard let id = food.baseFoodID else { return nil }
        return foodItems.first { $0.id == id }
    }

    /// The weight change to start a preparation with: the reference for the raw food's name and
    /// this method, else its usual one, else 0.
    func suggestedWeightChange(for base: FoodItem, method: FoodPreparation) -> (percent: Double, reference: CookingYield?) {
        guard method != .raw else { return (0, nil) }
        if let reference = CookingYield.reference(for: base.nameWithoutRawMarker, method: method, in: cookingYields) {
            return (reference.weightChange, reference)
        }
        return (base.cookingWeightChange ?? 0, nil)
    }
}
