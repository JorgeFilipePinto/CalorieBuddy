import SwiftUI

/// The meal-prep plans: still to cook (with what's missing from the stock) and already cooked.
struct MealPrepListView: View {
    @Environment(DataStore.self) private var store

    @State private var newPrep: MealPrep?

    private var planned: [MealPrep] {
        store.mealPreps.filter { $0.cookedAt == nil }.sorted { $0.createdAt > $1.createdAt }
    }

    private var cooked: [MealPrep] {
        store.mealPreps.filter { $0.cookedAt != nil }.sorted { ($0.cookedAt ?? .distantPast) > ($1.cookedAt ?? .distantPast) }
    }

    var body: some View {
        List {
            if store.mealPreps.isEmpty {
                ContentUnavailableView {
                    Label("Sem marmitas planeadas", systemImage: "takeoutbag.and.cup.and.straw")
                } description: {
                    Text("Escolhe receitas, quantas marmitas e o peso de cada uma já cozinhada. A app diz quanto pesar de cada ingrediente em cru e o que falta comprar.")
                } actions: {
                    Button("Planear Marmitas") { newPrep = Self.blankPrep(store: store) }
                        .buttonStyle(.borderedProminent)
                }
            }
            if !planned.isEmpty {
                Section("Por Cozinhar") {
                    ForEach(planned) { prep in
                        NavigationLink {
                            MealPrepEditorView(prep: prep)
                        } label: {
                            prepRow(prep)
                        }
                    }
                    .onDelete { offsets in offsets.map { planned[$0] }.forEach(store.deleteMealPrep) }
                }
            }
            if !cooked.isEmpty {
                Section("Cozinhadas") {
                    ForEach(cooked) { prep in
                        NavigationLink {
                            MealPrepEditorView(prep: prep)
                        } label: {
                            prepRow(prep)
                        }
                    }
                    .onDelete { offsets in offsets.map { cooked[$0] }.forEach(store.deleteMealPrep) }
                }
            }
        }
        .navigationTitle("Marmitas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newPrep = Self.blankPrep(store: store)
                } label: {
                    Label("Planear Marmitas", systemImage: "plus")
                }
            }
        }
        .navigationDestination(item: $newPrep) { prep in
            MealPrepEditorView(prep: prep)
        }
    }

    private func prepRow(_ prep: MealPrep) -> some View {
        let plan = store.mealPrepPlan(for: prep)
        return VStack(alignment: .leading, spacing: 2) {
            Text(prep.name)
            Group {
                if let cookedAt = prep.cookedAt {
                    Text("\(plan.totalBoxes) marmitas · cozinhadas a \(cookedAt.formatted(date: .abbreviated, time: .omitted))")
                } else if plan.requirements.isEmpty {
                    Text("Sem receitas")
                } else if plan.shoppingList.isEmpty {
                    Text("\(plan.totalBoxes) marmitas · tudo em stock")
                } else {
                    Text("\(plan.totalBoxes) marmitas · faltam \(plan.shoppingList.count) \(plan.shoppingList.count == 1 ? "ingrediente" : "ingredientes")")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    static func blankPrep(store: DataStore) -> MealPrep {
        MealPrep(name: "Marmitas \(Date.now.formatted(.dateTime.day().month(.abbreviated)))", items: [],
                 locationID: store.pantryLocations.count == 1 ? store.pantryLocations.first?.id : nil)
    }
}

extension MealPrep: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One meal prep: the recipes with how many boxes and the cooked weight in each, then what that
/// means — per box, raw and cooked amounts of every ingredient; all together, the raw amounts to
/// weigh against the chosen stock — the shopping list (exportable, e.g. to Notes) and marking it
/// as cooked, which takes the ingredients out of the stock.
///
/// Changes save as they're made (once it has a recipe).
struct MealPrepEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: MealPrep
    @State private var showingRecipePicker = false
    @State private var weightTexts: [UUID: String] = [:]
    @State private var showingCookConfirmation = false
    @State private var cookResult: String?
    @State private var copied = false

    init(prep: MealPrep) {
        _draft = State(initialValue: prep)
        _weightTexts = State(initialValue: Dictionary(uniqueKeysWithValues: prep.items.map { item in
            (item.id, item.cookedWeightPerBox.map { RecipeIngredientEditorView.number($0) } ?? "")
        }))
    }

    private var plan: MealPrepPlan { store.mealPrepPlan(for: draft) }

    private var locationName: String {
        store.pantryLocation(withID: draft.locationID)?.name ?? "todos os locais"
    }

    var body: some View {
        let plan = plan
        Form {
            Section {
                TextField("Nome", text: $draft.name)
                Picker("Cozinhar com o stock de", selection: $draft.locationID) {
                    Text("Todos os locais").tag(UUID?.none)
                    ForEach(store.pantryLocations) { location in
                        Text(location.name).tag(UUID?.some(location.id))
                    }
                }
                if let cookedAt = draft.cookedAt {
                    LabeledContent("Cozinhado", value: cookedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            recipesSection(plan)

            ForEach(plan.recipes) { part in
                perBoxSection(part)
            }

            if draft.cookedAt != nil {
                Section {
                    Button {
                        duplicate()
                    } label: {
                        Label("Duplicar para Voltar a Cozinhar", systemImage: "plus.square.on.square")
                    }
                } footer: {
                    Text("Os ingredientes já saíram do stock. A cópia fica em \"Por Cozinhar\", com a lista de compras atualizada.")
                }
            } else if !plan.requirements.isEmpty {
                requirementsSection(plan)
                shoppingSection(plan)
                Section {
                    Button {
                        showingCookConfirmation = true
                    } label: {
                        Label("Marcar como Cozinhado", systemImage: "frying.pan")
                    }
                } footer: {
                    Text("Tira do stock (\(locationName)) as quantidades a pesar, primeiro o que expira mais cedo.")
                }
            }
        }
        .navigationTitle(draft.name.isEmpty ? "Marmitas" : draft.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: draft) { save() }
        .sheet(isPresented: $showingRecipePicker) {
            MealPrepRecipePicker(excluded: Set(draft.items.map(\.recipeID))) { recipeIDs in
                for id in recipeIDs {
                    draft.items.append(MealPrepItem(recipeID: id, boxes: 5))
                }
            }
        }
        .confirmationDialog("Marcar como cozinhado?", isPresented: $showingCookConfirmation, titleVisibility: .visible) {
            Button("Cozinhado — Tirar do Stock") { markCooked() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("As quantidades a pesar saem do stock (\(locationName)).")
        }
        .alert("Marmitas Cozinhadas", isPresented: Binding(get: { cookResult != nil }, set: { if !$0 { cookResult = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cookResult ?? "")
        }
    }

    // MARK: Sections

    private func recipesSection(_ plan: MealPrepPlan) -> some View {
        Section {
            ForEach($draft.items) { $item in
                if let recipe = store.recipe(withID: item.recipeID) {
                    let part = plan.recipes.first { $0.id == item.id }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recipe.name).font(.headline)
                        Stepper(value: $item.boxes, in: 1...50) {
                            Text("\(item.boxes) \(item.boxes == 1 ? "marmita" : "marmitas")")
                        }
                        HStack {
                            Text("Cozinhado por marmita")
                            Spacer()
                            TextField(part.map { PantryFormat.number($0.cookedPortionWeight) } ?? "—",
                                      text: weightBinding(for: item.id))
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                            Text("g").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .onDelete { offsets in draft.items.remove(atOffsets: offsets) }

            Button {
                showingRecipePicker = true
            } label: {
                Label("Adicionar Receitas", systemImage: "plus.circle")
            }
        } header: {
            Text("Receitas")
        } footer: {
            Text("Peso de cada marmita já cozinhada. Vazio = uma dose da receita como está (o valor em cinzento). As quantidades em cru calculam-se com a variação de cada alimento ao cozinhar.")
        }
    }

    private func perBoxSection(_ part: MealPrepPlan.RecipePart) -> some View {
        Section {
            ForEach(part.ingredients) { ingredient in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.food.name)
                        if let prepared = ingredient.preparedAs {
                            Text("para \(prepared.preparation?.displayName.lowercased() ?? prepared.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        // "cru" only for what changes when cooked ("Arroz Cozido" is weighed as it is).
                        Text(PantryFormat.amount(ingredient.rawPerBox, unit: ingredient.food.unit) + (ingredient.weightChange != 0 ? " cru" : ""))
                            .monospacedDigit()
                        if ingredient.food.unit.baseUnit != .unit, ingredient.weightChange != 0 {
                            Text("\(PantryFormat.amount(ingredient.cookedPerBox, unit: ingredient.food.unit)) cozinhado (\(PantryFormat.percent(ingredient.weightChange)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Por Marmita · \(part.recipe.name)")
        } footer: {
            let totals = store.nutrition(of: part.boxItems)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cada marmita: \(PantryFormat.number(part.cookedBoxWeight)) g cozinhado · \(totals.calories) kcal · \(MacroFormat.macros(totals))")
                if part.hasUnitIngredients {
                    Text("Os ingredientes contados em unidades não entram no peso cozinhado.")
                }
            }
        }
    }

    private func requirementsSection(_ plan: MealPrepPlan) -> some View {
        Section {
            ForEach(plan.requirements) { requirement in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: requirement.missing > 0.0001 ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(requirement.missing > 0.0001 ? .red : .green)
                    Text(requirement.food.name)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(PantryFormat.amount(requirement.rawAmount, unit: requirement.food.unit))
                            .monospacedDigit()
                        Text(requirement.missing > 0.0001
                             ? "tens \(PantryFormat.amount(requirement.available, unit: requirement.food.unit))"
                             : "em stock")
                            .font(.caption)
                            .foregroundStyle(requirement.missing > 0.0001 ? .red : .secondary)
                    }
                }
            }
        } header: {
            Text("A Pesar · \(plan.totalBoxes) Marmitas")
        } footer: {
            Text("Quantidades antes de cozinhar, todas as marmitas juntas, comparadas com o stock de \(locationName) (sem contar o que está fora de validade).")
        }
    }

    @ViewBuilder
    private func shoppingSection(_ plan: MealPrepPlan) -> some View {
        if plan.shoppingList.isEmpty {
            Section {
                Label("Tens tudo em stock", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        } else {
            let text = store.shoppingListText(for: draft, plan: plan)
            Section {
                ForEach(plan.shoppingList) { requirement in
                    LabeledContent(requirement.food.name,
                                   value: PantryFormat.amount(requirement.toBuy, unit: requirement.food.unit))
                }
                ShareLink(item: text, subject: Text("Lista de Compras"), preview: SharePreview("Lista de Compras")) {
                    Label("Exportar Lista (ex: para Notas)", systemImage: "square.and.arrow.up")
                }
                Button {
                    copy(text)
                } label: {
                    Label(copied ? "Copiada" : "Copiar Lista", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            } header: {
                Text("Lista de Compras")
            } footer: {
                Text("O que falta, arredondado para cima. Na app Notas, seleciona as linhas e toca em Lista de Verificação para as ir riscando.")
            }
        }
    }

    // MARK: Actions

    private func weightBinding(for itemID: UUID) -> Binding<String> {
        Binding(
            get: { weightTexts[itemID] ?? "" },
            set: { text in
                weightTexts[itemID] = text
                guard let index = draft.items.firstIndex(where: { $0.id == itemID }) else { return }
                let value = LabelNutritionText.number(text)
                draft.items[index].cookedWeightPerBox = (value ?? 0) > 0 ? value : nil
            }
        )
    }

    private func save() {
        guard !draft.items.isEmpty || store.mealPreps.contains(where: { $0.id == draft.id }) else { return }
        store.saveMealPrep(draft)
    }

    private func markCooked() {
        let missing = store.markMealPrepCooked(draft)
        draft.cookedAt = store.mealPreps.first { $0.id == draft.id }?.cookedAt ?? .now
        Haptics.success()
        if missing.isEmpty {
            cookResult = "Os ingredientes saíram do stock."
        } else {
            let names = missing.keys.compactMap { id in store.foodItems.first { $0.id == id }?.name }.sorted()
            cookResult = "Saiu do stock o que havia. Não chegava para: \(names.joined(separator: ", ")) — confirma o stock destes alimentos."
        }
    }

    private func duplicate() {
        var copy = draft
        copy.id = UUID()
        copy.items = draft.items.map { item in
            var item = item
            item.id = UUID()
            return item
        }
        copy.name = draft.name + " (cópia)"
        copy.createdAt = .now
        copy.cookedAt = nil
        store.saveMealPrep(copy)
        dismiss()
    }

    private func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { copied = false } }
    }
}

/// Picks one or several recipes for a meal prep (searching names and ingredients), or creates
/// a new recipe.
private struct MealPrepRecipePicker: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let excluded: Set<UUID>
    let onPick: ([UUID]) -> Void

    @State private var selection: [UUID] = []
    @State private var searchText = ""
    @State private var showingNewRecipe = false

    private var recipes: [Recipe] {
        store.recipes
            .filter { !excluded.contains($0.id) }
            .filteredAndSorted(searchText: "", order: .name)
            .filter { recipe in
                searchText.isEmpty || SearchMatch.matches(searchText, in: [recipe.name] + recipe.items.compactMap { item in
                    store.foodItems.first { $0.id == item.foodItemID }?.name
                })
            }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingNewRecipe = true
                    } label: {
                        Label("Nova Receita", systemImage: "plus.circle")
                    }
                }
                if recipes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    Section("Receitas (\(recipes.count))") {
                        ForEach(recipes) { recipe in
                            Button {
                                toggle(recipe.id)
                            } label: {
                                HStack {
                                    SelectionMark(isSelected: selection.contains(recipe.id))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(recipe.name)
                                        Text("\(store.totalCalories(for: recipe)) kcal · \(store.amountSummary(of: recipe.items))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Procurar receita ou ingrediente")
            .navigationTitle("Receitas")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selection.isEmpty ? "Adicionar" : "Adicionar (\(selection.count))") {
                        onPick(selection)
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
            }
            .sheet(isPresented: $showingNewRecipe) {
                RecipeEditorView { recipe in
                    if !selection.contains(recipe.id) { selection.append(recipe.id) }
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }
        Haptics.light()
    }
}
