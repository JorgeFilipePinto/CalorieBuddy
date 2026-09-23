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

/// A reusable food definition (e.g. from the catalog or a barcode scan) that can be logged
/// directly, or combined with others into a `Recipe`.
struct FoodItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// Calories for one serving, as described by `servingLabel`.
    var calories: Int
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var servingLabel: String
    var barcode: String?
}

/// One food item and how many servings of it a recipe uses.
struct RecipeItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var foodItemID: UUID
    var quantity: Double
}

/// A named group of previously-catalogued foods, so a whole meal can be logged in one action.
struct Recipe: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var items: [RecipeItem]
}

struct UserSettings: Codable, Equatable {
    var dailyCalorieGoal: Int
    var proteinGoal: Double?
    var carbsGoal: Double?
    var fatGoal: Double?

    static let `default` = UserSettings(dailyCalorieGoal: 2000, proteinGoal: nil, carbsGoal: nil, fatGoal: nil)
}

/// The full contents of a CalorieBuddy database, as exported/imported via JSON.
///
/// Uses a custom decoder so that databases exported before `foodItems`/`recipes` existed
/// (version 1) still import cleanly, with those collections defaulting to empty.
struct AppDatabase: Codable {
    static let currentVersion = 2

    var version: Int
    var exportedAt: Date
    var settings: UserSettings
    var entries: [FoodEntry]
    var foodItems: [FoodItem]
    var recipes: [Recipe]

    init(version: Int, exportedAt: Date, settings: UserSettings, entries: [FoodEntry], foodItems: [FoodItem], recipes: [Recipe]) {
        self.version = version
        self.exportedAt = exportedAt
        self.settings = settings
        self.entries = entries
        self.foodItems = foodItems
        self.recipes = recipes
    }

    private enum CodingKeys: String, CodingKey {
        case version, exportedAt, settings, entries, foodItems, recipes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        settings = try container.decode(UserSettings.self, forKey: .settings)
        entries = try container.decode([FoodEntry].self, forKey: .entries)
        foodItems = try container.decodeIfPresent([FoodItem].self, forKey: .foodItems) ?? []
        recipes = try container.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
    }
}
