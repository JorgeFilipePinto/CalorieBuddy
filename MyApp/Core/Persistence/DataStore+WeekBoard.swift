import Foundation

/// Calories and macros on the week board.
struct BoardTotals: Equatable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    static func + (lhs: BoardTotals, rhs: BoardTotals) -> BoardTotals {
        BoardTotals(calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein,
                    carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat)
    }
}

/// How close a value is to its target: under (< 90 %), on (90–110 %), over (> 110 %) — the
/// dashboard's `targetStatus`.
enum TargetStatus {
    case none, under, on, over

    init(value: Double, target: Double?) {
        guard let target, target > 0 else { self = .none; return }
        let ratio = value / target
        self = ratio < 0.9 ? .under : ratio > 1.1 ? .over : .on
    }
}

extension DataStore {
    /// What one placed recipe adds up to with its own amounts (foods no longer in the catalog left out).
    func nutrition(of placement: MealBoardPlacement) -> BoardTotals {
        guard let recipe = recipe(withID: placement.recipeID) else { return BoardTotals() }
        return recipe.items.reduce(BoardTotals()) { sum, item in
            let doses = placement.doses(of: item)
            guard doses > 0, let food = foodItems.first(where: { $0.id == item.foodItemID }) else { return sum }
            let n = food.nutrition(quantity: doses)
            return sum + BoardTotals(calories: n.calories, protein: n.protein ?? 0, carbs: n.carbs ?? 0, fat: n.fat ?? 0)
        }
    }

    func boardTotals(day: String, meal: MealType? = nil) -> BoardTotals {
        mealBoardPlacements
            .filter { $0.day == day && (meal == nil || $0.meal == meal) }
            .reduce(BoardTotals()) { $0 + nutrition(of: $1) }
    }

    func placements(day: String, meal: MealType) -> [MealBoardPlacement] {
        mealBoardPlacements.filter { $0.day == day && $0.meal == meal }
    }

    /// A board meal's target (nutrition plan's split for the kind of day, else the meal plan).
    func boardMealTarget(day date: Date, meal: MealType, dayType: DayType) -> BoardMealTarget? {
        WeekBoard.mealTarget(meal: meal, dayType: dayType, plan: nutritionPlan(on: date), mealPlan: mealPlan(on: date))
    }
}
