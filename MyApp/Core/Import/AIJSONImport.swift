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

// MARK: - Lenient number parsing
//
// AI output sometimes quotes numbers ("12.5"), uses a decimal comma ("12,5") or gives a decimal
// where an integer is expected (165.5 kcal) — none of which is worth rejecting the whole import for.

private extension KeyedDecodingContainer {
    func lenientDouble(forKey key: Key) throws -> Double? {
        if try !contains(key) || decodeNil(forKey: key) { return nil }
        if let number = try? decode(Double.self, forKey: key) { return number }
        let text = try decode(String.self, forKey: key)
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let number = Double(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not a number: \(text)")
        }
        return number
    }

    func lenientDouble(_ key: Key) throws -> Double {
        guard let number = try lenientDouble(forKey: key) else {
            throw DecodingError.valueNotFound(Double.self, .init(codingPath: codingPath + [key], debugDescription: "Missing number"))
        }
        return number
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

extension NutrientImportPayload {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.lenientDouble(.amount)
        unit = try container.decode(String.self, forKey: .unit)
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
    var saturatedFat: Double?
    var sugars: Double?
    var fiber: Double?
    var salt: Double?
    var minerals: [NutrientImportPayload]?
    var vitamins: [NutrientImportPayload]?

    var resolvedUnit: MeasurementUnit { parseMeasurementUnit(unit) }
    var resolvedNutritionBasis: NutritionBasis { parseNutritionBasis(nutritionBasis) }

    func makeFoodItem() -> FoodItem {
        let trimmedBrand = brand?.trimmingCharacters(in: .whitespaces)
        var item = FoodItem(
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
        item.saturatedFat = saturatedFat
        item.sugars = sugars
        item.fiber = fiber
        item.salt = salt
        // Names the fixed list knows (Vitamina C, Magnésio…) become `micronutrients`.
        var micros: [String: Double] = [:]
        item.minerals = FoodItem.adopt(item.minerals, into: &micros)
        item.vitamins = FoodItem.adopt(item.vitamins, into: &micros)
        item.micronutrients = micros
        return item
    }
}

extension FoodImportPayload {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        doseSize = try container.lenientDouble(forKey: .doseSize)
        nutritionBasis = try container.decodeIfPresent(String.self, forKey: .nutritionBasis)
        calories = Int(try container.lenientDouble(.calories).rounded())
        protein = try container.lenientDouble(forKey: .protein)
        carbs = try container.lenientDouble(forKey: .carbs)
        fat = try container.lenientDouble(forKey: .fat)
        saturatedFat = try container.lenientDouble(forKey: .saturatedFat)
        sugars = try container.lenientDouble(forKey: .sugars)
        fiber = try container.lenientDouble(forKey: .fiber)
        salt = try container.lenientDouble(forKey: .salt)
        minerals = try container.decodeIfPresent([NutrientImportPayload].self, forKey: .minerals)
        vitamins = try container.decodeIfPresent([NutrientImportPayload].self, forKey: .vitamins)
    }
}

struct RecipeItemImportPayload: Codable {
    var food: FoodImportPayload
    var quantity: Double?
}

extension RecipeItemImportPayload {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        food = try container.decode(FoodImportPayload.self, forKey: .food)
        quantity = try container.lenientDouble(forKey: .quantity)
    }
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
    var saturatedFat: Double?
    var sugars: Double?
    var fiber: Double?
    var salt: Double?

    /// What was eaten, for the diary entry.
    var nutrition: NutritionAmounts {
        NutritionAmounts(calories: Double(calories), protein: protein, carbs: carbs, sugars: sugars, fat: fat,
                         saturatedFat: saturatedFat, fiber: fiber, salt: salt)
    }
}

extension DiaryEntryImportPayload {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        calories = Int(try container.lenientDouble(.calories).rounded())
        protein = try container.lenientDouble(forKey: .protein)
        carbs = try container.lenientDouble(forKey: .carbs)
        fat = try container.lenientDouble(forKey: .fat)
        saturatedFat = try container.lenientDouble(forKey: .saturatedFat)
        sugars = try container.lenientDouble(forKey: .sugars)
        fiber = try container.lenientDouble(forKey: .fiber)
        salt = try container.lenientDouble(forKey: .salt)
    }
}

/// A sports supplement as an AI describes it. Nutrition is per dose (supplements are always
/// logged by the dose), and the category is a free name matched to — or added to — the user's own
/// categories when imported.
struct SupplementImportPayload: Codable {
    var name: String
    var category: String?
    var unit: String?
    var totalSize: Double?
    var doseSize: Double?
    var calories: Int?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var saturatedFat: Double?
    var sugars: Double?
    var fiber: Double?
    var salt: Double?
    var minerals: [NutrientImportPayload]?
    var vitamins: [NutrientImportPayload]?

    var resolvedUnit: MeasurementUnit { parseMeasurementUnit(unit) }
    /// One dose, falling back to the whole package (or 1) when the AI leaves it out.
    var resolvedDoseSize: Double { [doseSize, totalSize].compactMap { $0 }.first { $0 > 0 } ?? 1 }
    var resolvedTotalSize: Double { totalSize.flatMap { $0 > 0 ? $0 : nil } ?? resolvedDoseSize }

    func makeSupplement(categoryID: UUID) -> Supplement {
        var supplement = Supplement(
            name: name.trimmingCharacters(in: .whitespaces),
            categoryID: categoryID,
            unit: resolvedUnit,
            totalSize: resolvedTotalSize,
            doseSize: resolvedDoseSize,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat
        )
        supplement.saturatedFat = saturatedFat
        supplement.sugars = sugars
        supplement.fiber = fiber
        supplement.salt = salt
        // Only what the fixed list knows: supplements have no free-text nutrients.
        var micros: [String: Double] = [:]
        _ = FoodItem.adopt(((minerals ?? []) + (vitamins ?? [])).map { $0.makeNutrientValue() }, into: &micros)
        supplement.micronutrients = micros
        return supplement
    }
}

extension SupplementImportPayload {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        totalSize = try container.lenientDouble(forKey: .totalSize)
        doseSize = try container.lenientDouble(forKey: .doseSize)
        calories = try container.lenientDouble(forKey: .calories).map { Int($0.rounded()) }
        protein = try container.lenientDouble(forKey: .protein)
        carbs = try container.lenientDouble(forKey: .carbs)
        fat = try container.lenientDouble(forKey: .fat)
        saturatedFat = try container.lenientDouble(forKey: .saturatedFat)
        sugars = try container.lenientDouble(forKey: .sugars)
        fiber = try container.lenientDouble(forKey: .fiber)
        salt = try container.lenientDouble(forKey: .salt)
        minerals = try container.decodeIfPresent([NutrientImportPayload].self, forKey: .minerals)
        vitamins = try container.decodeIfPresent([NutrientImportPayload].self, forKey: .vitamins)
    }
}

// MARK: - Decoding

enum AIImportError: LocalizedError {
    case invalidJSON
    case empty
    case missingRecipeName

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Este texto não corresponde ao formato esperado. Confirma que colaste o JSON completo devolvido pela IA."
        case .empty:
            return "O JSON não contém nenhum item."
        case .missingRecipeName:
            return "A resposta da IA não tem o nome da receita. Escreve-o no campo Nome."
        }
    }
}

/// Parses JSON pasted from an external AI assistant into the app's models. Tries a couple of
/// reasonably-shaped alternatives (a bare object, a bare array, a wrapper object) since AI output
/// isn't always wrapped exactly the way the example schema shows.
enum AIJSONImport {
    private static let decoder = JSONDecoder()

    /// The JSON inside whatever the AI answered: assistants often wrap it in a ```json block or add
    /// a sentence before/after it, so everything outside the outermost `{…}`/`[…]` is dropped.
    private static func data(from text: String) throws -> Data {
        var json = text
        if let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }),
           let end = text.lastIndex(where: { $0 == "}" || $0 == "]" }),
           start < end {
            json = String(text[start...end])
        }
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

    static func decodeSupplements(from json: String) throws -> [SupplementImportPayload] {
        let data = try data(from: json)
        if let array = try? decoder.decode([SupplementImportPayload].self, from: data), !array.isEmpty {
            return array
        }
        if let single = try? decoder.decode(SupplementImportPayload.self, from: data) {
            return [single]
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

// MARK: - Prompts handed to the AI

/// What the user copies into any AI assistant: the task, what each field means, the rules the
/// answer must follow, and a template of the JSON shape. The template is generic (placeholders
/// describing each value, no example food) so the AI fills in the user's own food instead of
/// echoing an example back.
struct AIImportPrompt {
    /// Example shown in the import sheet's description field, fitting what's being imported.
    var descriptionPlaceholder = "Descrição (opcional)"
    let task: String
    let fields: String
    let template: String

    private static let rules = """
    Regras da resposta:
    - Responde apenas com o JSON, sem texto antes ou depois e sem blocos de código Markdown.
    - JSON válido: aspas duplas, números com ponto decimal e sem unidades dentro dos valores (12.5, não "12,5 g").
    - Substitui cada <descrição> pelo valor real. Os campos opcionais podem ser omitidos ou ficar a null quando não os souberes.
    - Escreve os nomes em português de Portugal.
    - Se não souberes um valor exato, estima-o a partir de valores de referência habituais (tabelas de composição de alimentos ou rótulos típicos). Não inventes marcas.
    """

    /// The full text to paste into the AI, ending where the user describes their food.
    var text: String {
        """
        \(task)

        \(fields)

        \(Self.rules)

        Formato da resposta:
        \(template)

        O que quero registar:
        """
    }
}

extension AIJSONImport {
    static let foodPrompt = AIImportPrompt(
        descriptionPlaceholder: "Descrição (ex.: iogurte grego natural Milbona, 150 g)",
        task: "Preciso dos valores nutricionais de um alimento para uma app de registo de nutrição. O alimento é o que eu descrever no fim (ou o da foto ou rótulo que eu enviar).",
        fields: """
        Campos:
        - name: nome do alimento.
        - brand (opcional): marca, só se for um produto de marca.
        - unit: unidade em que o alimento é medido — "gram", "milliliter" ou "unit" (alimentos contados à unidade, ex.: ovos).
        - doseSize: tamanho de uma dose habitual, na unidade indicada (ex.: 30 para 30 g de cereais, 1 para um ovo).
        - nutritionBasis: "per100" se os valores forem por 100 g/ml (como nos rótulos) ou "perDose" se forem por uma dose. Usa "perDose" quando unit for "unit".
        - calories: energia em kcal (número inteiro).
        - protein, carbs, fat: proteína, hidratos de carbono e lípidos, em gramas.
        - saturatedFat, sugars, fiber, salt (opcionais): lípidos saturados, açúcares, fibra e sal, em gramas, como no rótulo.
        - minerals, vitamins (opcionais): listas de { name, amount, unit }, com unit "mg" ou "µg" (ex.: Potássio, Magnésio, Vitamina C, Tiamina (B1), Cafeína).
        Se eu descrever vários alimentos, devolve um array com um objeto por alimento.
        """,
        template: """
        {
          "name": "<nome do alimento>",
          "brand": "<marca, opcional>",
          "unit": "<gram | milliliter | unit>",
          "doseSize": <tamanho de uma dose, na unidade>,
          "nutritionBasis": "<per100 | perDose>",
          "calories": <kcal, inteiro>,
          "protein": <gramas>,
          "carbs": <gramas>,
          "fat": <gramas>,
          "saturatedFat": <gramas>,
          "sugars": <gramas>,
          "fiber": <gramas>,
          "salt": <gramas>,
          "minerals": [
            { "name": "<mineral>", "amount": <quantidade>, "unit": "<mg | µg>" }
          ],
          "vitamins": [
            { "name": "<vitamina>", "amount": <quantidade>, "unit": "<mg | µg>" }
          ]
        }
        """
    )

    static let recipePrompt = AIImportPrompt(
        descriptionPlaceholder: "Descrição (ex.: arroz de pato para 4 pessoas)",
        task: "Preciso de decompor uma receita ou refeição nos alimentos que a compõem, para uma app de registo de nutrição. A receita é a que eu descrever no fim (ou a da foto que eu enviar).",
        fields: """
        Campos:
        - name (opcional): nome da receita.
        - items: um objeto por ingrediente, com:
          - food: o ingrediente — name, unit ("gram", "milliliter" ou "unit"), doseSize (tamanho de uma dose na unidade), nutritionBasis ("per100" se os valores forem por 100 g/ml, "perDose" se forem por uma dose), calories (kcal, inteiro), protein, carbs e fat (gramas).
          - quantity: quantas doses (doseSize) desse ingrediente a receita leva. Ex.: com doseSize 100 g, 150 g de arroz é quantity 1.5.
        Usa os ingredientes no estado em que são pesados (ex.: arroz cozido ou cru) e indica-o no nome.
        """,
        template: """
        {
          "name": "<nome da receita, opcional>",
          "items": [
            {
              "food": {
                "name": "<nome do ingrediente>",
                "unit": "<gram | milliliter | unit>",
                "doseSize": <tamanho de uma dose, na unidade>,
                "nutritionBasis": "<per100 | perDose>",
                "calories": <kcal, inteiro>,
                "protein": <gramas>,
                "carbs": <gramas>,
                "fat": <gramas>
              },
              "quantity": <número de doses>
            }
          ]
        }
        """
    )

    static let diaryPrompt = AIImportPrompt(
        descriptionPlaceholder: "Descrição (ex.: bitoque, comi metade da batata)",
        task: "Preciso de estimar os valores nutricionais do que comi numa refeição, para registar numa app de nutrição. A refeição é a que eu descrever no fim (ou a da foto que eu enviar).",
        fields: """
        Campos (um objeto por alimento ou prato, sempre num array):
        - name: nome do alimento ou prato, com a porção quando ajudar (ex.: "Arroz cozido (150 g)").
        - calories: energia da porção comida, em kcal (número inteiro).
        - protein, carbs, fat (opcionais): proteína, hidratos de carbono e lípidos da porção comida, em gramas.
        - saturatedFat, sugars, fiber, salt (opcionais): lípidos saturados, açúcares, fibra e sal da porção comida, em gramas.
        Os valores são os da porção que foi realmente comida, não por 100 g.
        """,
        template: """
        [
          {
            "name": "<alimento ou prato>",
            "calories": <kcal da porção, inteiro>,
            "protein": <gramas>,
            "carbs": <gramas>,
            "fat": <gramas>,
            "saturatedFat": <gramas>,
            "sugars": <gramas>,
            "fiber": <gramas>,
            "salt": <gramas>
          }
        ]
        """
    )

    /// The supplement prompt lists the user's own categories, so the AI picks one of them instead
    /// of inventing a near-duplicate ("Proteína" vs. "Proteínas").
    static func supplementPrompt(categories: [String]) -> AIImportPrompt {
        let categoryRule = categories.isEmpty
            ? "categoria do suplemento (ex.: Proteína, Gel Energético, Isotónico, Eletrólitos, Creatina)."
            : "uma destas categorias: \(categories.joined(separator: ", ")). Só se nenhuma servir, sugere uma nova, curta."
        return AIImportPrompt(
            descriptionPlaceholder: "Descrição (ex.: gel energético Maurten 100, caixa de 12)",
            task: "Preciso dos dados de um suplemento desportivo (proteína, gel energético, isotónico, eletrólitos, creatina, cafeína…) para uma app de nutrição. O suplemento é o que eu descrever no fim (ou o da foto ou rótulo que eu enviar).",
            fields: """
            Campos:
            - name: nome do suplemento, com a marca quando ajudar (ex.: "Whey Isolate (marca)").
            - category: \(categoryRule)
            - unit: unidade em que a embalagem e as doses são medidas — "gram", "milliliter" ou "unit" (cápsulas, comprimidos, géis, saquetas).
            - totalSize: quantidade total da embalagem, na unidade indicada (ex.: 900 para 900 g, 60 para 60 cápsulas).
            - doseSize: quantidade de uma dose, na unidade indicada (ex.: 30 para 30 g, 1 para um gel).
            - calories (opcional): energia de uma dose, em kcal (número inteiro).
            - protein, carbs, fat (opcionais): proteína, hidratos de carbono e lípidos de uma dose, em gramas.
            - saturatedFat, sugars, fiber, salt (opcionais): lípidos saturados, açúcares, fibra e sal de uma dose, em gramas.
            - minerals, vitamins (opcionais): listas de { name, amount, unit } por dose, com unit "mg" ou "µg" (ex.: Potássio, Magnésio, Selénio, Vitamina C, Niacina (B3), Cafeína).
            Os valores nutricionais são por dose, não por 100 g. Se eu descrever vários suplementos, devolve um array com um objeto por suplemento.
            """,
            template: """
            {
              "name": "<nome do suplemento>",
              "category": "<categoria>",
              "unit": "<gram | milliliter | unit>",
              "totalSize": <quantidade da embalagem, na unidade>,
              "doseSize": <quantidade de uma dose, na unidade>,
              "calories": <kcal por dose, inteiro>,
              "protein": <gramas por dose>,
              "carbs": <gramas por dose>,
              "fat": <gramas por dose>,
              "saturatedFat": <gramas por dose>,
              "sugars": <gramas por dose>,
              "fiber": <gramas por dose>,
              "salt": <gramas por dose>,
              "minerals": [
                { "name": "<mineral>", "amount": <quantidade por dose>, "unit": "<mg | µg>" }
              ],
              "vitamins": [
                { "name": "<vitamina>", "amount": <quantidade por dose>, "unit": "<mg | µg>" }
              ]
            }
            """
        )
    }
}
