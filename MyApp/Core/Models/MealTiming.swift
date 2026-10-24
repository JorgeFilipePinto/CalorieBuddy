import Foundation

/// Training or rest for a day, and a plan's meals set to when the workout is — the dashboard's
/// `meal-timing.ts`, with the same rules.
enum MealTiming {
    /// A workout detected on the day always makes it a training day (even when the board said
    /// rest — the day happened that way); otherwise the board's choice, else rest.
    static func dayType(hasWorkout: Bool, chosen: DayType?) -> DayType {
        hasWorkout ? .training : (chosen ?? .rest)
    }

    /// A workout's span in minutes after midnight (Lisbon); `end` may pass 1440.
    struct Span: Equatable {
        var start: Int
        var end: Int

        init(start: Int, end: Int) {
            self.start = start
            self.end = end
        }

        init(startDate: Date, duration: TimeInterval) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Lisbon") ?? .current
            let parts = calendar.dateComponents([.hour, .minute], from: startDate)
            let start = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            self.init(start: start, end: start + max(0, Int((duration / 60).rounded())))
        }
    }

    /// "HH:mm" → minutes after midnight; nil when it isn't a time.
    static func minutes(_ clock: String?) -> Int? {
        guard let clock else { return nil }
        let parts = clock.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// "HH:mm" for a Date, as a time-picker value.
    static func clock(from date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func date(fromClock clock: String?) -> Date? {
        guard let total = minutes(clock) else { return nil }
        return Calendar.current.date(bySettingHour: total / 60, minute: total % 60, second: 0, of: .now)
    }

    private static func window(of targets: PlanMealTargets?) -> (start: Int, end: Int)? {
        guard let start = minutes(targets?.startsAt), var end = minutes(targets?.endsAt) else { return nil }
        if end < start { end += 1440 }
        return (start, end)
    }

    /// Swaps what two meals expect (macros and suggestions); each keeps its own time window.
    private static func swap(_ meals: inout [MealType: PlanMealTargets], _ a: MealType, _ b: MealType) {
        let first = meals[a] ?? PlanMealTargets()
        let second = meals[b] ?? PlanMealTargets()
        func take(_ from: PlanMealTargets, into base: PlanMealTargets) -> PlanMealTargets {
            var next = base
            next.proteinG = from.proteinG
            next.carbsG = from.carbsG
            next.fatG = from.fatG
            next.notes = from.notes
            return next
        }
        meals[a] = take(second, into: first)
        meals[b] = take(first, into: second)
    }

    struct TimedSplit {
        var meals: [MealType: PlanMealTargets]
        /// The meals standing in for the pre- and post-workout slots today (nil = the slot's own meal).
        var pre: MealType?
        var post: MealType?
    }

    /// A training day's split per meal, set to when the workout is: the meal whose window ends last
    /// before the workout starts becomes the pre-workout meal, the one whose window starts first
    /// after it ends the post-workout one, and each swaps what it expects with the plan's slot, so
    /// the day still adds up to the same. Meals without a window never move; without a workout
    /// time, or windows, nothing changes.
    static func split(_ split: [MealType: PlanMealTargets], workout: Span?) -> TimedSplit {
        var meals = split
        var result = TimedSplit(meals: meals)
        guard let workout else { return result }
        let windowed = split.compactMap { meal, targets in window(of: targets).map { (meal: meal, start: $0.start, end: $0.end) } }

        if split[.preWorkout] != nil {
            let pre = windowed
                .filter { $0.meal != .postWorkout && $0.end <= workout.start }
                .sorted { ($0.end, $0.start) > ($1.end, $1.start) }
                .first
            if let pre, pre.meal != .preWorkout {
                swap(&meals, .preWorkout, pre.meal)
                result.pre = pre.meal
            }
        }
        if split[.postWorkout] != nil {
            let post = windowed
                .filter { $0.meal != .preWorkout && $0.meal != result.pre && $0.start >= workout.end }
                .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
                .first
            if let post, post.meal != .postWorkout {
                swap(&meals, .postWorkout, post.meal)
                result.post = post.meal
            }
        }
        result.meals = meals
        return result
    }

    // MARK: Meals in the order they happened

    /// The usual time of each meal, in minutes after midnight (the dashboard's `APP_MEAL_TIMES`).
    private static let usualMinutes: [MealType: Int] = [
        .breakfast: 8 * 60, .morningSnack: 10 * 60 + 30, .preWorkout: 17 * 60 + 30, .postWorkout: 19 * 60 + 30,
        .lunch: 13 * 60, .snack: 16 * 60 + 30, .dinner: 20 * 60 + 30, .supper: 22 * 60 + 30
    ]

    /// The meals of a day in the order they happened: each meal sits where its earliest logged food is
    /// (a pre-workout snack lands before lunch or after it, whenever the training was). A meal with
    /// only planned items goes by the planned time, else by its usual time; ties keep the diary's order.
    static func orderedMeals(entries: [FoodEntry], planned: [MealBoardPlacement]) -> [MealType] {
        let calendar = Calendar.current
        var key: [MealType: Int] = [:]
        for entry in entries {
            let minutes = calendar.component(.hour, from: entry.date) * 60 + calendar.component(.minute, from: entry.date)
            key[entry.mealType] = min(key[entry.mealType] ?? .max, minutes)
        }
        for placement in planned where key[placement.meal] == nil {
            key[placement.meal] = minutes(placement.time) ?? usualMinutes[placement.meal] ?? 0
        }
        let order = MealType.allCases
        return order.sorted { a, b in
            let ka = key[a] ?? usualMinutes[a] ?? 0
            let kb = key[b] ?? usualMinutes[b] ?? 0
            return ka != kb ? ka < kb : (order.firstIndex(of: a) ?? 0) < (order.firstIndex(of: b) ?? 0)
        }
    }
}
