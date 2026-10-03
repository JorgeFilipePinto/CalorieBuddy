import Foundation

/// A vitamin, mineral, amino acid or sports substance a nutrition label can declare, from a fixed
/// list so amounts add up across a recipe or a day and compare between products. Stored as
/// `[rawValue: amount]` (`micronutrients`), the amount in `unit`.
///
/// `referenceIntake` is the EU nutrient reference value (Regulation 1169/2011, annex XIII) that
/// labels' "%VRN" is computed from; sodium, the amino acids and the sports substances have none.
enum Micronutrient: String, CaseIterable, Identifiable, Codable {
    // Vitamins
    case vitaminA, vitaminD, vitaminE, vitaminK, vitaminC
    case thiamin, riboflavin, niacin, vitaminB6, folate, vitaminB12, biotin, pantothenicAcid
    // Minerals
    case potassium, chloride, calcium, phosphorus, magnesium, iron, zinc, copper, manganese
    case fluoride, selenium, chromium, molybdenum, iodine, sodium
    // Amino acids (the three BCAAs first)
    case leucine, isoleucine, valine, glutamine, arginine, citrulline
    // Sports substances
    case creatine, betaAlanine, hmb, carnitine, taurine, nitrate, epa, dha, caffeine

    enum Kind: String, CaseIterable {
        case vitamin, mineral, aminoAcid, sport

        var title: String {
            switch self {
            case .vitamin: return "Vitaminas"
            case .mineral: return "Minerais"
            case .aminoAcid: return "Aminoácidos"
            case .sport: return "Desporto"
            }
        }
    }

    var id: String { rawValue }

    var kind: Kind {
        switch self {
        case .vitaminA, .vitaminD, .vitaminE, .vitaminK, .vitaminC, .thiamin, .riboflavin, .niacin,
             .vitaminB6, .folate, .vitaminB12, .biotin, .pantothenicAcid:
            return .vitamin
        case .leucine, .isoleucine, .valine, .glutamine, .arginine, .citrulline:
            return .aminoAcid
        case .creatine, .betaAlanine, .hmb, .carnitine, .taurine, .nitrate, .epa, .dha, .caffeine:
            return .sport
        default:
            return .mineral
        }
    }

    var displayName: String {
        switch self {
        case .vitaminA: return "Vitamina A"
        case .vitaminD: return "Vitamina D"
        case .vitaminE: return "Vitamina E"
        case .vitaminK: return "Vitamina K"
        case .vitaminC: return "Vitamina C"
        case .thiamin: return "Tiamina (B1)"
        case .riboflavin: return "Riboflavina (B2)"
        case .niacin: return "Niacina (B3)"
        case .vitaminB6: return "Vitamina B6"
        case .folate: return "Ácido fólico (B9)"
        case .vitaminB12: return "Vitamina B12"
        case .biotin: return "Biotina (B8)"
        case .pantothenicAcid: return "Ácido pantoténico (B5)"
        case .potassium: return "Potássio"
        case .chloride: return "Cloreto"
        case .calcium: return "Cálcio"
        case .phosphorus: return "Fósforo"
        case .magnesium: return "Magnésio"
        case .iron: return "Ferro"
        case .zinc: return "Zinco"
        case .copper: return "Cobre"
        case .manganese: return "Manganês"
        case .fluoride: return "Flúor"
        case .selenium: return "Selénio"
        case .chromium: return "Crómio"
        case .molybdenum: return "Molibdénio"
        case .iodine: return "Iodo"
        case .sodium: return "Sódio"
        case .leucine: return "Leucina (BCAA)"
        case .isoleucine: return "Isoleucina (BCAA)"
        case .valine: return "Valina (BCAA)"
        case .glutamine: return "Glutamina"
        case .arginine: return "Arginina"
        case .citrulline: return "Citrulina"
        case .creatine: return "Creatina"
        case .betaAlanine: return "Beta-alanina"
        case .hmb: return "HMB"
        case .carnitine: return "L-carnitina"
        case .taurine: return "Taurina"
        case .nitrate: return "Nitratos"
        case .epa: return "Ómega-3 EPA"
        case .dha: return "Ómega-3 DHA"
        case .caffeine: return "Cafeína"
        }
    }

    /// Whether it's one of the three branched-chain amino acids (leucine, isoleucine, valine).
    var isBCAA: Bool { self == .leucine || self == .isoleucine || self == .valine }

    /// The unit labels use for it ("g", "mg" or "µg") — grams for what's taken by the gram
    /// (creatine, amino acids…).
    var unit: String {
        switch self {
        case .vitaminA, .vitaminD, .vitaminK, .folate, .vitaminB12, .biotin, .selenium, .chromium,
             .molybdenum, .iodine:
            return "µg"
        case .leucine, .isoleucine, .valine, .glutamine, .arginine, .citrulline, .creatine, .betaAlanine,
             .hmb, .carnitine:
            return "g"
        default:
            return "mg"
        }
    }

    /// EU nutrient reference value, in `unit` (nil: none — the label shows no %VRN).
    var referenceIntake: Double? {
        switch self {
        case .vitaminA: return 800
        case .vitaminD: return 5
        case .vitaminE: return 12
        case .vitaminK: return 75
        case .vitaminC: return 80
        case .thiamin: return 1.1
        case .riboflavin: return 1.4
        case .niacin: return 16
        case .vitaminB6: return 1.4
        case .folate: return 200
        case .vitaminB12: return 2.5
        case .biotin: return 50
        case .pantothenicAcid: return 6
        case .potassium: return 2000
        case .chloride: return 800
        case .calcium: return 800
        case .phosphorus: return 700
        case .magnesium: return 375
        case .iron: return 14
        case .zinc: return 10
        case .copper: return 1
        case .manganese: return 2
        case .fluoride: return 3.5
        case .selenium: return 55
        case .chromium: return 40
        case .molybdenum: return 50
        case .iodine: return 150
        default: return nil
        }
    }

    /// `amount` as a percentage of the reference value, e.g. 39 for 790 mg of potassium.
    func percentOfReference(_ amount: Double) -> Double? {
        referenceIntake.map { amount / $0 * 100 }
    }

    /// Names (lowercased, without accents) a label or an older free-text entry may use for it.
    private var aliases: [String] {
        switch self {
        case .vitaminA: return ["vitamina a", "vitamin a", "retinol"]
        case .vitaminD: return ["vitamina d", "vitamin d", "vitamina d3", "colecalciferol"]
        case .vitaminE: return ["vitamina e", "vitamin e", "tocoferol"]
        case .vitaminK: return ["vitamina k", "vitamin k", "vitamina k1", "vitamina k2"]
        case .vitaminC: return ["vitamina c", "vitamin c", "acido ascorbico", "ascorbic acid"]
        case .thiamin: return ["tiamina", "thiamin", "thiamine", "vitamina b1", "vitamin b1", "b1"]
        case .riboflavin: return ["riboflavina", "riboflavin", "vitamina b2", "vitamin b2", "b2"]
        case .niacin: return ["niacina", "niacin", "vitamina b3", "vitamin b3", "b3", "nicotinamida"]
        case .vitaminB6: return ["vitamina b6", "vitamin b6", "b6", "piridoxina"]
        case .folate: return ["acido folico", "folato", "folate", "folic acid", "vitamina b9", "vitamin b9", "b9"]
        case .vitaminB12: return ["vitamina b12", "vitamin b12", "b12", "cobalamina"]
        case .biotin: return ["biotina", "biotin", "vitamina b8", "vitamina b7", "b8", "b7"]
        case .pantothenicAcid: return ["acido pantotenico", "pantothenic acid", "vitamina b5", "vitamin b5", "b5"]
        case .potassium: return ["potassio", "potassium", "k"]
        case .chloride: return ["cloreto", "chloride", "cloro"]
        case .calcium: return ["calcio", "calcium", "ca"]
        case .phosphorus: return ["fosforo", "phosphorus", "p"]
        case .magnesium: return ["magnesio", "magnesium", "mg"]
        case .iron: return ["ferro", "iron", "fe"]
        case .zinc: return ["zinco", "zinc", "zn"]
        case .copper: return ["cobre", "copper", "cu"]
        case .manganese: return ["manganes", "manganesio", "manganese", "mn"]
        case .fluoride: return ["fluor", "fluoreto", "fluoride"]
        case .selenium: return ["selenio", "selenium", "se"]
        case .chromium: return ["cromio", "chromium", "cr"]
        case .molybdenum: return ["molibdenio", "molybdenum", "mo"]
        case .iodine: return ["iodo", "iodine"]
        case .sodium: return ["sodio", "sodium", "na"]
        case .leucine: return ["leucina", "leucine", "l-leucina", "l-leucine"]
        case .isoleucine: return ["isoleucina", "isoleucine", "l-isoleucina", "l-isoleucine"]
        case .valine: return ["valina", "valine", "l-valina", "l-valine"]
        case .glutamine: return ["glutamina", "glutamine", "l-glutamina", "l-glutamine"]
        case .arginine: return ["arginina", "arginine", "l-arginina", "l-arginine"]
        case .citrulline: return ["citrulina", "citrulline", "l-citrulina", "l-citrulline", "citrulina malato", "citrulline malate"]
        case .creatine: return ["creatina", "creatine", "creatina monohidratada", "creatine monohydrate"]
        case .betaAlanine: return ["beta-alanina", "beta alanina", "beta-alanine", "beta alanine"]
        case .hmb: return ["hmb", "beta-hidroxi-beta-metilbutirato"]
        case .carnitine: return ["carnitina", "l-carnitina", "carnitine", "l-carnitine"]
        case .taurine: return ["taurina", "taurine"]
        case .nitrate: return ["nitratos", "nitrato", "nitrate", "nitrates"]
        case .epa: return ["epa", "omega-3 epa", "omega 3 epa", "acido eicosapentaenoico"]
        case .dha: return ["dha", "omega-3 dha", "omega 3 dha", "acido docosa-hexaenoico", "acido docosahexaenoico"]
        case .caffeine: return ["cafeina", "caffeine"]
        }
    }

    /// The micronutrient a free-text name refers to ("Vitamina C", "Magnésio", "B6"…), if any.
    static func matching(_ name: String) -> Micronutrient? {
        let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return allCases.first { $0.aliases.contains(key) }
    }

    /// `amount` given in `unit` ("g", "mg", "µg"/"mcg"/"ug") converted to this nutrient's unit,
    /// or nil when the unit isn't a mass unit.
    func convert(_ amount: Double, from unit: String) -> Double? {
        let micrograms: Double
        switch unit.trimmingCharacters(in: .whitespaces).lowercased() {
        case "g": micrograms = amount * 1_000_000
        case "mg": micrograms = amount * 1000
        case "µg", "μg", "mcg", "ug": micrograms = amount
        default: return nil
        }
        switch self.unit {
        case "g": return micrograms / 1_000_000
        case "mg": return micrograms / 1000
        default: return micrograms
        }
    }
}

/// Every nutrient of an amount of food (a dose, a recipe, a day's entries), ready to add up.
/// `nil` means "not stated", which isn't the same as 0 — a total only shows a value when at least
/// one part stated it.
struct NutritionAmounts: Equatable {
    var calories: Double = 0
    var protein: Double?
    var carbs: Double?
    var sugars: Double?
    var fat: Double?
    var saturatedFat: Double?
    var fiber: Double?
    var salt: Double?
    var micronutrients: [Micronutrient: Double] = [:]

    static let zero = NutritionAmounts()

    static func + (lhs: NutritionAmounts, rhs: NutritionAmounts) -> NutritionAmounts {
        func add(_ a: Double?, _ b: Double?) -> Double? {
            switch (a, b) {
            case (nil, nil): return nil
            default: return (a ?? 0) + (b ?? 0)
            }
        }
        return NutritionAmounts(
            calories: lhs.calories + rhs.calories,
            protein: add(lhs.protein, rhs.protein),
            carbs: add(lhs.carbs, rhs.carbs),
            sugars: add(lhs.sugars, rhs.sugars),
            fat: add(lhs.fat, rhs.fat),
            saturatedFat: add(lhs.saturatedFat, rhs.saturatedFat),
            fiber: add(lhs.fiber, rhs.fiber),
            salt: add(lhs.salt, rhs.salt),
            micronutrients: lhs.micronutrients.merging(rhs.micronutrients, uniquingKeysWith: +)
        )
    }

    func scaled(by factor: Double) -> NutritionAmounts {
        NutritionAmounts(
            calories: calories * factor,
            protein: protein.map { $0 * factor },
            carbs: carbs.map { $0 * factor },
            sugars: sugars.map { $0 * factor },
            fat: fat.map { $0 * factor },
            saturatedFat: saturatedFat.map { $0 * factor },
            fiber: fiber.map { $0 * factor },
            salt: salt.map { $0 * factor },
            micronutrients: micronutrients.mapValues { $0 * factor }
        )
    }

    /// Leucine + isoleucine + valine, in g, when at least one is stated.
    var bcaaTotal: Double? {
        let parts = micronutrients.filter { $0.key.isBCAA }
        return parts.isEmpty ? nil : parts.values.reduce(0, +)
    }

    /// Whether anything beyond energy and the three macros is stated.
    var hasDetails: Bool {
        sugars != nil || saturatedFat != nil || fiber != nil || salt != nil || !micronutrients.isEmpty
    }
}

/// Storage form of `micronutrients` (`[rawValue: amount]`) — JSON-friendly, and keys the app
/// doesn't know (written by a newer version or the dashboard) survive a round trip.
extension Dictionary where Key == String, Value == Double {
    var typedMicronutrients: [Micronutrient: Double] {
        reduce(into: [:]) { result, pair in
            if let nutrient = Micronutrient(rawValue: pair.key) { result[nutrient] = pair.value }
        }
    }
}

extension Dictionary where Key == Micronutrient, Value == Double {
    var stored: [String: Double] {
        reduce(into: [:]) { result, pair in result[pair.key.rawValue] = pair.value }
    }
}
