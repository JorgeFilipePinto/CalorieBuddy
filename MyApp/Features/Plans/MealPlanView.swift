import SwiftUI
import UniformTypeIdentifiers

/// Every meal plan, the one in effect today first: several can exist, each with its own dates
/// and priority (the highest-priority plan covering a day applies — same rule as the nutrition
/// plans). Each plan and each of its meals is collapsible; a meal's options are linked to recipes
/// that can be logged straight into the daily log. Plans export/import as self-contained JSON.
struct MealPlanView: View {
    @Environment(DataStore.self) private var store

    @State private var optionToLog: PlanOptionSelection?
    @State private var optionToLink: PlanOptionSelection?
    @State private var recipeToEdit: Recipe?
    @State private var planToSchedule: MealPlan?

    @State private var expandedPlans: Set<UUID> = []
    @State private var expandedMeals: Set<UUID> = []
    @State private var didSetInitialExpansion = false

    @State private var exportURL: URL?
    @State private var showExportMover = false
    @State private var isImporting = false
    @State private var pendingImport: MealPlanFile?
    @State private var planToDelete: MealPlan?
    @State private var errorMessage: String?

    /// In effect today first, then other active plans by priority, then scheduled (soonest
    /// first), then ended (most recent first).
    private var orderedPlans: [ClassifiedPlan<MealPlan>] {
        let classified = store.mealPlans.classifiedPlans(today: .now)
        func rank(_ c: ClassifiedPlan<MealPlan>) -> Int {
            if c.inEffect { return 0 }
            switch c.status {
            case .active: return 1
            case .scheduled: return 2
            case .ended: return 3
            }
        }
        return classified.sorted { a, b in
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            switch a.status {
            case .active: return a.plan.priority != b.plan.priority ? a.plan.priority > b.plan.priority : a.plan.startsOn > b.plan.startsOn
            case .scheduled: return a.plan.startsOn < b.plan.startsOn
            case .ended: return a.plan.startsOn > b.plan.startsOn
            }
        }
    }

    var body: some View {
        List {
            if store.mealPlans.isEmpty {
                ContentUnavailableView {
                    Label("Sem Plano Alimentar", systemImage: "list.clipboard")
                } description: {
                    Text("Importa um plano alimentar (ficheiro JSON exportado pela CalorieBuddy).")
                } actions: {
                    Button("Importar Plano") { isImporting = true }
                }
            } else {
                ForEach(orderedPlans) { classified in
                    planSection(classified)
                }
            }
        }
        .navigationTitle("Plano Alimentar")
        .trackScreen("Plano Alimentar")
        .onAppear(perform: setInitialExpansion)
        .refreshable {
            Haptics.light()
            store.reloadFromDisk()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporting = true
                } label: {
                    Label("Importar Plano", systemImage: "square.and.arrow.down")
                }
            }
        }
        .sheet(item: $optionToLog) { selection in
            NavigationStack {
                LogMealPlanOptionView(meal: selection.meal, option: selection.option, date: .now) {
                    optionToLog = nil
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { optionToLog = nil }
                    }
                }
            }
        }
        .sheet(item: $optionToLink) { selection in
            RecipeLinkPickerView(currentRecipeID: selection.option.recipeID) { recipeID in
                store.linkMealPlanOption(selection.option.id, inMeal: selection.meal.id, ofPlan: selection.planID, toRecipe: recipeID)
            }
        }
        .sheet(item: $recipeToEdit) { recipe in
            RecipeEditorView(recipeToEdit: recipe)
        }
        .sheet(item: $planToSchedule) { plan in
            MealPlanScheduleEditorView(plan: plan)
        }
        .fileMover(isPresented: $showExportMover, file: exportURL) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let file = try store.readMealPlanFile(at: url)
                    if store.mealPlans.contains(where: { $0.id == file.plan.id }) {
                        pendingImport = file
                    } else {
                        performImport(file)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Substituir o plano alimentar?",
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            titleVisibility: .visible,
            presenting: pendingImport
        ) { file in
            Button("Importar e Substituir", role: .destructive) { performImport(file) }
            Button("Cancelar", role: .cancel) { pendingImport = nil }
        } message: { file in
            Text("Já existe o plano “\(file.plan.name)”. É substituído pelo importado. As receitas e alimentos do ficheiro são adicionados ao catálogo; os que já existem mantêm-se como estão.")
        }
        .confirmationDialog(
            "Eliminar o plano alimentar?",
            isPresented: Binding(get: { planToDelete != nil }, set: { if !$0 { planToDelete = nil } }),
            titleVisibility: .visible,
            presenting: planToDelete
        ) { plan in
            Button("Eliminar “\(plan.name)”", role: .destructive) { store.deleteMealPlan(plan) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("As receitas e os alimentos do plano continuam no catálogo.")
        }
        .alert(
            "Erro",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Plan

    private func planSection(_ classified: ClassifiedPlan<MealPlan>) -> some View {
        let plan = classified.plan
        let isExpanded = expandedPlans.contains(plan.id)
        return Section {
            HStack(alignment: .top) {
                Button {
                    withAnimation { toggle(plan.id, in: &expandedPlans) }
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.name)
                                .font(.title3.bold())
                                .foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                PlanStatusBadge(status: classified.status, inEffect: classified.inEffect)
                                if plan.priority > 1 {
                                    PlanPriorityBadge(priority: plan.priority)
                                }
                            }
                            Text(Self.dateRange(plan, status: classified.status))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .padding(.top, 6)
                    }
                    .contentShape(Rectangle())
                }
                // Plain, not borderless: borderless would tint the whole title in the accent red.
                .buttonStyle(.plain)

                Menu {
                    Button {
                        planToSchedule = plan
                    } label: {
                        Label("Datas e Prioridade", systemImage: "calendar")
                    }
                    Button {
                        export(plan)
                    } label: {
                        Label("Exportar Plano", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        planToDelete = plan
                    } label: {
                        Label("Eliminar Plano", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .padding(.leading, 8)
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                if plan.author != nil || plan.prescribedAt != nil || !(plan.notes ?? "").isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if let author = plan.author {
                            Text(author)
                                .foregroundStyle(.secondary)
                        }
                        if let prescribedAt = plan.prescribedAt {
                            Text("Prescrito em \(prescribedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let notes = plan.notes, !notes.isEmpty {
                            Label(notes, systemImage: "info.circle")
                                .font(.subheadline)
                        }
                    }
                }

                DisclosureGroup {
                    MealPlanSummaryView(plan: plan)
                } label: {
                    Label("Resumo Diário", systemImage: "chart.pie")
                }

                ForEach(plan.meals) { meal in
                    DisclosureGroup(isExpanded: binding(for: meal.id, in: $expandedMeals)) {
                        ForEach(meal.options) { option in
                            optionRow(option, in: meal, of: plan)
                        }
                        if let notes = meal.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        MealPlanMealLabel(meal: meal)
                    }
                }
            }
        } header: {
            Text(Self.sectionTitle(classified))
        }
    }

    private static func sectionTitle(_ classified: ClassifiedPlan<MealPlan>) -> String {
        if classified.inEffect { return "Em vigor hoje" }
        switch classified.status {
        case .active: return "Ativo, substituído"
        case .scheduled: return "Agendado"
        case .ended: return "Terminado"
        }
    }

    static func dateRange(_ plan: MealPlan, status: PlanStatus) -> String {
        let hasStart = plan.startsOn > .distantPast
        let start = plan.startsOn.formatted(date: .abbreviated, time: .omitted)
        switch (hasStart, plan.endsOn) {
        case (true, let end?): return "\(start) – \(end.formatted(date: .abbreviated, time: .omitted))"
        case (false, let end?): return "Até \(end.formatted(date: .abbreviated, time: .omitted))"
        case (true, nil): return status == .scheduled ? "A partir de \(start)" : "Desde \(start) · em aberto"
        case (false, nil): return "Sem datas · em aberto"
        }
    }

    // MARK: Options

    private func optionRow(_ option: MealPlanOption, in meal: PlannedMeal, of plan: MealPlan) -> some View {
        let selection = PlanOptionSelection(planID: plan.id, meal: meal, option: option)
        let recipe = option.recipeID.flatMap(store.recipe(withID:))
        return Button {
            if recipe == nil {
                optionToLink = selection
            } else {
                optionToLog = selection
            }
        } label: {
            MealPlanOptionRow(option: option)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            if recipe != nil {
                Button {
                    optionToLog = selection
                } label: {
                    Label("Registar", systemImage: "plus.circle.fill")
                }
                .tint(.green)
            }
        }
        .contextMenu {
            if recipe != nil {
                Button {
                    optionToLog = selection
                } label: {
                    Label("Registar…", systemImage: "plus.circle")
                }
            }
            if let recipe {
                Button {
                    recipeToEdit = recipe
                } label: {
                    Label("Editar Receita", systemImage: "pencil")
                }
            }
            Button {
                optionToLink = selection
            } label: {
                Label(recipe == nil ? "Ligar a Receita" : "Ligar a Outra Receita", systemImage: "link")
            }
        }
    }

    // MARK: Expansion

    /// Opens the plan in effect today, and in it the meal for the current time of day.
    private func setInitialExpansion() {
        guard !didSetInitialExpansion else { return }
        didSetInitialExpansion = true
        guard let current = store.mealPlan(on: .now) else { return }
        expandedPlans.insert(current.id)
        let mealType = MealType.suggested(for: .now)
        if let meal = current.meals.first(where: { $0.mealType == mealType }) {
            expandedMeals.insert(meal.id)
        }
    }

    private func toggle(_ id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func binding(for id: UUID, in set: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { isOpen in
                if isOpen { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) }
            }
        )
    }

    // MARK: Import / export

    private func export(_ plan: MealPlan) {
        do {
            exportURL = try store.exportMealPlanURL(plan)
            showExportMover = true
            AppAnalytics.log(.mealPlanExported)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Imports the plan and opens its dates/priority right away, so a new plan gets scheduled
    /// alongside the existing ones instead of silently overriding (or being overridden by) them.
    private func performImport(_ file: MealPlanFile) {
        let isNew = !store.mealPlans.contains(where: { $0.id == file.plan.id })
        store.importMealPlan(file)
        AppAnalytics.log(.mealPlanImported)
        pendingImport = nil
        expandedPlans.insert(file.plan.id)
        if isNew, let imported = store.mealPlans.first(where: { $0.id == file.plan.id }) {
            planToSchedule = imported
        }
    }
}

/// "Em Vigor" / "Ativo, Substituído" / "Agendado" / "Terminado", as a small coloured capsule.
struct PlanStatusBadge: View {
    let status: PlanStatus
    let inEffect: Bool

    var body: some View {
        let (label, color): (String, Color) = {
            switch status {
            case .active: return inEffect ? ("Em Vigor", .green) : ("Ativo, Substituído", .secondary)
            case .scheduled: return ("Agendado", .blue)
            case .ended: return ("Terminado", .secondary)
            }
        }()
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct PlanPriorityBadge: View {
    let priority: Int

    var body: some View {
        Text("Prioridade \(priority)")
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(.secondary.opacity(0.4)))
            .foregroundStyle(.secondary)
    }
}

/// A meal's collapsed row: name and icon, how many options, and its macro targets.
struct MealPlanMealLabel: View {
    let meal: PlannedMeal

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.name)
                        .font(.headline)
                    Text("\(meal.options.count) \(meal.options.count == 1 ? "opção" : "opções")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: meal.mealType.symbolName)
            }
            Spacer()
            if let targets = MacroFormat.targets(meal) {
                Text(targets)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// Edits a meal plan's name, start/end dates and priority — the same fields and rules as a
/// nutrition plan's schedule.
struct MealPlanScheduleEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let plan: MealPlan

    @State private var name = ""
    @State private var hasStart = true
    @State private var startsOn = Date()
    @State private var isTemporary = false
    @State private var endsOn = Date()
    @State private var priority = 1

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        !trimmedName.isEmpty
            && (!isTemporary || !hasStart || Calendar.current.startOfDay(for: endsOn) >= Calendar.current.startOfDay(for: startsOn))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $name)
                }
                Section {
                    Toggle("Data de Início", isOn: $hasStart.animation())
                    if hasStart {
                        DatePicker("Início", selection: $startsOn, displayedComponents: .date)
                    }
                    Toggle("Plano Temporário", isOn: $isTemporary.animation())
                    if isTemporary {
                        DatePicker("Fim", selection: $endsOn, in: (hasStart ? startsOn : .distantPast)..., displayedComponents: .date)
                    }
                    Picker("Prioridade", selection: $priority) {
                        ForEach(1...5, id: \.self) { level in
                            Text(level == 1 ? "1 — plano normal" : level == 5 ? "5 — máxima" : "\(level)").tag(level)
                        }
                    }
                } header: {
                    Text("Vigência")
                } footer: {
                    Text("Sem data de início, o plano aplica-se desde sempre; sem data de fim, fica em aberto. Quando mais do que um plano alimentar cobre o mesmo dia, aplica-se o de prioridade mais alta (em empate, o que começou mais recentemente) — é esse que aparece em \"Do Plano Alimentar\" no registo do dia.")
                }
            }
            .navigationTitle("Datas e Prioridade")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear(perform: populate)
            .onChange(of: startsOn) {
                if endsOn < startsOn { endsOn = startsOn }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func populate() {
        name = plan.name
        hasStart = plan.startsOn > .distantPast
        startsOn = hasStart ? plan.startsOn : Calendar.current.startOfDay(for: .now)
        isTemporary = plan.endsOn != nil
        endsOn = plan.endsOn ?? startsOn
        priority = plan.priority
    }

    private func save() {
        let calendar = Calendar.current
        store.updateMealPlanSchedule(
            plan.id,
            name: trimmedName,
            startsOn: hasStart ? calendar.startOfDay(for: startsOn) : .distantPast,
            endsOn: isTemporary ? calendar.startOfDay(for: endsOn) : nil,
            priority: priority
        )
        dismiss()
    }
}

/// A meal and one of its options, as a single identifiable value for sheets.
struct PlanOptionSelection: Identifiable {
    var planID: UUID
    var meal: PlannedMeal
    var option: MealPlanOption
    var id: UUID { option.id }
}

/// A meal's name and its macro targets, e.g. "Almoço · P 35 · HC 45 · G 15".
struct MealPlanMealHeader: View {
    let meal: PlannedMeal

    var body: some View {
        HStack {
            Label(meal.name, systemImage: meal.mealType.symbolName)
            Spacer()
            if let targets = MacroFormat.targets(meal) {
                Text(targets)
            }
        }
    }
}

/// One option of a planned meal: its label, the plan's description and the linked recipe's
/// calories and macros (or a warning when it isn't linked to any recipe).
struct MealPlanOptionRow: View {
    @Environment(DataStore.self) private var store
    let option: MealPlanOption

    var body: some View {
        let recipe = option.recipeID.flatMap(store.recipe(withID:))
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                if let details = option.details, !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let recipe {
                    let totals = store.nutrition(for: recipe)
                    Text("\(totals.calories) kcal · \(MacroFormat.macros(totals))")
                        .font(.caption)
                        .foregroundStyle(.tint)
                } else {
                    Label("Sem receita ligada", systemImage: "link.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

enum MacroFormat {
    nonisolated static func grams(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    static func macros(_ totals: NutritionTotals) -> String {
        "P \(grams(totals.protein)) · HC \(grams(totals.carbs)) · G \(grams(totals.fat))"
    }

    /// "P 35 · HC 45 · G 15" from whichever targets the meal has, or `nil` if it has none.
    static func targets(_ meal: PlannedMeal) -> String? {
        let parts = [("P", meal.proteinTarget), ("HC", meal.carbsTarget), ("G", meal.fatTarget)]
            .compactMap { label, value in value.map { "\(label) \(grams($0))" } }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A food amount in its own unit, e.g. "150 g" or "2 unidades".
    static func amount(of food: FoodItem, quantity: Double) -> String {
        let amount = food.doseSize * quantity
        let number = amount.formatted(.number.precision(.fractionLength(0...1)))
        if food.unit == .unit {
            return "\(number) \(amount == 1 ? "unidade" : "unidades")"
        }
        return "\(number) \(food.unit.shortLabel)"
    }
}

/// The sheet shown before logging a plan option: its recipe's foods as an editable list, where
/// each food can be swapped for an equivalent one or have its amount changed, compared against
/// the meal's targets. Meant to be shown inside a `NavigationStack`; `onLogged` runs after
/// logging so the caller can dismiss it.
struct LogMealPlanOptionView: View {
    @Environment(DataStore.self) private var store

    let meal: PlannedMeal
    let option: MealPlanOption
    let onLogged: () -> Void

    @State private var mealType: MealType
    @State private var logDate: Date
    @State private var lines: [RecipeItem] = []
    @State private var didLoadLines = false
    @State private var lineToSubstitute: RecipeItem?

    /// `date` is the day to log on; for today, the current time is used instead of midnight.
    init(meal: PlannedMeal, option: MealPlanOption, date: Date, onLogged: @escaping () -> Void) {
        self.meal = meal
        self.option = option
        self.onLogged = onLogged
        _mealType = State(initialValue: meal.mealType)
        _logDate = State(initialValue: Calendar.current.isDateInToday(date) ? .now : date)
    }

    private var recipe: Recipe? { option.recipeID.flatMap(store.recipe(withID:)) }

    private var isModified: Bool {
        guard let recipe else { return false }
        return lines != recipe.items
    }

    var body: some View {
        Form {
            if let recipe {
                let totals = store.nutrition(of: lines)
                Section {
                    ForEach(lines) { line in
                        if let food = food(line.foodItemID) {
                            Button {
                                lineToSubstitute = line
                            } label: {
                                lineRow(line, food: food, original: recipe.items.first { $0.id == line.id })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onDelete { offsets in lines.remove(atOffsets: offsets) }

                    if isModified {
                        Button {
                            lines = recipe.items
                        } label: {
                            Label("Repor Receita Original", systemImage: "arrow.uturn.backward")
                        }
                    }
                } header: {
                    Text(recipe.name)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Toca num alimento para o trocar por um equivalente ou ajustar a quantidade. Desliza para o remover.")
                        if let details = option.details, !details.isEmpty {
                            Text("Plano: \(details)")
                        }
                    }
                }

                Section("Total") {
                    LabeledContent("Calorias", value: "\(totals.calories) kcal")
                    macroRow("Proteína", value: totals.protein, target: meal.proteinTarget)
                    macroRow("Hidratos de Carbono", value: totals.carbs, target: meal.carbsTarget)
                    macroRow("Gordura", value: totals.fat, target: meal.fatTarget)
                }

                Section("Registo") {
                    Picker("Refeição", selection: $mealType) {
                        ForEach(MealType.allCases) { meal in
                            Label(meal.displayName, systemImage: meal.symbolName).tag(meal)
                        }
                    }
                    DatePicker("Data", selection: $logDate)
                }
            } else {
                ContentUnavailableView(
                    "Sem receita ligada",
                    systemImage: "link.badge.plus",
                    description: Text("Liga esta opção a uma receita no Plano Alimentar para a poderes registar.")
                )
            }
        }
        .navigationTitle(option.label)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didLoadLines, let recipe else { return }
            lines = recipe.items
            didLoadLines = true
        }
        .sheet(item: $lineToSubstitute) { line in
            FoodSubstitutionView(line: line) { updated in
                guard let index = lines.firstIndex(where: { $0.id == updated.id }) else { return }
                lines[index] = updated
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Registar") {
                    if let recipe {
                        store.logFoods(lines, groupName: recipe.name, mealType: mealType, date: logDate, recipeID: recipe.id)
                        logAnalytics(original: recipe.items)
                    }
                    onLogged()
                }
                .disabled(recipe == nil || lines.isEmpty)
            }
        }
    }

    /// Reports the logged option and how much it was customised (no nutrition values).
    private func logAnalytics(original: [RecipeItem]) {
        let pairs = lines.compactMap { line in original.first { $0.id == line.id }.map { (line, $0) } }
        AppAnalytics.log(.entryLogged(source: .mealPlan, mealType: mealType))
        AppAnalytics.log(.mealPlanOptionLogged(
            meal: meal.name,
            option: option.label,
            substitutions: pairs.filter { $0.0.foodItemID != $0.1.foodItemID }.count,
            amountChanges: pairs.filter { $0.0.foodItemID == $0.1.foodItemID && $0.0.quantity != $0.1.quantity }.count
        ))
    }

    private func food(_ id: UUID) -> FoodItem? {
        store.foodItems.first { $0.id == id }
    }

    private func lineRow(_ line: RecipeItem, food lineFood: FoodItem, original: RecipeItem?) -> some View {
        let swappedFrom = original.flatMap { $0.foodItemID == line.foodItemID ? nil : food($0.foodItemID) }
        let amountChanged = original.map { $0.foodItemID == line.foodItemID && $0.quantity != line.quantity } ?? false
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lineFood.name)
                Text(MacroFormat.amount(of: lineFood, quantity: line.quantity))
                    .font(.caption)
                    .foregroundStyle(amountChanged ? .orange : .secondary)
                if let swappedFrom {
                    Label("em vez de \(swappedFrom.name)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text("\(lineFood.scaledCalories(quantity: line.quantity)) kcal")
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.tint)
        }
        .contentShape(Rectangle())
    }

    private func macroRow(_ title: String, value: Double, target: Double?) -> some View {
        LabeledContent(title) {
            if let target {
                Text("\(MacroFormat.grams(value)) g / \(MacroFormat.grams(target)) g")
            } else {
                Text("\(MacroFormat.grams(value)) g")
            }
        }
    }
}

/// Swaps one food of a to-be-logged recipe for another, or changes its amount. Foods whose main
/// macro is the same are offered first as equivalents, with the amount that provides the same
/// quantity of that macro; any other catalog food can be picked too (matched on calories).
struct FoodSubstitutionView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let line: RecipeItem
    let onApply: (RecipeItem) -> Void

    @State private var amountText = ""
    @State private var searchText = ""

    private var currentFood: FoodItem? { store.foodItems.first { $0.id == line.foodItemID } }

    /// The amount typed in, converted back to a number of doses of the current food.
    private var editedQuantity: Double? {
        guard let currentFood, currentFood.baseDoseAmount > 0,
              let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")), amount > 0 else { return nil }
        return amount / currentFood.baseDoseAmount
    }

    private var candidates: [FoodItem] {
        store.foodItems
            .filter { $0.id != line.foodItemID }
            .filteredAndSorted(searchText: searchText, order: .name)
    }

    var body: some View {
        NavigationStack {
            List {
                if let currentFood {
                    let macro = currentFood.dominantMacro
                    let equivalents = candidates.compactMap { food in
                        food.practicalEquivalentQuantity(to: currentFood, quantity: line.quantity).map { (food, $0) }
                    }
                    let equivalentIDs = Set(equivalents.map(\.0.id))
                    let others = candidates.filter { !equivalentIDs.contains($0.id) }

                    Section {
                        HStack {
                            Text("Quantidade")
                            Spacer()
                            TextField("0", text: $amountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text(currentFood.unit == .unit ? "unid." : currentFood.unit.baseUnit.shortLabel)
                                .foregroundStyle(.secondary)
                        }
                        if let editedQuantity {
                            Text(summary(currentFood, quantity: editedQuantity))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(currentFood.name)
                    }

                    if !equivalents.isEmpty {
                        Section {
                            ForEach(equivalents, id: \.0.id) { food, quantity in
                                candidateRow(food, quantity: quantity)
                            }
                        } header: {
                            Text("Equivalentes")
                        } footer: {
                            if let reference = currentFood.amount(of: macro, quantity: line.quantity) {
                                Text("Quantidades calculadas para a mesma \(macro.displayName) (\(MacroFormat.grams(reference)) \(macro.unitLabel)).")
                            }
                        }
                    }

                    if !others.isEmpty {
                        Section {
                            ForEach(others) { food in
                                if let quantity = food.equivalentQuantity(to: currentFood, quantity: line.quantity, matching: .calories) {
                                    candidateRow(food, quantity: quantity)
                                }
                            }
                        } header: {
                            Text("Outros Alimentos")
                        } footer: {
                            Text("Quantidades calculadas para as mesmas calorias.")
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Procurar alimento")
            .navigationTitle("Substituir Alimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") {
                        if let editedQuantity {
                            var updated = line
                            updated.quantity = editedQuantity
                            onApply(updated)
                        }
                        dismiss()
                    }
                    .disabled(editedQuantity == nil)
                }
            }
            .onAppear {
                guard let currentFood else { return }
                amountText = (line.quantity * currentFood.baseDoseAmount).formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
            }
        }
    }

    private func candidateRow(_ food: FoodItem, quantity: Double) -> some View {
        Button {
            onApply(RecipeItem(id: line.id, foodItemID: food.id, quantity: quantity))
            if let currentFood {
                AppAnalytics.log(.foodSubstituted(macro: currentFood.dominantMacro))
            }
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                    Text("\(MacroFormat.amount(of: food, quantity: quantity)) · \(summary(food, quantity: quantity))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func summary(_ food: FoodItem, quantity: Double) -> String {
        let totals = store.nutrition(of: [RecipeItem(foodItemID: food.id, quantity: quantity)])
        return "\(totals.calories) kcal · \(MacroFormat.macros(totals))"
    }
}

/// Daily totals of the plan's targets — calories estimated from the macros (4 kcal/g protein
/// and carbs, 9 kcal/g fat) — with each meal's share.
struct MealPlanSummaryView: View {
    let plan: MealPlan

    private var totals: NutritionTotals {
        plan.meals.reduce(into: NutritionTotals()) { totals, meal in
            totals.protein += meal.proteinTarget ?? 0
            totals.carbs += meal.carbsTarget ?? 0
            totals.fat += meal.fatTarget ?? 0
        }
    }

    static func calories(protein: Double, carbs: Double, fat: Double) -> Int {
        Int((protein * 4 + carbs * 4 + fat * 9).rounded())
    }

    var body: some View {
        let totals = totals
        let calories = Self.calories(protein: totals.protein, carbs: totals.carbs, fat: totals.fat)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(calories) kcal")
                    .font(.title2.bold())
                Spacer()
                Text("por dia")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                tile("Proteína", grams: totals.protein, kcalPerGram: 4, of: calories, color: .blue)
                tile("Hidratos", grams: totals.carbs, kcalPerGram: 4, of: calories, color: .orange)
                tile("Gordura", grams: totals.fat, kcalPerGram: 9, of: calories, color: .pink)
            }
            Divider()
            ForEach(plan.meals.filter { MacroFormat.targets($0) != nil }) { meal in
                HStack {
                    Text(meal.name)
                    Spacer()
                    Text(MacroFormat.targets(meal) ?? "")
                        .foregroundStyle(.secondary)
                    Text("\(Self.calories(protein: meal.proteinTarget ?? 0, carbs: meal.carbsTarget ?? 0, fat: meal.fatTarget ?? 0)) kcal")
                        .monospacedDigit()
                        .frame(minWidth: 64, alignment: .trailing)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private func tile(_ title: String, grams: Double, kcalPerGram: Double, of calories: Int, color: Color) -> some View {
        let share = calories > 0 ? grams * kcalPerGram / Double(calories) : 0
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(MacroFormat.grams(grams)) g")
                .font(.subheadline.bold())
            ProgressView(value: share)
                .tint(color)
            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Quick-log sheet from the daily log: pick an option of the meal plan in effect on `date` and
/// log its recipe.
struct MealPlanPickerView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let date: Date

    var body: some View {
        NavigationStack {
            List {
                if let plan = store.mealPlan(on: date) {
                    Section {
                        Text(plan.name)
                            .font(.headline)
                    } footer: {
                        if store.mealPlans.count > 1 {
                            Text("O plano alimentar em vigor neste dia (o de prioridade mais alta).")
                        }
                    }
                    ForEach(plan.meals) { meal in
                        Section {
                            ForEach(meal.options) { option in
                                NavigationLink {
                                    LogMealPlanOptionView(meal: meal, option: option, date: date) {
                                        dismiss()
                                    }
                                } label: {
                                    MealPlanOptionRow(option: option)
                                }
                            }
                        } header: {
                            MealPlanMealHeader(meal: meal)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        store.mealPlans.isEmpty ? "Sem Plano Alimentar" : "Nenhum Plano em Vigor",
                        systemImage: "list.clipboard",
                        description: Text(store.mealPlans.isEmpty
                            ? "Importa um plano em Alimentos › Plano Alimentar."
                            : "Nenhum plano alimentar cobre este dia. Ajusta as datas em Alimentos › Plano Alimentar.")
                    )
                }
            }
            .navigationTitle("Do Plano Alimentar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}

/// Picks which recipe a meal plan option is linked to (or none).
struct RecipeLinkPickerView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let currentRecipeID: UUID?
    let onSelect: (UUID?) -> Void

    @State private var searchText = ""

    private var visibleRecipes: [Recipe] {
        store.recipes.filteredAndSorted(searchText: searchText, order: .name)
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    select(nil)
                } label: {
                    checkmarkRow(title: "Sem receita", subtitle: nil, isSelected: currentRecipeID == nil)
                }
                .buttonStyle(.plain)

                ForEach(visibleRecipes) { recipe in
                    Button {
                        select(recipe.id)
                    } label: {
                        let totals = store.nutrition(for: recipe)
                        checkmarkRow(
                            title: recipe.name,
                            subtitle: "\(totals.calories) kcal · \(MacroFormat.macros(totals))",
                            isSelected: currentRecipeID == recipe.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Procurar receita")
            .navigationTitle("Ligar a Receita")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private func select(_ recipeID: UUID?) {
        onSelect(recipeID)
        dismiss()
    }

    private func checkmarkRow(title: String, subtitle: String?, isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        MealPlanView()
    }
    .environment(DataStore())
}
