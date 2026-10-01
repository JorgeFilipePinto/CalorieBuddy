import Foundation

// MARK: - Lenient enum parsing
//
// AI-generated JSON won't always spell these exactly like the app's own raw values (e.g. "g"
// instead of "gram", or a Portuguese word), so these are parsed leniently instead of relying on
// `MeasurementUnit`/`NutritionBasis`/`MealType`'s own strict `Codable` conformance.

private func normalized(_ raw: String) -> String {
    raw.folding(options: .diacriticInsensitive, locale: .current)
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "-", with: "")
}

private func parseMeasurementUnit(_ raw: String?) -> MeasurementUnit {
    guard let raw else { return .gram }
    switch normalized(raw) {
    case "g", "gram", "grams", "grama", "gramas": return .gram
    case "kg", "kilogram", "kilograms", "quilograma", "quilo", "quilos": return .kilogram
    case "ml", "milliliter", "milliliters", "millilitre", "mililitro", "mililitros": return .milliliter
    case "l", "liter", "liters", "litre", "litro", "litros": return .liter
    case "unit", "units", "unidade", "unidades", "un", "pcs", "piece", "pieces": return .unit
    default: return .gram
    }
}

private func parseNutritionBasis(_ raw: String?) -> NutritionBasis {
    guard let raw else { return .per100 }
    switch normalized(raw) {
    case "perdose", "dose", "pordose": return .perDose
    default: return .per100
    }
}

// MARK: - Import payloads
//
// Deliberately separate from `FoodItem`/`Recipe`/`FoodEntry` themselves: those use custom
// decoders tuned for the app's own exported JSON (requiring an `id`, etc.), which is more
// rigid than what's reasonable to expect back from an AI assistant. These payloads only need
// what an AI can reasonably be asked to fill in, and are converted into real models afterwards.

struct NutrientImportPayload: Codable {
    var name: String
    var amount: Double
    var unit: String

    func makeNutrientValue() -> NutrientValue {
        NutrientValue(
            name: name.trimmingCharacters(in: .whitespaces),
            amount: amount,
            unit: unit.trimmingCharacters(in: .whitespaces)
        )
    }
}

struct FoodImportPayload: Codable {
    var name: String
    var brand: String?
    var unit: String?
    var doseSize: Double?
    var nutritionBasis: String?
    var calories: Int
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var minerals: [NutrientImportPayload]?
    var vitamins: [NutrientImportPayload]?

    var resolvedUnit: MeasurementUnit { parseMeasurementUnit(unit) }
    var resolvedNutritionBasis: NutritionBasis { parseNutritionBasis(nutritionBasis) }

    func makeFoodItem() -> FoodItem {
        let trimmedBrand = brand?.trimmingCharacters(in: .whitespaces)
        return FoodItem(
            name: name.trimmingCharacters(in: .whitespaces),
            brand: (trimmedBrand?.isEmpty ?? true) ? nil : trimmedBrand,
            unit: resolvedUnit,
            doseSize: doseSize ?? 100,
            nutritionBasis: resolvedNutritionBasis,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            minerals: (minerals ?? []).map { $0.makeNutrientValue() },
            vitamins: (vitamins ?? []).map { $0.makeNutrientValue() }
        )
    }
}

struct RecipeItemImportPayload: Codable {
    var food: FoodImportPayload
    var quantity: Double?
}

struct RecipeImportPayload: Codable {
    var name: String?
    var items: [RecipeItemImportPayload]
}

/// The `groupName`/`mealType` that used to live inside this payload are now entered directly in
/// the import sheet's UI (a required text field and a picker) instead, so the JSON copied to/from
/// the AI only needs to carry what it actually can't get any other way: the nutrition data.
struct DiaryEntryImportPayload: Codable {
    var name: String
    var calories: Int
    var protein: Double?
    var carbs: Double?
    var fat: Double?
}

// MARK: - Decoding

enum AIImportError: LocalizedError {
    case invalidJSON
    case empty

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Este texto não corresponde ao formato esperado. Confirma que colaste o JSON completo devolvido pela IA."
        case .empty:
            return "O JSON não contém nenhum item."
        }
    }
}

/// Parses JSON pasted from an external AI assistant into the app's models. Tries a couple of
/// reasonably-shaped alternatives (a bare object, a bare array, a wrapper object) since AI output
/// isn't always wrapped exactly the way the example schema shows.
enum AIJSONImport {
    private static let decoder = JSONDecoder()

    private static func data(from json: String) throws -> Data {
        guard let data = json.data(using: .utf8) else { throw AIImportError.invalidJSON }
        return data
    }

    static func decodeFoodItems(from json: String) throws -> [FoodImportPayload] {
        let data = try data(from: json)
        if let array = try? decoder.decode([FoodImportPayload].self, from: data), !array.isEmpty {
            return array
        }
        if let single = try? decoder.decode(FoodImportPayload.self, from: data) {
            return [single]
        }
        throw AIImportError.invalidJSON
    }

    static func decodeRecipe(from json: String) throws -> RecipeImportPayload {
        let data = try data(from: json)
        if let payload = try? decoder.decode(RecipeImportPayload.self, from: data), !payload.items.isEmpty {
            return payload
        }
        if let items = try? decoder.decode([RecipeItemImportPayload].self, from: data), !items.isEmpty {
            return RecipeImportPayload(name: nil, items: items)
        }
        throw AIImportError.invalidJSON
    }

    static func decodeDiaryEntries(from json: String) throws -> [DiaryEntryImportPayload] {
        let data = try data(from: json)
        if let array = try? decoder.decode([DiaryEntryImportPayload].self, from: data), !array.isEmpty {
            return array
        }
        if let single = try? decoder.decode(DiaryEntryImportPayload.self, from: data) {
            return [single]
        }
        throw AIImportError.invalidJSON
    }
}

// MARK: - Example schemas shown/copied in the import sheets

extension AIJSONImport {
    static let foodExample = """
    {
      "name": "Peito de frango grelhado",
      "brand": "Continente",
      "unit": "gram",
      "doseSize": 100,
      "nutritionBasis": "per100",
      "calories": 165,
      "protein": 31,
      "carbs": 0,
      "fat": 3.6,
      "minerals": [
        { "name": "Sódio", "amount": 74, "unit": "mg" }
      ],
      "vitamins": []
    }
    """

    static let recipeExample = """
    {
      "name": "Bowl de frango com arroz",
      "items": [
        {
          "food": {
            "name": "Peito de frango grelhado",
            "unit": "gram",
            "doseSize": 100,
            "nutritionBasis": "per100",
            "calories": 165,
            "protein": 31,
            "carbs": 0,
            "fat": 3.6
          },
          "quantity": 1.5
        },
        {
          "food": {
            "name": "Arroz cozido",
            "unit": "gram",
            "doseSize": 100,
            "nutritionBasis": "per100",
            "calories": 130,
            "protein": 2.7,
            "carbs": 28,
            "fat": 0.3
          },
          "quantity": 2
        }
      ]
    }
    """

    static let diaryExample = """
    [
      {
        "name": "Hambúrguer de vaca",
        "calories": 540,
        "protein": 28,
        "carbs": 32,
        "fat": 32
      },
      {
        "name": "Batata frita",
        "calories": 310,
        "protein": 4,
        "carbs": 38,
        "fat": 16
      }
    ]
    """
}
