import Foundation

// The food stock ("Despensa") and meal prep ("Marmitas"): what's at home, where, until when, and
// what a batch of meal-prep boxes needs. Athlete-only everywhere: backed up to `app_documents`
// and sent as typed rows (pantry_locations, pantry_lots, cooking_yields, meal_preps); the dashboard
// edits the same records (its /dashboard/pantry and /dashboard/meal-prep pages).

/// A place food is kept (e.g. "Despensa", "Frigorífico", "Congelador"). Separate from the
/// supplements' `StockLocation`s: food and supplements are rarely kept in the same places.
struct PantryLocation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
}

/// One batch of a catalog food in stock: what came in at once, at one location, with its own
/// expiry date — so two packs bought on different days keep their own dates.
struct PantryLot: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var foodItemID: UUID
    var locationID: UUID
    /// What's left, in the food's base unit (g, ml or units).
    var remaining: Double
    var addedAt: Date = Date()
    /// The day it expires (`nil` = doesn't, e.g. salt).
    var expiresOn: Date?
}

/// How much a food's weight changes when cooked, as a percentage of its raw weight: rice
/// +160 (100 g raw → 260 g cooked), chicken breast −25. A reference value for every food whose
/// name has all the words of `name`; a food can override it (`FoodItem.cookingWeightChange`).
/// With `method` it's the value for that way of cooking (Frango grelhado −25, estufado −22); without,
/// the usual one — used for raw foods in meal prep and when no value exists for the method.
struct CookingYield: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var weightChange: Double
    var method: FoodPreparation?

    /// Common foods in sports diets, raw → cooked (boiled, grilled or roasted as usually done for
    /// meal prep). Approximate values from food-composition yield tables; adjustable in the app.
    static let defaults: [CookingYield] = [
        CookingYield(name: "Arroz", weightChange: 160),
        CookingYield(name: "Arroz Integral", weightChange: 150),
        CookingYield(name: "Arroz Basmati", weightChange: 170),
        CookingYield(name: "Massa", weightChange: 125),
        CookingYield(name: "Massa Integral", weightChange: 110),
        CookingYield(name: "Esparguete", weightChange: 125),
        CookingYield(name: "Quinoa", weightChange: 170),
        CookingYield(name: "Cuscuz", weightChange: 150),
        CookingYield(name: "Bulgur", weightChange: 150),
        CookingYield(name: "Lentilhas", weightChange: 150),
        CookingYield(name: "Grão", weightChange: 140),
        CookingYield(name: "Feijão", weightChange: 150),
        CookingYield(name: "Batata", weightChange: 0),
        CookingYield(name: "Batata Doce", weightChange: -20),
        CookingYield(name: "Frango", weightChange: -25),
        CookingYield(name: "Peru", weightChange: -25),
        CookingYield(name: "Vaca", weightChange: -28),
        CookingYield(name: "Carne Picada", weightChange: -30),
        CookingYield(name: "Porco", weightChange: -28),
        CookingYield(name: "Salmão", weightChange: -20),
        CookingYield(name: "Pescada", weightChange: -20),
        CookingYield(name: "Bacalhau", weightChange: -20),
        CookingYield(name: "Brócolos", weightChange: -10),
        CookingYield(name: "Cogumelos", weightChange: -40),
        CookingYield(name: "Espinafres", weightChange: -50),
        CookingYield(name: "Ovo", weightChange: 0)
    ] + byMethod

    /// Per way of cooking, for the foods where it makes a difference (approximate, adjustable).
    private static let byMethod: [CookingYield] = [
        ("Frango", [(FoodPreparation.grilled, -25.0), (.roasted, -28), (.boiled, -20), (.stewed, -22), (.steamed, -18), (.fried, -30)]),
        ("Peru", [(.grilled, -25), (.roasted, -28), (.boiled, -20), (.stewed, -22)]),
        ("Vaca", [(.grilled, -28), (.roasted, -30), (.stewed, -35), (.boiled, -30)]),
        ("Porco", [(.grilled, -28), (.roasted, -30), (.stewed, -32)]),
        ("Salmão", [(.grilled, -20), (.roasted, -20), (.steamed, -12), (.boiled, -15)]),
        ("Pescada", [(.boiled, -15), (.steamed, -12), (.grilled, -20), (.roasted, -20)]),
        ("Bacalhau", [(.boiled, -10), (.roasted, -15), (.grilled, -15)]),
        ("Batata", [(.boiled, 0), (.roasted, -25), (.fried, -40)]),
        ("Batata Doce", [(.boiled, 0), (.roasted, -20)]),
        ("Brócolos", [(.boiled, -5), (.steamed, -5), (.roasted, -30)]),
        ("Ovo", [(.boiled, 0), (.fried, -10)]),
        ("Cogumelos", [(.grilled, -40), (.stewed, -45), (.roasted, -40)]),
        ("Espinafres", [(.boiled, -50), (.steamed, -40)])
    ].flatMap { name, values in values.map { CookingYield(name: name, weightChange: $0.1, method: $0.0) } }

    /// Words saying a food is already cooked or ready to eat ("Arroz Cozido", "Frango Grelhado",
    /// "Grão em Conserva"): its weight doesn't change any more, so no reference applies.
    static let readyWords: Set<String> = [
        "cozido", "cozida", "cozidos", "cozidas", "cozinhado", "cozinhada", "cozinhados", "cozinhadas",
        "grelhado", "grelhada", "grelhados", "grelhadas", "assado", "assada", "assados", "assadas",
        "frito", "frita", "fritos", "fritas", "estufado", "estufada", "conserva", "enlatado", "enlatada",
        // Ready-to-eat products made from a food ("Bolachas de Arroz", "Flocos de Aveia", "Bebida de Arroz").
        "bolacha", "bolachas", "tosta", "tostas", "flocos", "farinha", "bebida", "leite", "pao", "barra", "barras",
        "crackers", "galetes", "wraps", "tortilhas"
    ]

    /// The most specific reference matching `foodName` (the one with the most words): "Arroz
    /// Integral Cigala" takes "Arroz Integral", not "Arroz". Words match whole, ignoring case/accents.
    /// With `method`, a value for that method wins over the usual one for the same words.
    /// None for foods whose name says they're already cooked (`readyWords`).
    static func reference(for foodName: String, method: FoodPreparation? = nil, in yields: [CookingYield]) -> CookingYield? {
        let foodWords = Set(words(foodName))
        guard foodWords.isDisjoint(with: readyWords) else { return nil }
        return yields
            .filter { yield in
                let needed = words(yield.name)
                return !needed.isEmpty && needed.allSatisfy(foodWords.contains)
                    && (yield.method == nil || (method != nil && yield.method == method))
            }
            .max { a, b in
                let (wa, wb) = (words(a.name).count, words(b.name).count)
                return wa != wb ? wa < wb : (a.method == nil && b.method != nil)
            }
    }

    private static func words(_ text: String) -> [String] {
        SearchMatch.normalized(text)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}

/// A batch of meal-prep boxes ("marmitas") planned from recipes: how many boxes of each and how
/// much cooked food goes in each one, and the stock it's cooked from.
struct MealPrep: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var items: [MealPrepItem]
    /// The stock it's checked against and taken from (`nil` = every location).
    var locationID: UUID?
    var createdAt: Date = Date()
    /// When it was marked as cooked (the ingredients were taken from the stock then).
    var cookedAt: Date?
}

struct MealPrepItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var recipeID: UUID
    var boxes: Int
    /// Grams of cooked food per box (`nil` = one portion of the recipe as it is).
    var cookedWeightPerBox: Double?
}
