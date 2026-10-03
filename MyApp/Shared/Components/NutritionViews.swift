import SwiftUI

/// The text the label fields are edited as — empty = not stated.
struct LabelNutritionText: Equatable {
    var calories = ""
    var fat = ""
    var saturatedFat = ""
    var carbs = ""
    var sugars = ""
    var fiber = ""
    var protein = ""
    var salt = ""

    static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    static func text(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}

/// The rows of a nutrition label, in the order EU labels use (energy, fat, of which saturates,
/// carbohydrate, of which sugars, fibre, protein, salt), each a number field — the amounts as
/// printed on the label. Goes inside a Form `Section`.
struct LabelNutritionFields: View {
    @Binding var text: LabelNutritionText

    var body: some View {
        row("Energia", unit: "kcal", text: $text.calories, keyboard: .numberPad)
        if let kcal = LabelNutritionText.number(text.calories) {
            Text("= \(Int((kcal * 4.184).rounded())) kJ")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        row("Lípidos", unit: "g", text: $text.fat)
        row("dos quais saturados", unit: "g", text: $text.saturatedFat, indented: true)
        row("Hidratos de carbono", unit: "g", text: $text.carbs)
        row("dos quais açúcares", unit: "g", text: $text.sugars, indented: true)
        row("Fibra", unit: "g", text: $text.fiber)
        row("Proteína", unit: "g", text: $text.protein)
        row("Sal", unit: "g", text: $text.salt)
    }

    private func row(_ title: String, unit: String, text: Binding<String>, keyboard: KeyboardKind = .decimalPad,
                     indented: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(indented ? .secondary : .primary)
                .padding(.leading, indented ? 16 : 0)
            Spacer()
            TextField("—", text: text)
                #if os(iOS)
                .keyboardType(keyboard == .numberPad ? .numberPad : .decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
        }
    }

    enum KeyboardKind { case numberPad, decimalPad }
}

/// Vitamins, minerals, amino acids and sports substances from the fixed list: each one present with its amount, unit
/// and %VRN, swipe to remove, and a menu to add more. `basis` says what the amounts are for
/// ("por 100 g", "por dose").
struct MicronutrientsSection: View {
    @Binding var values: [Micronutrient: Double]
    let basis: String

    private var present: [Micronutrient] {
        Micronutrient.allCases.filter { values[$0] != nil }
    }

    var body: some View {
        Section {
            ForEach(present) { nutrient in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nutrient.displayName)
                        if let percent = values[nutrient].flatMap(nutrient.percentOfReference) {
                            Text("\(Int(percent.rounded()))% VRN")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    TextField("0", value: Binding(
                        get: { values[nutrient] ?? 0 },
                        set: { values[nutrient] = $0 }
                    ), format: .number)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text(nutrient.unit)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                }
            }
            .onDelete { offsets in
                for index in offsets { values[present[index]] = nil }
            }

            Menu {
                ForEach(Micronutrient.Kind.allCases, id: \.self) { kind in
                    let missing = Micronutrient.allCases.filter { $0.kind == kind && values[$0] == nil }
                    if !missing.isEmpty {
                        Section(kind.title) {
                            ForEach(missing) { nutrient in
                                Button("\(nutrient.displayName) (\(nutrient.unit))") { values[nutrient] = 0 }
                            }
                        }
                    }
                }
            } label: {
                Label("Adicionar Nutriente", systemImage: "plus")
            }
        } header: {
            Text("Vitaminas, Minerais e Outros")
        } footer: {
            Text("Quantidades \(basis), como no rótulo. A %VRN usa os valores de referência da UE (aminoácidos, creatina e afins não têm).")
        }
    }
}

/// A read-only nutrition label for an amount (a recipe, a day): the rows that are stated, then
/// the vitamins/minerals with %VRN. Goes inside a `List`/`Form`.
struct NutritionFactsRows: View {
    let amounts: NutritionAmounts

    var body: some View {
        row("Energia", "\(Int(amounts.calories.rounded())) kcal · \(Int((amounts.calories * 4.184).rounded())) kJ")
        grams("Lípidos", amounts.fat)
        grams("dos quais saturados", amounts.saturatedFat, indented: true)
        grams("Hidratos de carbono", amounts.carbs)
        grams("dos quais açúcares", amounts.sugars, indented: true)
        grams("Fibra", amounts.fiber)
        grams("Proteína", amounts.protein)
        grams("Sal", amounts.salt)
        ForEach(Micronutrient.allCases.filter { amounts.micronutrients[$0] != nil }) { nutrient in
            let amount = amounts.micronutrients[nutrient] ?? 0
            let percent = nutrient.percentOfReference(amount).map { " (\(Int($0.rounded()))%)" } ?? ""
            row(nutrient.displayName, "\(Self.format(amount)) \(nutrient.unit)\(percent)")
        }
        if let bcaa = amounts.bcaaTotal {
            row("BCAA total", "\(Self.format(bcaa)) g")
        }
    }

    @ViewBuilder
    private func grams(_ title: String, _ value: Double?, indented: Bool = false) -> some View {
        if let value {
            row(title, "\(Self.format(value)) g", indented: indented)
        }
    }

    private func row(_ title: String, _ value: String, indented: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(indented ? .secondary : .primary)
                .padding(.leading, indented ? 16 : 0)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// Like a label: whole numbers from 100, one decimal from 1, two below (0.33 mg of B1).
    static func format(_ value: Double) -> String {
        if value >= 100 { return String(Int(value.rounded())) }
        let digits = value >= 1 ? 1 : 2
        let factor = pow(10, Double(digits))
        let rounded = (value * factor).rounded() / factor
        if rounded.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(rounded)) }
        return String(format: "%.\(digits)f", rounded)
    }
}
