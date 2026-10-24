import Foundation
import Observation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// Where a tap on a Live Activity's "Recusar" leads: the day's "what did you eat instead" sheet.
@Observable
final class MealActivityRouter {
    static let shared = MealActivityRouter()
    /// The planned meal to refuse, set by the Live Activity; `ContentView` shows the sheet.
    var refusing: MealBoardPlacement?
}

/// Planned meals with a time become Live Activities (Dynamic Island + Lock Screen) at that time,
/// scheduled on the device — no server push, so it works with a free developer account. Each is
/// ended once the meal is eaten or refused (here, on the dashboard or from the activity itself),
/// moved or unscheduled. Rescheduled whenever the board changes and when the app opens.
enum MealLiveActivities {
    /// How far ahead activities are scheduled, and how long one stays after its time.
    private static let horizon: TimeInterval = 36 * 3600
    private static let staleAfter: TimeInterval = 3 * 3600

    /// Hooks the activity's buttons to the store (they run in the app's process).
    static func connect(store: DataStore) {
        #if canImport(ActivityKit) && os(iOS)
        MealActivityActions.confirm = { id in
            guard let placement = store.mealBoardPlacements.first(where: { $0.id.uuidString == id }) else { return }
            if store.state(of: placement) != .consumed { store.confirmPlacement(placement) }
            reschedule(store: store)
        }
        MealActivityActions.refuse = { id in
            MealActivityRouter.shared.refusing = store.mealBoardPlacements.first { $0.id.uuidString == id }
        }
        #endif
    }

    static func reschedule(store: DataStore) {
        #if canImport(ActivityKit) && os(iOS)
        let now = Date.now
        // What should be showing or scheduled: still to confirm, with a time not long past.
        var wanted: [String: (placement: MealBoardPlacement, attributes: MealActivityAttributes)] = [:]
        for placement in store.mealBoardPlacements where store.state(of: placement) == .planned {
            guard let date = WeekBoard.plannedDate(of: placement),
                  date > now.addingTimeInterval(-staleAfter), date < now.addingTimeInterval(horizon),
                  let recipe = store.recipe(withID: placement.recipeID) else { continue }
            let totals = store.nutrition(of: placement)
            wanted[placement.id.uuidString] = (placement, MealActivityAttributes(
                placementID: placement.id.uuidString,
                recipeName: recipe.name,
                mealName: placement.meal.displayName,
                mealSymbol: placement.meal.symbolName,
                time: date,
                kcal: Int(totals.calories.rounded()),
                macros: "P \(Int(totals.protein.rounded())) · C \(Int(totals.carbs.rounded())) · G \(Int(totals.fat.rounded()))"
            ))
        }

        // End what's no longer wanted (eaten, refused, moved, renamed…); keep the rest.
        var kept = Set<String>()
        for activity in Activity<MealActivityAttributes>.activities {
            let id = activity.attributes.placementID
            if let match = wanted[id], match.attributes == activity.attributes, !kept.contains(id) {
                kept.insert(id)
            } else {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for (id, item) in wanted where !kept.contains(id) {
            let content = ActivityContent(state: MealActivityAttributes.ContentState(),
                                          staleDate: item.attributes.time.addingTimeInterval(staleAfter))
            do {
                if item.attributes.time > now.addingTimeInterval(60) {
                    let alert = AlertConfiguration(
                        title: "\(item.placement.meal.displayName): \(item.attributes.recipeName)",
                        body: "Confirma se comeste.",
                        sound: .default
                    )
                    _ = try Activity.request(attributes: item.attributes, content: content, pushType: nil,
                                             style: .standard, alertConfiguration: alert, start: item.attributes.time)
                } else {
                    _ = try Activity.request(attributes: item.attributes, content: content, pushType: nil)
                }
            } catch {
                // Too many activities, or not allowed right now: tried again on the next change/open.
            }
        }
        #endif
    }
}
