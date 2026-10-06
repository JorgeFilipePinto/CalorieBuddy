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
    /// One of the catalog's food categories, by name (matched leniently; unknown names are ignored).
    var category: String?
    /// The EAN printed on the package, when the AI could read it from a photo.
    var barcode: String?
    /// % weight change raw → cooked (rice +160, chicken −25), for meal prep; only for raw foods
    /// that change. `nil` = the app's reference for its name.
    var cookingWeightChange: Double?

    var resolvedUnit: MeasurementUnit { parseMeasurementUnit(unit) }

    /// Just the digits of `barcode`, when it looks like a real code (8–14 digits).
    var resolvedBarcode: String? {
        let digits = (barcode ?? "").filter(\.isNumber)
        return (8...14).contains(digits.count) ? digits : nil
    }
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
        // A raw food can't lose all its weight; foods counted in units don't change.
        if let change = cookingWeightChange, change > -100, change != 0, item.unit.baseUnit != .unit {
            item.cookingWeightChange = change
        }
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
        category = try? container.decodeIfPresent(String.self, forKey: .category)
        // A barcode sometimes comes back as a bare number.
        barcode = (try? container.decodeIfPresent(String.self, forKey: .barcode))
            ?? (try? container.decodeIfPresent(Int64.self, forKey: .barcode)).flatMap { $0.map(String.init) }
        cookingWeightChange = try? container.lenientDouble(forKey: .cookingWeightChange)
    }
}

struct RecipeItemImportPayload: Codable {
    var food: FoodImportPayload
    /// How much of the ingredient one portion takes, in the food's unit (g, ml or units) — what the
    /// prompt asks for.
    var amount: Double?
    /// Older answers: how many of the food's doses (`doseSize`). Used only without `amount`.
    var quantity: Double?
}

extension RecipeItemImportPayload {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        food = try container.decode(FoodImportPayload.self, forKey: .food)
        amount = try container.lenientDouble(forKey: .amount)
        quantity = try container.lenientDouble(forKey: .quantity)
    }
}

struct RecipeImportPayload: Codable {
    var name: String?
    var items: [RecipeItemImportPayload]
}

/// One product that came into the food stock (e.g. a line of a shopping receipt or a photographed
/// package): the food, how much came in and, when known, its expiry date and where it's kept.
struct StockImportPayload: Codable {
    var food: FoodImportPayload
    /// Total amount that came in, in the food's unit (g, ml or units) — every pack added up.
    var amount: Double?
    /// "YYYY-MM-DD", read from the package; nil when not visible.
    var expiresOn: String?
    /// One of the user's stock locations, by name.
    var location: String?

    /// The expiry date as a day (accepts "2026-10-12" and "12/10/2026").
    var resolvedExpiry: Date? {
        guard let text = expiresOn?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in ["yyyy-MM-dd", "dd/MM/yyyy", "dd-MM-yyyy", "dd.MM.yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return Calendar.current.startOfDay(for: date) }
        }
        return nil
    }
}

extension StockImportPayload {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        food = try container.decode(FoodImportPayload.self, forKey: .food)
        amount = try container.lenientDouble(forKey: .amount)
        expiresOn = try? container.decodeIfPresent(String.self, forKey: .expiresOn)
        location = try? container.decodeIfPresent(String.self, forKey: .location)
    }
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
        // iOS's smart punctuation turns " into “ ” when the answer is typed or edited on the phone.
        var json = text
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{201E}", with: "\"")
            .replacingOccurrences(of: "\u{00AB}", with: "\"")
            .replacingOccurrences(of: "\u{00BB}", with: "\"")
        let cleaned = json
        if let start = cleaned.firstIndex(where: { $0 == "{" || $0 == "[" }),
           let end = cleaned.lastIndex(where: { $0 == "}" || $0 == "]" }),
           start < end {
            json = String(cleaned[start...end])
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

    /// Stock lines: an array, a single object, or a wrapper like `{ "items": [...] }`.
    static func decodeStock(from json: String) throws -> [StockImportPayload] {
        struct Wrapper: Decodable { let items: [StockImportPayload] }
        let data = try data(from: json)
        if let array = try? decoder.decode([StockImportPayload].self, from: data), !array.isEmpty {
            return array
        }
        if let wrapper = try? decoder.decode(Wrapper.self, from: data), !wrapper.items.isEmpty {
            return wrapper.items
        }
        if let single = try? decoder.decode(StockImportPayload.self, from: data) {
            return [single]
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
    /// The categories the AI may pick from, as a prompt line (empty when there are none).
    private static func categoryField(_ categories: [String]) -> String {
        guard !categories.isEmpty else { return "" }
        return "\n- category (opcional): a categoria do alimento, exatamente uma destas: " + categories.map { "\"\($0)\"" }.joined(separator: ", ") + ". Omite se nenhuma servir."
    }

    static func foodPrompt(categories: [String] = []) -> AIImportPrompt { AIImportPrompt(
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
        - minerals, vitamins (opcionais): listas de { name, amount, unit }, com unit "g", "mg" ou "µg" (ex.: Potássio, Magnésio, Vitamina C, Tiamina (B1), Cafeína). Aminoácidos e substâncias de desporto também vão em "minerals" (ex.: Leucina, Isoleucina, Valina, Glutamina, Creatina, Beta-alanina, Citrulina, Taurina, L-carnitina, HMB, EPA, DHA).
        - barcode (opcional): o código de barras (EAN, só dígitos) se estiver visível na foto da embalagem. Nunca o inventes.
        - \(cookingField)\(categoryField(categories))
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
            { "name": "<mineral>", "amount": <quantidade>, "unit": "<g | mg | µg>" }
          ],
          "vitamins": [
            { "name": "<vitamina>", "amount": <quantidade>, "unit": "<g | mg | µg>" }
          ],
          "barcode": "<código de barras, opcional>",
          "cookingWeightChange": <variação ao cozinhar em %, opcional>,
          "category": "<categoria, opcional>"
        }
        """
    ) }

    /// The field asking how much a raw food's weight changes when cooked (for meal prep).
    private static let cookingField = "cookingWeightChange (opcional): só para alimentos crus que mudam de peso ao cozinhar, a variação do peso de cru para cozinhado em % (ex.: arroz cru 160, massa crua 125, peito de frango cru -25, brócolos -10). Omite para alimentos já cozinhados ou prontos a comer e para os contados à unidade."

    /// What came into the stock: foods (as in the food prompt) with the amount bought, the expiry
    /// date read from the package and, when the user has stock locations, where it's kept.
    static func stockPrompt(categories: [String] = [], locations: [String] = []) -> AIImportPrompt {
        let locationField = locations.isEmpty ? "" : "\n  - location (opcional): onde guardar, exatamente um destes locais: " + locations.map { "\"\($0)\"" }.joined(separator: ", ") + ". Escolhe pelo tipo de produto (ex.: frescos no frigorífico, congelados no congelador); omite se não for claro."
        return AIImportPrompt(
            descriptionPlaceholder: "Descrição (ex.: compras do Continente, ver talão)",
            task: "Preciso de registar a entrada de alimentos no stock de casa, numa app de nutrição. Os produtos são os que eu descrever no fim (ou os da foto do talão de compras ou das embalagens que eu enviar).",
            fields: """
            Campos (sempre um array, um objeto por produto; o mesmo produto comprado várias vezes aparece uma só vez com as quantidades somadas):
            - food: o alimento, com os campos de um alimento — name (nome genérico em português, sem pesos nem preços; ex.: "Peito de Frango (cru)", "Arroz Agulha (cru)"), brand (opcional, só se for de marca), unit ("gram", "milliliter" ou "unit"), doseSize (uma dose habitual, na unidade), nutritionBasis ("per100" para valores por 100 g/ml, "perDose" por dose; "perDose" quando unit for "unit"), calories (kcal, inteiro), protein, carbs, fat e, se souberes, saturatedFat, sugars, fiber e salt (gramas); barcode (opcional, só se estiver visível; nunca o inventes); \(cookingField)\(categoryField(categories).replacingOccurrences(of: "\n- ", with: " Opcional também: "))
            - amount: quantidade total que entrou, na unidade do alimento (ex.: 1000 para um pacote de 1 kg, 2000 para dois pacotes de 1 kg, 12 para uma dúzia de ovos). Converte kg e L para gramas e mililitros.
            - expiresOn (opcional): data de validade impressa na embalagem, no formato "AAAA-MM-DD". Só se estiver visível; nunca a inventes.\(locationField)
            Ignora no talão o que não é comida (sacos, detergentes…), os descontos e os totais.
            """,
            template: """
            [
              {
                "food": {
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
                  "barcode": "<código de barras, opcional>",
                  "cookingWeightChange": <variação ao cozinhar em %, opcional>,
                  "category": "<categoria, opcional>"
                },
                "amount": <quantidade total que entrou, na unidade do alimento>,
                "expiresOn": "<AAAA-MM-DD, opcional>",
                "location": "<local, opcional>"
              }
            ]
            """
        )
    }

    static func recipePrompt(categories: [String] = []) -> AIImportPrompt { AIImportPrompt(
        descriptionPlaceholder: "Descrição (ex.: arroz de pato para 4 pessoas)",
        task: "Preciso de decompor uma receita ou refeição nos alimentos que a compõem, para uma app de registo de nutrição. A receita é a que eu descrever no fim (ou a da foto que eu enviar).",
        fields: """
        Campos:
        - name (opcional): nome da receita.
        - items: um objeto por ingrediente (cada ingrediente uma só vez), com:
          - food: o ingrediente, com os mesmos campos de um alimento — name, unit ("gram", "milliliter" ou "unit"), doseSize (uma dose habitual, na unidade), nutritionBasis ("per100" para valores por 100 g/ml, "perDose" por dose; "perDose" quando unit for "unit"), calories (kcal, inteiro), protein, carbs, fat e, se souberes, saturatedFat, sugars, fiber e salt (gramas); \(cookingField)\(categoryField(categories).replacingOccurrences(of: "\n- ", with: " Opcional também: "))
          - amount: quanto desse ingrediente leva UMA dose individual (uma pessoa), na unidade do ingrediente — ex.: 150 para 150 g de arroz cozido, 2 para dois ovos, 5 para uma colher de chá de azeite.
        Se a receita for para várias pessoas, divide as quantidades pelo número de pessoas: as quantidades são só o ponto de partida, a app pergunta quanto foi comido ao registar.
        Usa os ingredientes no estado em que são pesados (ex.: arroz cozido ou cru) e indica-o no nome. Inclui gorduras de confeção (azeite, manteiga) e molhos, que são fáceis de esquecer.
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
                "fat": <gramas>,
                "saturatedFat": <gramas>,
                "sugars": <gramas>,
                "fiber": <gramas>,
                "salt": <gramas>,
                "cookingWeightChange": <variação ao cozinhar em %, opcional>
              },
              "amount": <quantidade numa dose individual, na unidade do ingrediente>
            }
          ]
        }
        """
    ) }

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
            - minerals, vitamins (opcionais): listas de { name, amount, unit } por dose, com unit "g", "mg" ou "µg" (ex.: Potássio, Magnésio, Selénio, Vitamina C, Niacina (B3), Cafeína). Aminoácidos e substâncias de desporto também vão em "minerals" (ex.: Creatina, Leucina, Isoleucina, Valina, Glutamina, Beta-alanina, Citrulina, Taurina, L-carnitina, HMB, EPA, DHA).
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
                { "name": "<mineral>", "amount": <quantidade por dose>, "unit": "<g | mg | µg>" }
              ],
              "vitamins": [
                { "name": "<vitamina>", "amount": <quantidade por dose>, "unit": "<g | mg | µg>" }
              ]
            }
            """
        )
    }
}
