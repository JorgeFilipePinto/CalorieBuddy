import SwiftUI

/// A nutrition plan's split per meal for one kind of day: the protein / carbs / fat expected at
/// each of the diary's meals (each optional) and food suggestions, with what they add up to against
/// the day's targets. Same fields as the dashboard's plan form.
struct PlanMealsEditorView: View {
    let dayType: DayType
    let targets: NutritionTargets
    @Binding var plan: NutritionPlan

    var body: some View {
        Form {
            Section {
                let totals = plan.mealSplitTotals(on: dayType)
                LabeledContent("Proteína", value: "\(PantryFormat.number(totals.protein)) / \(targets.proteinG) g")
                LabeledContent("Hidratos", value: "\(PantryFormat.number(totals.carbs)) / \(targets.carbsG) g")
                LabeledContent("Gordura", value: "\(PantryFormat.number(totals.fat)) / \(targets.fatG) g")
                LabeledContent("Calorias", value: "≈ \(totals.kcal) / \(targets.kcal) kcal")
            } header: {
                Text("Soma das Refeições")
            } footer: {
                Text("Opcional: deixa vazia uma refeição que não se aplica. As calorias saem dos macros (4/4/9).")
            }

            ForEach(MealType.allCases) { meal in
                mealSection(meal)
            }
        }
        .navigationTitle("Refeições — \(dayType.displayName)")
    }

    private func mealSection(_ meal: MealType) -> some View {
        let current = plan.meal(meal, on: dayType) ?? PlanMealTargets()
        let update: (PlanMealTargets) -> Void = { plan.setMeal(meal, on: dayType, to: $0) }
        return Section {
            macroField("Proteína (g)", value: current.proteinG) { var t = current; t.proteinG = $0; update(t) }
            macroField("Hidratos (g)", value: current.carbsG) { var t = current; t.carbsG = $0; update(t) }
            macroField("Gordura (g)", value: current.fatG) { var t = current; t.fatG = $0; update(t) }
            TextField("Sugestões de alimentação", text: Binding(
                get: { current.notes ?? "" },
                set: { text in
                    var t = current
                    t.notes = text.isEmpty ? nil : String(text.prefix(1000))
                    update(t)
                }
            ), axis: .vertical)
            .lineLimit(2...5)
        } header: {
            HStack {
                Label(meal.displayName, systemImage: meal.symbolName)
                Spacer()
                if let kcal = current.kcal {
                    Text("≈ \(kcal) kcal").textCase(nil)
                }
            }
        }
    }

    private func macroField(_ label: String, value: Double?, set: @escaping (Double?) -> Void) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", value: Binding(get: { value }, set: { set($0.map { max($0, 0) }) }), format: .number)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            .multilineTextAlignment(.trailing)
            .frame(width: 90)
        }
    }
}
