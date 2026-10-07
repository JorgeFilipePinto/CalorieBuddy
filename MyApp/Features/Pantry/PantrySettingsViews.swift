import SwiftUI

/// The places food is kept (Despensa, Frigorífico, Congelador…): add, rename, remove.
struct PantryLocationsView: View {
    @Environment(DataStore.self) private var store

    @State private var newName = ""
    @State private var locationToRename: PantryLocation?
    @State private var renameText = ""
    @State private var locationToDelete: PantryLocation?

    var body: some View {
        List {
            Section {
                ForEach(store.pantryLocations) { location in
                    let count = store.pantryLots.filter { $0.locationID == location.id }.count
                    Button {
                        renameText = location.name
                        locationToRename = location
                    } label: {
                        LabeledContent(location.name, value: count == 0 ? "vazio" : "\(count) \(count == 1 ? "lote" : "lotes")")
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Apagar", role: .destructive) { locationToDelete = location }
                    }
                }
                HStack {
                    TextField("Novo local (ex: Congelador)", text: $newName)
                    Button("Adicionar") {
                        store.addPantryLocation(PantryLocation(name: newName.trimmingCharacters(in: .whitespaces)))
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Toca num local para lhe mudar o nome; desliza para o apagar (o que lá está sai do stock). São só da comida — os suplementos têm os seus.")
            }
        }
        .navigationTitle("Locais de Stock")
        .alert("Mudar Nome", isPresented: Binding(get: { locationToRename != nil }, set: { if !$0 { locationToRename = nil } })) {
            TextField("Nome", text: $renameText)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if let location = locationToRename, !name.isEmpty { store.renamePantryLocation(location, to: name) }
            }
        }
        .confirmationDialog(
            "Apagar \"\(locationToDelete?.name ?? "")\"?",
            isPresented: Binding(get: { locationToDelete != nil }, set: { if !$0 { locationToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Apagar Local e o Seu Stock", role: .destructive) {
                if let location = locationToDelete { store.deletePantryLocation(location) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Tudo o que está registado neste local sai do stock.")
        }
    }
}

/// How much foods gain or lose when cooked — the reference table (common foods in sports diets,
/// adjustable) — and which catalog foods each value applies to. A food can also have its own
/// value in its editor, which wins over this table.
struct CookingYieldsView: View {
    @Environment(DataStore.self) private var store

    @State private var searchText = ""
    @State private var yieldToEdit: CookingYield?
    @State private var showingReset = false

    private var yields: [CookingYield] {
        store.cookingYields
            .filter { searchText.isEmpty || SearchMatch.matches(searchText, in: [$0.name]) }
            .sorted {
                let byName = $0.name.localizedStandardCompare($1.name)
                if byName != .orderedSame { return byName == .orderedAscending }
                return ($0.method.flatMap { FoodPreparation.allCases.firstIndex(of: $0) } ?? -1)
                    < ($1.method.flatMap { FoodPreparation.allCases.firstIndex(of: $0) } ?? -1)
            }
    }

    /// Catalog foods with their own value.
    private var overridden: [FoodItem] {
        store.foodItems.filter { $0.cookingWeightChange != nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                ForEach(yields) { yield in
                    Button {
                        yieldToEdit = yield
                    } label: {
                        yieldRow(yield)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    store.deleteCookingYields(withIDs: Set(offsets.map { yields[$0].id }))
                }
            } header: {
                Text("Referências")
            } footer: {
                Text("Variação do peso de cru para cozinhado: +160% = 100 g de arroz cru dão 260 g cozido; −25% = 100 g de frango cru dão 75 g grelhado. Cada valor aplica-se aos alimentos do catálogo cujo nome tem todas as palavras da referência (\"Arroz Integral\" ganha a \"Arroz\"), exceto os que já dizem estar cozinhados (\"Arroz Cozido\", \"Frango Grelhado\"…), que não mudam. Valores aproximados: ajusta-os à tua forma de cozinhar.")
            }

            if !overridden.isEmpty {
                Section {
                    ForEach(overridden) { food in
                        LabeledContent(food.name, value: PantryFormat.percent(food.cookingWeightChange ?? 0))
                    }
                } header: {
                    Text("Valor Próprio no Alimento")
                } footer: {
                    Text("Estes alimentos têm o seu valor (no editor do alimento, secção Confeção), que conta em vez da referência.")
                }
            }

            Section {
                Button("Repor Valores de Referência") { showingReset = true }
            }
        }
        .searchable(text: $searchText, prompt: "Procurar")
        .navigationTitle("Variação na Confeção")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    yieldToEdit = CookingYield(name: "", weightChange: 0)
                } label: {
                    Label("Adicionar", systemImage: "plus")
                }
            }
        }
        .onAppear { store.seedCookingYieldsIfEmpty() }
        .sheet(item: $yieldToEdit) { yield in
            NavigationStack {
                CookingYieldEditorView(yield: yield)
            }
        }
        .confirmationDialog("Repor os valores de referência?", isPresented: $showingReset, titleVisibility: .visible) {
            Button("Repor") { store.resetCookingYields() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("As referências originais voltam aos valores iniciais; as que criaste com outros nomes ficam.")
        }
    }

    private func yieldRow(_ yield: CookingYield) -> some View {
        let matches = store.foodItems.filter {
            $0.cookingWeightChange == nil && $0.unit.baseUnit != .unit
                && CookingYield.reference(for: $0.name, in: store.cookingYields)?.id == yield.id
        }.count
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let method = yield.method {
                    Label("\(yield.name) · \(method.nameSuffix)", systemImage: method.symbolName)
                } else {
                    Text(yield.name)
                }
                Text(yield.method != nil
                     ? "Sugerido ao criar esta preparação"
                     : matches == 0 ? "Nenhum alimento do catálogo" : "\(matches) \(matches == 1 ? "alimento" : "alimentos") do catálogo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(PantryFormat.percent(yield.weightChange))
                .monospacedDigit()
                .foregroundStyle(yield.weightChange > 0 ? .green : yield.weightChange < 0 ? .orange : .secondary)
        }
        .contentShape(Rectangle())
    }
}

/// One reference: its name (the words a food's name must have) and the change in %, with the
/// catalog foods it currently applies to.
private struct CookingYieldEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let yield: CookingYield

    @State private var name = ""
    @State private var changeText = ""
    @State private var method: FoodPreparation?
    @State private var didLoad = false

    private var change: Double? { LabelNutritionText.number(changeText.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "−", with: "-")) }

    /// With the name being typed: the foods it would apply to.
    private var matchingFoods: [FoodItem] {
        var preview = store.cookingYields.filter { $0.id != yield.id }
        let candidate = CookingYield(id: yield.id, name: name, weightChange: change ?? 0)
        preview.append(candidate)
        return store.foodItems.filter {
            $0.unit.baseUnit != .unit && CookingYield.reference(for: $0.name, in: preview)?.id == yield.id
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Nome (ex: Arroz Integral)", text: $name)
                Picker("Preparação", selection: $method) {
                    Text("Habitual (qualquer)").tag(FoodPreparation?.none)
                    ForEach(FoodPreparation.cooked) { option in
                        Text(option.displayName).tag(FoodPreparation?.some(option))
                    }
                }
                HStack {
                    Text("Variação")
                    Spacer()
                    TextField("0", text: $changeText)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("%").foregroundStyle(.secondary)
                }
            } footer: {
                if let change {
                    Text("100 g cru → \(RecipeIngredientEditorView.number(max(100 + change, 0))) g cozinhado. Usa um número negativo quando perde peso (ex: −25).")
                }
            }

            Section("Aplica-se a") {
                if matchingFoods.isEmpty {
                    Text("Nenhum alimento do catálogo").foregroundStyle(.secondary)
                } else {
                    ForEach(matchingFoods) { food in
                        HStack {
                            Text(food.name)
                            if food.cookingWeightChange != nil {
                                Spacer()
                                Text("tem valor próprio").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(store.cookingYields.contains { $0.id == yield.id } ? "Referência" : "Nova Referência")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    guard let change else { return }
                    store.saveCookingYield(CookingYield(id: yield.id, name: name.trimmingCharacters(in: .whitespaces), weightChange: change, method: method))
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || change == nil || (change ?? 0) <= -100)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            name = yield.name
            method = yield.method
            changeText = yield.name.isEmpty ? "" : RecipeIngredientEditorView.number(yield.weightChange)
        }
    }
}
