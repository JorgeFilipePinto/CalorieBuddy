import SwiftUI

/// The week board ("Quadro Semanal"): the recipes placed in each meal of the week, with their own
/// amounts, against the nutrition plan (per day, training or rest, and per meal when the plan has
/// a split) or the meal plan. One day at a time; recipes are added with "+", dragged between meals,
/// and opened to change their amounts. Synced with the dashboard's board.
struct WeekBoardView: View {
    @Environment(DataStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit

    @State private var monday = WeekBoard.monday(of: .now)
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var addingTo: MealType?
    @State private var editing: MealBoardPlacement?
    @State private var confirmingClear = false

    private var days: [Date] { WeekBoard.weekDays(from: monday) }
    private var dayKey: String { WeekBoard.dayKey(selectedDay) }

    private func dayType(for date: Date) -> DayType {
        store.boardDayType(for: WeekBoard.dayKey(date)) ?? (healthKit.workouts(on: date).isEmpty ? .rest : .training)
    }

    private func targets(for date: Date) -> NutritionTargets? {
        guard let plan = store.nutritionPlan(on: date) else { return nil }
        return dayType(for: date) == .training ? plan.training : plan.rest
    }

    var body: some View {
        List {
            Section {
                weekHeader
                dayStrip
            }
            daySection
            ForEach(MealType.allCases) { meal in
                mealSection(meal)
            }
        }
        .navigationTitle("Quadro Semanal")
        .trackScreen("Quadro Semanal")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        confirmingClear = true
                    } label: {
                        Label("Limpar Semana", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Tirar todas as receitas desta semana?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Limpar Semana", role: .destructive) {
                store.clearBoard(days: Set(days.map(WeekBoard.dayKey)))
            }
        }
        .sheet(item: $addingTo) { meal in
            BoardRecipePickerView(meal: meal, suggested: store.boardMealTarget(day: selectedDay, meal: meal, dayType: dayType(for: selectedDay))?.suggestedRecipeIDs ?? []) { recipe in
                store.placeRecipe(recipe, day: dayKey, meal: meal)
                Haptics.light()
            }
        }
        .sheet(item: $editing) { placement in
            NavigationStack {
                BoardPlacementEditorView(placement: placement, days: days)
            }
        }
    }

    // MARK: Week and days

    private var weekHeader: some View {
        HStack {
            Button {
                shiftWeek(by: -7)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Semana anterior")
            Spacer()
            Text(weekTitle).font(.headline)
            Spacer()
            Button {
                shiftWeek(by: 7)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Semana seguinte")
        }
    }

    private var weekTitle: String {
        let format = Date.FormatStyle().day().month(.abbreviated)
        guard let first = days.first, let last = days.last else { return "" }
        return "\(first.formatted(format)) – \(last.formatted(format))"
    }

    private func shiftWeek(by days: Int) {
        let calendar = Calendar.current
        monday = calendar.date(byAdding: .day, value: days, to: monday) ?? monday
        selectedDay = calendar.date(byAdding: .day, value: days, to: selectedDay) ?? selectedDay
    }

    private var dayStrip: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { date in
                let key = WeekBoard.dayKey(date)
                let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDay)
                let kcal = store.boardTotals(day: key).calories
                let status = TargetStatus(value: kcal, target: targets(for: date).map { Double($0.kcal) })
                Button {
                    selectedDay = date
                } label: {
                    VStack(spacing: 2) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(date.formatted(.dateTime.day()))
                            .font(.subheadline.weight(isSelected ? .bold : .regular))
                        Circle()
                            .fill(kcal > 0 ? status.color : Color.clear)
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        if Calendar.current.isDateInToday(date) {
                            RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                // Drop a recipe of another day here: it moves to the same meal on this day.
                .dropDestination(for: String.self) { ids, _ in
                    moveDropped(ids, to: date, meal: nil)
                }
            }
        }
    }

    private var daySection: some View {
        let type = dayType(for: selectedDay)
        let plan = store.nutritionPlan(on: selectedDay)
        let targets = targets(for: selectedDay)
        let totals = store.boardTotals(day: dayKey)
        return Section {
            Picker("Tipo de dia", selection: Binding(
                get: { type },
                set: { store.setBoardDayType($0, for: dayKey) }
            )) {
                ForEach(DayType.allCases) { dayType in
                    Label(dayType.displayName, systemImage: dayType.symbolName).tag(dayType)
                }
            }
            .pickerStyle(.segmented)
            TotalRow(label: "Calorias", value: totals.calories, target: targets.map { Double($0.kcal) }, unit: "kcal")
            TotalRow(label: "Proteína", value: totals.protein, target: targets.map { Double($0.proteinG) }, unit: "g")
            TotalRow(label: "Hidratos", value: totals.carbs, target: targets.map { Double($0.carbsG) }, unit: "g")
            TotalRow(label: "Gordura", value: totals.fat, target: targets.map { Double($0.fatG) }, unit: "g")
        } header: {
            Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let plan {
                    Text("Plano: \(plan.name)")
                    if plan.hasMealSplit(on: type) {
                        let split = plan.mealSplitTotals(on: type)
                        let off = targets.map { abs(Double(split.kcal - $0.kcal)) / Double(max($0.kcal, 1)) > 0.05 } ?? false
                        Text("Refeições do plano: \(split.kcal)\(targets.map { " / \($0.kcal)" } ?? "") kcal")
                            .foregroundStyle(off ? .orange : .secondary)
                    }
                } else {
                    Text("Sem plano nutricional para este dia.")
                }
                Text("Um dia com treino registado começa como Treino.")
            }
        }
    }

    // MARK: Meals

    private func mealSection(_ meal: MealType) -> some View {
        let target = store.boardMealTarget(day: selectedDay, meal: meal, dayType: dayType(for: selectedDay))
        let items = store.placements(day: dayKey, meal: meal)
        let totals = store.boardTotals(day: dayKey, meal: meal)
        return Section {
            ForEach(items) { placement in
                placementRow(placement, suggested: target?.suggestedRecipeIDs.contains(placement.recipeID) == true)
            }
            Button {
                addingTo = meal
            } label: {
                Label("Adicionar Receita", systemImage: "plus")
            }
            .dropDestination(for: String.self) { ids, _ in
                moveDropped(ids, to: selectedDay, meal: meal)
            }
        } header: {
            HStack {
                Label(meal.displayName, systemImage: meal.symbolName)
                Spacer()
                if !items.isEmpty || target?.hasMacros == true {
                    MealTargetSummary(totals: totals, target: target, hasItems: !items.isEmpty)
                }
            }
        } footer: {
            if let notes = target?.notes, !notes.isEmpty {
                Label(notes, systemImage: "lightbulb")
            }
        }
    }

    private func placementRow(_ placement: MealBoardPlacement, suggested: Bool) -> some View {
        let recipe = store.recipe(withID: placement.recipeID)
        let totals = store.nutrition(of: placement)
        return Button {
            editing = placement
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if suggested {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                                .accessibilityLabel("Sugerida pelo plano alimentar")
                        }
                        Text(recipe?.name ?? "Receita apagada")
                    }
                    Text("\(Int(totals.calories.rounded())) kcal · P \(Int(totals.protein.rounded())) · C \(Int(totals.carbs.rounded())) · G \(Int(totals.fat.rounded()))"
                         + (recipe.map { placement.isAdjusted(from: $0) } == true ? " · ajustada" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(placement.id.uuidString)
        .dropDestination(for: String.self) { ids, _ in
            moveDropped(ids, to: selectedDay, meal: placement.meal)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deletePlacement(placement)
            } label: {
                Label("Remover", systemImage: "trash")
            }
            Button {
                store.movePlacement(id: placement.id, to: placement.day, meal: placement.meal, copying: true)
            } label: {
                Label("Duplicar", systemImage: "plus.square.on.square")
            }
            .tint(.blue)
        }
        .contextMenu {
            Menu("Mover para Refeição") {
                ForEach(MealType.allCases.filter { $0 != placement.meal }) { meal in
                    Button(meal.displayName) { store.movePlacement(id: placement.id, to: placement.day, meal: meal) }
                }
            }
            Menu("Copiar para Dia") {
                ForEach(days.filter { WeekBoard.dayKey($0) != placement.day }, id: \.self) { date in
                    Button(date.formatted(.dateTime.weekday(.wide).day())) {
                        store.movePlacement(id: placement.id, to: WeekBoard.dayKey(date), meal: placement.meal, copying: true)
                    }
                }
            }
        }
    }

    /// A placed recipe dropped on a meal (or on a day: same meal there). Recipes are dragged by id.
    private func moveDropped(_ ids: [String], to date: Date, meal: MealType?) -> Bool {
        var moved = false
        for id in ids {
            guard let uuid = UUID(uuidString: id), let placement = store.mealBoardPlacements.first(where: { $0.id == uuid }) else { continue }
            store.movePlacement(id: uuid, to: WeekBoard.dayKey(date), meal: meal ?? placement.meal)
            moved = true
        }
        if moved { Haptics.light() }
        return moved
    }
}

extension TargetStatus {
    var color: Color {
        switch self {
        case .none: return .secondary
        case .under: return .orange
        case .on: return .green
        case .over: return .red
        }
    }
}

/// "1 840 / 2 500 kcal" with a bar, coloured by how close it is.
private struct TotalRow: View {
    let label: String
    let value: Double
    let target: Double?
    let unit: String

    var body: some View {
        let status = value > 0 ? TargetStatus(value: value, target: target) : .none
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value.rounded()))\(target.map { " / \(Int($0))" } ?? "") \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(status == .none ? .secondary : status.color)
            }
            if let target, target > 0 {
                ProgressView(value: min(value / target, 1))
                    .tint(status == .none ? .secondary : status.color)
            }
        }
    }
}

/// A meal's totals against its target: "P 30/45 · C 40/60 · G 10/15".
private struct MealTargetSummary: View {
    let totals: BoardTotals
    let target: BoardMealTarget?
    let hasItems: Bool

    var body: some View {
        HStack(spacing: 6) {
            part("P", totals.protein, target?.protein)
            part("C", totals.carbs, target?.carbs)
            part("G", totals.fat, target?.fat)
        }
        .font(.caption2.monospacedDigit())
        .textCase(nil)
    }

    private func part(_ label: String, _ value: Double, _ goal: Double?) -> some View {
        let status = hasItems ? TargetStatus(value: value, target: goal) : .none
        let goalText = goal.map { "/\(Int($0.rounded()))" } ?? ""
        return Text("\(label) \(Int(value.rounded()))\(goalText)")
            .foregroundStyle(status == .none ? .secondary : status.color)
    }
}

/// Picks a recipe for a meal of the board: the meal plan's suggestions first, then every recipe.
private struct BoardRecipePickerView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let meal: MealType
    let suggested: Set<UUID>
    let onPick: (Recipe) -> Void

    @State private var searchText = ""

    private var visible: [Recipe] {
        let sorted = store.recipes.filteredAndSorted(searchText: "", order: .name)
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { recipe in
            SearchMatch.matches(searchText, in: [recipe.name] + recipe.items.compactMap { item in
                store.foodItems.first { $0.id == item.foodItemID }?.name
            })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let suggestions = visible.filter { suggested.contains($0.id) }
                if !suggestions.isEmpty {
                    Section("Sugeridas pelo Plano") {
                        ForEach(suggestions) { row(for: $0) }
                    }
                }
                Section(suggestions.isEmpty ? "" : "Todas") {
                    ForEach(visible.filter { !suggested.contains($0.id) }) { row(for: $0) }
                }
            }
            .overlay {
                if store.recipes.isEmpty {
                    ContentUnavailableView("Sem Receitas", systemImage: "book", description: Text("Cria receitas na Biblioteca para as pores no quadro."))
                }
            }
            .searchable(text: $searchText, prompt: "Nome ou ingrediente")
            .navigationTitle(meal.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private func row(for recipe: Recipe) -> some View {
        let totals = store.nutrition(of: MealBoardPlacement(day: "", meal: meal, recipeID: recipe.id))
        return Button {
            onPick(recipe)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name).foregroundStyle(.primary)
                Text("\(Int(totals.calories.rounded())) kcal · P \(Int(totals.protein.rounded())) · C \(Int(totals.carbs.rounded())) · G \(Int(totals.fat.rounded()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A placed recipe: its day and meal, and the amount of each ingredient on the board only — the
/// recipe itself isn't changed. Live totals for the meal and the whole day.
private struct BoardPlacementEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State var placement: MealBoardPlacement
    let days: [Date]

    private var recipe: Recipe? { store.recipe(withID: placement.recipeID) }

    var body: some View {
        Form {
            Section {
                Picker("Dia", selection: Binding(
                    get: { placement.day },
                    set: { placement.day = $0; save() }
                )) {
                    ForEach(days, id: \.self) { date in
                        Text(date.formatted(.dateTime.weekday(.wide).day().month())).tag(WeekBoard.dayKey(date))
                    }
                }
                Picker("Refeição", selection: Binding(
                    get: { placement.meal },
                    set: { placement.meal = $0; save() }
                )) {
                    ForEach(MealType.allCases) { meal in
                        Text(meal.displayName).tag(meal)
                    }
                }
            }

            if let recipe {
                Section {
                    ForEach(recipe.items) { item in
                        ingredientRow(item)
                    }
                } header: {
                    Text("Quantidades")
                } footer: {
                    Text("Só muda esta refeição no quadro. 0 deixa o ingrediente de fora.")
                }
            }

            Section("Totais") {
                let meal = store.nutrition(of: placement)
                let day = store.boardTotals(day: placement.day)
                LabeledContent("Esta refeição", value: "\(Int(meal.calories.rounded())) kcal · P \(Int(meal.protein.rounded())) · C \(Int(meal.carbs.rounded())) · G \(Int(meal.fat.rounded()))")
                LabeledContent("Dia inteiro", value: "\(Int(day.calories.rounded())) kcal · P \(Int(day.protein.rounded())) · C \(Int(day.carbs.rounded())) · G \(Int(day.fat.rounded()))")
            }

            Section {
                Button {
                    placement.doses = [:]
                    save()
                } label: {
                    Label("Repor Quantidades da Receita", systemImage: "arrow.counterclockwise")
                }
                .disabled(recipe.map { !placement.isAdjusted(from: $0) } ?? true)
                Button {
                    store.movePlacement(id: placement.id, to: placement.day, meal: placement.meal, copying: true)
                    dismiss()
                } label: {
                    Label("Duplicar", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) {
                    store.deletePlacement(placement)
                    dismiss()
                } label: {
                    Label("Remover do Quadro", systemImage: "trash")
                }
            }
        }
        .navigationTitle(recipe?.name ?? "Receita")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("OK") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func ingredientRow(_ item: RecipeItem) -> some View {
        if let food = store.foodItems.first(where: { $0.id == item.foodItemID }) {
            let unit = food.unit.baseUnit.shortLabel
            let doses = placement.doses(of: item)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                    Text("receita: \(PantryFormat.number(item.quantity * food.baseDoseAmount)) \(unit) · \(Int(food.nutrition(quantity: doses).calories.rounded())) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("0", value: Binding(
                    get: { (doses * food.baseDoseAmount * 10).rounded() / 10 },
                    set: { amount in
                        placement.doses[item.id.uuidString] = food.baseDoseAmount > 0 ? max(amount, 0) / food.baseDoseAmount : 0
                        save()
                    }
                ), format: .number)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                Text(unit).foregroundStyle(.secondary)
            }
        } else {
            Text("Alimento que já não está no catálogo (fica de fora).")
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        store.savePlacement(placement)
    }
}
