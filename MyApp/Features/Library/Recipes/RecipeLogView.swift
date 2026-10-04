import SwiftUI

/// Logs a recipe with the amounts actually eaten: every ingredient with a field for its amount
/// (in g / ml / units), prefilled with the recipe's default — 0 leaves it out (e.g. the olive oil
/// that wasn't used) — and the totals for those amounts. With `groupID` it changes the amounts of
/// a recipe already logged instead.
///
/// The amounts belong to this log only; each ingredient stays linked to its food, so editing the
/// food later re-adjusts the entry whatever the amount.
struct RecipeLogView: View {
    @Environment(DataStore.self) private var store

    let recipe: Recipe
    let date: Date
    let groupID: UUID?
    let onDone: () -> Void

    /// The ingredients shown: the recipe's, plus (when editing) foods logged in the group that
    /// are no longer in the recipe. `quantity` is the default, in doses.
    @State private var lines: [RecipeItem] = []
    /// The amount typed for each line (by line id), in the food's own unit.
    @State private var amounts: [UUID: String] = [:]
    @State private var mealType: MealType
    /// When it was eaten — like a single food's entry, the time can be changed.
    @State private var logDate: Date
    @State private var didLoad = false

    /// `date` is the day to log on (for today, the current time is used instead of midnight), or —
    /// when editing — the time it was logged at.
    init(recipe: Recipe, date: Date, mealType: MealType, groupID: UUID? = nil, onDone: @escaping () -> Void) {
        self.recipe = recipe
        self.date = date
        self.groupID = groupID
        self.onDone = onDone
        _mealType = State(initialValue: mealType)
        _logDate = State(initialValue: groupID == nil && Calendar.current.isDateInToday(date) ? .now : date)
    }

    /// The lines with the typed amounts, in doses (unreadable or empty = 0, left out).
    private var chosen: [RecipeItem] {
        lines.compactMap { line in
            guard let food = food(line.foodItemID) else { return nil }
            var item = line
            item.quantity = doses(of: food, text: amounts[line.id] ?? "")
            return item
        }
    }

    private var included: [RecipeItem] { chosen.filter { $0.quantity > 0 } }

    private var isDefault: Bool {
        lines.allSatisfy { line in
            guard let food = food(line.foodItemID), let original = recipe.items.first(where: { $0.id == line.id }) else {
                return false
            }
            return abs(doses(of: food, text: amounts[line.id] ?? "") - original.quantity) < 0.0001
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(lines) { line in
                    if let food = food(line.foodItemID) {
                        ingredientRow(line, food: food)
                    }
                }
                if !isDefault {
                    Button {
                        resetToRecipe()
                    } label: {
                        Label("Repor Quantidades da Receita", systemImage: "arrow.uturn.backward")
                    }
                }
            } header: {
                Text("Quanto Comeste")
            } footer: {
                Text("Começa nas quantidades da receita. Deixa a 0 o que não usaste. Os valores de cada ingrediente vêm sempre do alimento: se o alterares, este registo acompanha.")
            }

            Section("Registo") {
                Picker("Refeição", selection: $mealType) {
                    ForEach(MealType.allCases) { meal in
                        Label(meal.displayName, systemImage: meal.symbolName).tag(meal)
                    }
                }
                DatePicker("Data", selection: $logDate)
            }

            if !included.isEmpty {
                Section {
                    NutritionFactsRows(amounts: store.fullNutrition(of: included))
                } header: {
                    Text("Total · \(store.amountSummary(of: included))")
                }
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(groupID == nil ? "Registar" : "Guardar") { save() }
                    .disabled(included.isEmpty)
            }
        }
    }

    private func ingredientRow(_ line: RecipeItem, food: FoodItem) -> some View {
        let quantity = doses(of: food, text: amounts[line.id] ?? "")
        let inRecipe = recipe.items.contains { $0.id == line.id }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .foregroundStyle(quantity > 0 ? .primary : .secondary)
                Group {
                    if !inRecipe {
                        Text("Já não está na receita")
                    } else if quantity > 0 {
                        Text("\(food.scaledCalories(quantity: quantity)) kcal")
                    } else {
                        Text("Não incluído")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("0", text: Binding(
                get: { amounts[line.id] ?? "" },
                set: { amounts[line.id] = $0 }
            ))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(food.unit.shortLabel)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        lines = recipe.items
        guard let groupID else {
            resetToRecipe()
            return
        }
        // Editing: the amounts that were logged; a recipe ingredient not logged starts at 0.
        let logged = store.entries(inGroup: groupID)
        for line in recipe.items {
            let quantity = logged.first { $0.foodItemID == line.foodItemID }?.quantity ?? 0
            amounts[line.id] = amountText(food(line.foodItemID), quantity: quantity)
        }
        for entry in logged {
            guard let foodID = entry.foodItemID, let quantity = entry.quantity,
                  !lines.contains(where: { $0.foodItemID == foodID }) else { continue }
            let extra = RecipeItem(foodItemID: foodID, quantity: 0)
            lines.append(extra)
            amounts[extra.id] = amountText(food(foodID), quantity: quantity)
        }
    }

    private func resetToRecipe() {
        for line in lines {
            let quantity = recipe.items.first { $0.id == line.id }?.quantity ?? 0
            amounts[line.id] = amountText(food(line.foodItemID), quantity: quantity)
        }
    }

    private func save() {
        if let groupID {
            store.relogRecipe(recipe, group: groupID, items: chosen, mealType: mealType, date: logDate)
        } else {
            store.logRecipe(recipe, items: chosen, mealType: mealType, date: logDate)
            AppAnalytics.log(.entryLogged(source: .recipe, mealType: mealType))
        }
        onDone()
    }

    private func food(_ id: UUID) -> FoodItem? {
        store.foodItems.first { $0.id == id }
    }

    private func amountText(_ food: FoodItem?, quantity: Double) -> String {
        guard let food, quantity > 0 else { return "0" }
        return RecipeIngredientEditorView.number(quantity * food.doseSize)
    }

    /// The amount typed, in the food's unit, as doses (0 when empty or unreadable).
    private func doses(of food: FoodItem, text: String) -> Double {
        guard food.doseSize > 0,
              let amount = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")),
              amount > 0 else { return 0 }
        return amount / food.doseSize
    }
}

#Preview {
    NavigationStack {
        RecipeLogView(recipe: Recipe(name: "Arroz com Frango", items: []), date: .now, mealType: .lunch) {}
    }
    .environment(DataStore())
}
