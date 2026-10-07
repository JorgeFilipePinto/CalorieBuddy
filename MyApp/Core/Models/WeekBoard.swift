import Foundation

/// One recipe placed on the week board ("Quadro Semanal"): a day, a meal, and its own amounts.
/// The same JSON as the dashboard's board (`Dashboard/src/lib/athlete/week-board.ts`).
struct MealBoardPlacement: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// Lisbon day, "yyyy-MM-dd".
    var day: String
    var meal: MealType
    var recipeID: UUID
    /// Doses per recipe item (its `RecipeItem.id.uuidString`); an item missing here uses the
    /// recipe's own amount, 0 leaves it out. Only this placement — the recipe isn't changed.
    var doses: [String: Double] = [:]

    func doses(of item: RecipeItem) -> Double {
        doses[item.id.uuidString] ?? item.quantity
    }

    func isAdjusted(from recipe: Recipe) -> Bool {
        recipe.items.contains { item in
            doses[item.id.uuidString].map { abs($0 - item.quantity) > 1e-9 } ?? false
        }
    }
}

/// Training or rest, as chosen on the week board for one day (otherwise worked out from the
/// day's workouts).
struct MealBoardDay: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// Lisbon day, "yyyy-MM-dd".
    var day: String
    var dayType: DayType
}

/// What a nutrition plan expects at one meal: protein / carbs / fat (each optional) and food
/// suggestions. Stored per day type and meal in `NutritionPlan.meals` (table nutrition_plan_meals).
struct PlanMealTargets: Codable, Equatable {
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var notes: String?

    var hasMacros: Bool { proteinG != nil || carbsG != nil || fatG != nil }
    var isEmpty: Bool { !hasMacros && (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// kcal implied by the macros (4/4/9), `nil` without any.
    var kcal: Int? {
        guard hasMacros else { return nil }
        return Int(((proteinG ?? 0) * 4 + (carbsG ?? 0) * 4 + (fatG ?? 0) * 9).rounded())
    }
}

extension NutritionPlan {
    /// The meal's targets for a kind of day, if the plan has any.
    func meal(_ meal: MealType, on dayType: DayType) -> PlanMealTargets? {
        meals[dayType.rawValue]?[meal.rawValue]
    }

    /// Every meal the plan splits a kind of day into.
    func meals(on dayType: DayType) -> [MealType: PlanMealTargets] {
        var result: [MealType: PlanMealTargets] = [:]
        for (key, value) in meals[dayType.rawValue] ?? [:] {
            if let meal = MealType(rawValue: key) { result[meal] = value }
        }
        return result
    }

    /// Whether the plan has a split per meal for that kind of day.
    func hasMealSplit(on dayType: DayType) -> Bool {
        !(meals[dayType.rawValue] ?? [:]).isEmpty
    }

    /// Sets (or, when empty, removes) a meal's targets.
    mutating func setMeal(_ meal: MealType, on dayType: DayType, to targets: PlanMealTargets?) {
        var day = meals[dayType.rawValue] ?? [:]
        if let targets, !targets.isEmpty { day[meal.rawValue] = targets } else { day[meal.rawValue] = nil }
        meals[dayType.rawValue] = day.isEmpty ? nil : day
    }

    /// What the split per meal adds up to (protein, carbs, fat in g; kcal 4/4/9).
    func mealSplitTotals(on dayType: DayType) -> (protein: Double, carbs: Double, fat: Double, kcal: Int) {
        let values = meals(on: dayType).values
        let protein = values.reduce(0) { $0 + ($1.proteinG ?? 0) }
        let carbs = values.reduce(0) { $0 + ($1.carbsG ?? 0) }
        let fat = values.reduce(0) { $0 + ($1.fatG ?? 0) }
        return (protein, carbs, fat, Int((protein * 4 + carbs * 4 + fat * 9).rounded()))
    }
}

/// A meal's target on the week board — the dashboard's `boardMealTarget`: when the nutrition plan
/// in effect has a split per meal for that kind of day, the whole day follows it (a meal it leaves
/// empty has no target); otherwise the meal plan's targets. The meal plan's recipes stay suggested.
struct BoardMealTarget: Equatable {
    var name: String
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var notes: String?
    var suggestedRecipeIDs: Set<UUID> = []
    var fromNutritionPlan: Bool

    var hasMacros: Bool { protein != nil || carbs != nil || fat != nil }
    var kcal: Int? {
        guard hasMacros else { return nil }
        return Int(((protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9).rounded())
    }
}

enum WeekBoard {
    /// "yyyy-MM-dd" in Lisbon, the board's day key (same as the dashboard).
    nonisolated static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Lisbon")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    nonisolated static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }
    nonisolated static func date(of key: String) -> Date? { dayFormatter.date(from: key) }

    /// Monday of `date`'s week.
    static func monday(of date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon") ?? .current
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func weekDays(from monday: Date) -> [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: monday) }
    }

    static func mealTarget(meal: MealType, dayType: DayType, plan: NutritionPlan?, mealPlan: MealPlan?) -> BoardMealTarget? {
        let planned = mealPlan?.meals.filter { $0.mealType == meal } ?? []
        let suggested = Set(planned.flatMap { $0.options.compactMap(\.recipeID) })
        if let plan, plan.hasMealSplit(on: dayType) {
            let split = plan.meal(meal, on: dayType)
            return BoardMealTarget(name: "Plano nutricional: \(plan.name)", protein: split?.proteinG, carbs: split?.carbsG,
                                   fat: split?.fatG, notes: split?.notes, suggestedRecipeIDs: suggested, fromNutritionPlan: true)
        }
        guard !planned.isEmpty else { return nil }
        func sum(_ value: (PlannedMeal) -> Double?) -> Double? {
            let values = planned.compactMap(value)
            return values.isEmpty ? nil : values.reduce(0, +)
        }
        return BoardMealTarget(name: planned.map(\.name).joined(separator: " + "), protein: sum(\.proteinTarget),
                               carbs: sum(\.carbsTarget), fat: sum(\.fatTarget), suggestedRecipeIDs: suggested,
                               fromNutritionPlan: false)
    }
}
