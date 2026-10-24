#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import AppIntents
import Foundation

/// A meal planned on the week board, as a Live Activity (Dynamic Island + Lock Screen) when its
/// time comes. Compiled into the app and into the MealActivity widget extension.
nonisolated struct MealActivityAttributes: ActivityAttributes, Hashable {
    nonisolated struct ContentState: Codable, Hashable {
        /// Still to confirm; the activity is ended once it's eaten or refused.
        var isPending: Bool = true
    }

    /// `MealBoardPlacement.id`.
    var placementID: String
    var recipeName: String
    var mealName: String
    var mealSymbol: String
    var time: Date
    var kcal: Int
    /// "P 35 · C 60 · G 15".
    var macros: String
}

/// What the activity's buttons do. Live Activity intents run in the app's process, so the app sets
/// this when it starts; the extension never runs them (it only draws the activity).
@MainActor
enum MealActivityActions {
    static var confirm: ((String) -> Void)?
    static var refuse: ((String) -> Void)?
}

/// "Comi": logs the planned meal with the board's amounts, without opening the app.
struct ConfirmPlannedMealIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Comi"
    static let isDiscoverable = false

    @Parameter(title: "Refeição") var placementID: String

    init() {}
    init(placementID: String) { self.placementID = placementID }

    func perform() async throws -> some IntentResult {
        let id = placementID
        await MainActor.run { MealActivityActions.confirm?(id) }
        return .result()
    }
}

/// "Recusar": opens the app on "what did you eat instead".
struct RefusePlannedMealIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Recusar"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Refeição") var placementID: String

    init() {}
    init(placementID: String) { self.placementID = placementID }

    func perform() async throws -> some IntentResult {
        let id = placementID
        await MainActor.run { MealActivityActions.refuse?(id) }
        return .result()
    }
}
#endif
