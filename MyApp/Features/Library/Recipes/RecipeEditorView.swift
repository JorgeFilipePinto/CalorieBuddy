import SwiftUI

struct RecipeEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let recipeToEdit: Recipe?
    /// Called right after saving (e.g. a meal prep adds the new recipe).
    var onSave: ((Recipe) -> Void)?

    @State private var name = ""
    @State private var photoID: UUID?
    @State private var labelPhotoIDs: [UUID] = []
    @State private var items: [RecipeItem] = []
    @State private var searchText = ""
    @State private var showingNewFoodItem = false
    /// Barcode to prefill the new food with (scanned but not in the catalog).
    @State private var newFoodBarcode: String?
    @State private var showingScanner = false
    /// What the scanner read, handled once its sheet is gone (an alert can't show over it).
    @State private var scannedCode: String?
    @State private var unknownBarcode: String?
    @State private var showingJSONImport = false
    @State private var editingItem: RecipeItem?

    init(recipeToEdit: Recipe? = nil, onSave: ((Recipe) -> Void)? = nil) {
        self.recipeToEdit = recipeToEdit
        self.onSave = onSave
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !items.isEmpty
    }

    private var totalCalories: Int {
        items.reduce(0) { partial, item in
            guard let food = store.foodItems.first(where: { $0.id == item.foodItemID }) else { return partial }
            return partial + food.scaledCalories(quantity: item.quantity)
        }
    }

    private var totalCost: Double {
        items.reduce(0) { partial, item in
            guard let food = store.foodItems.first(where: { $0.id == item.foodItemID }),
                  let itemCost = store.cost(for: food, quantity: item.quantity) else { return partial }
            return partial + itemCost
        }
    }

    private var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }

    var body: some View {
        NavigationStack {
            Form {
                #if canImport(UIKit)
                Section("Foto") {
                    PhotoPickerField(photoID: $photoID)
                }
                NutritionLabelPhotosSection(photoIDs: $labelPhotoIDs)
                #endif

                Section("Receita") {
                    TextField("Nome da receita", text: $name)
                }

                Section {
                    TextField("Procurar alimentos", text: $searchText)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        let matches = Array(store.foodItems.filteredAndSorted(searchText: searchText, order: .name).prefix(30))
                        if matches.isEmpty {
                            Text("Nenhum alimento corresponde.").foregroundStyle(.secondary)
                        }
                        ForEach(matches) { food in
                            Button { toggle(food) } label: {
                                HStack {
                                    Text(food.name).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: isSelected(food) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected(food) ? Color.accentColor : .secondary)
                                }
                            }
                            .tint(.primary)
                        }
                    }
                    #if canImport(UIKit)
                    Button { showingScanner = true } label: {
                        Label("Digitalizar Código de Barras", systemImage: "barcode.viewfinder")
                    }
                    #endif
                    Button {
                        newFoodBarcode = nil
                        showingNewFoodItem = true
                    } label: {
                        Label("Criar Novo Alimento", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Ingredientes")
                } footer: {
                    Text(store.foodItems.isEmpty ? "Cria primeiro alimentos no catálogo."
                         : "Procura e marca todos os alimentos da receita; aparecem abaixo para acertares as quantidades.")
                }

                Section {
                    if items.isEmpty {
                        Text("Ainda sem alimentos.").foregroundStyle(.secondary)
                    }
                    ForEach($items) { $item in
                        if let food = store.foodItems.first(where: { $0.id == item.foodItemID }) {
                            IngredientAmountRow(food: food, quantity: $item.quantity,
                                                cost: store.cost(for: food, quantity: item.quantity).map { $0.formatted(.currency(code: currencyCode)) },
                                                onOpen: { editingItem = item })
                        }
                    }
                    .onDelete { offsets in items.remove(atOffsets: offsets) }
                } header: {
                    Text("Selecionados · Quantidades por Omissão")
                } footer: {
                    if !items.isEmpty {
                        Text("Total: \(totalCalories) kcal" + (totalCost > 0 ? " · \(totalCost.formatted(.currency(code: currencyCode)))" : "")
                             + ". Desliza para remover. Ao registar no diário escolhes quanto comeste de cada ingrediente; estas quantidades são só o ponto de partida.")
                    }
                }

                if !items.isEmpty {
                    Section {
                        NutritionFactsRows(amounts: store.fullNutrition(of: items))
                    } header: {
                        Text("Declaração Nutricional · \(store.amountSummary(of: items))")
                    } footer: {
                        Text("Para as quantidades por omissão acima (\(store.amountSummary(of: items)) no total), somada dos ingredientes. Os valores que um ingrediente não indica não entram no total.")
                    }
                }
            }
            .navigationTitle(recipeToEdit == nil ? "Nova Receita" : "Editar Receita")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .barTrailing) {
                    Button {
                        showingJSONImport = true
                    } label: {
                        Label("Importar JSON (IA)", systemImage: "sparkles")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: populateIfEditing)
            .sheet(item: $editingItem) { item in
                if let food = store.foodItems.first(where: { $0.id == item.foodItemID }) {
                    RecipeIngredientEditorView(food: food, quantity: item.quantity) { quantity in
                        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].quantity = quantity }
                    }
                }
            }
            .sheet(isPresented: $showingNewFoodItem) {
                FoodItemEditorView(initialBarcode: newFoodBarcode) { newItem in
                    if !items.contains(where: { $0.foodItemID == newItem.id }) {
                        items.append(RecipeItem(foodItemID: newItem.id, quantity: 1))
                    }
                }
            }
            .sheet(isPresented: $showingScanner, onDismiss: handleScannedCode) {
                BarcodeScannerView { code in scannedCode = code }
            }
            .alert("Alimento Não Encontrado", isPresented: Binding(
                get: { unknownBarcode != nil },
                set: { if !$0 { unknownBarcode = nil } }
            )) {
                Button("Criar Manualmente") {
                    newFoodBarcode = unknownBarcode
                    unknownBarcode = nil
                    showingNewFoodItem = true
                }
                Button("Cancelar", role: .cancel) { unknownBarcode = nil }
            } message: {
                Text("O código \(unknownBarcode ?? "") não está em nenhum alimento do catálogo. Preenche os dados do rótulo para o criar — fica com este código.")
            }
            .sheet(isPresented: $showingJSONImport) {
                JSONImportSheet(
                    title: "Importar Receita",
                    prompt: AIJSONImport.recipePrompt(categories: store.foodCategories.map(\.name)),
                    instructions: "Útil quando não sabes ao detalhe o valor nutricional de cada ingrediente. Um ingrediente com o mesmo nome de um alimento já existente no catálogo é reutilizado em vez de criado outra vez."
                ) { json in
                    try handleJSONImport(json)
                }
            }
        }
    }

    private func isSelected(_ food: FoodItem) -> Bool { items.contains { $0.foodItemID == food.id } }

    /// Ticks a food into the recipe at one dose, or takes it out again.
    private func toggle(_ food: FoodItem) {
        if let index = items.firstIndex(where: { $0.foodItemID == food.id }) {
            items.remove(at: index)
        } else {
            items.append(RecipeItem(foodItemID: food.id, quantity: 1))
        }
    }

    /// A known code adds its food; an unknown one warns and then opens the manual editor with the code filled in.
    private func handleScannedCode() {
        guard let code = scannedCode else { return }
        scannedCode = nil
        guard let food = store.foodItem(forBarcode: code) else {
            unknownBarcode = code
            return
        }
        if !isSelected(food) { toggle(food) }
    }

    private func populateIfEditing() {
        guard let recipe = recipeToEdit else { return }
        name = recipe.name
        items = recipe.items
        photoID = recipe.photoID
        labelPhotoIDs = recipe.labelPhotoIDs
    }

    private func handleJSONImport(_ json: String) throws {
        let payload = try AIJSONImport.decodeRecipe(from: json)
        if name.trimmingCharacters(in: .whitespaces).isEmpty, let payloadName = payload.name {
            name = payloadName.trimmingCharacters(in: .whitespaces)
        }
        // A food already in the recipe gets the imported amount added instead of a second line.
        for item in store.recipeItems(for: payload.items) {
            if let index = items.firstIndex(where: { $0.foodItemID == item.foodItemID }) {
                items[index].quantity += item.quantity
            } else {
                items.append(item)
            }
        }
    }

    private func save() {
        var recipe = Recipe(
            id: recipeToEdit?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            items: items,
            isFavorite: recipeToEdit?.isFavorite ?? false,
            createdAt: recipeToEdit?.createdAt ?? Date(),
            photoID: photoID
        )
        recipe.labelPhotoIDs = labelPhotoIDs
        if recipeToEdit == nil {
            store.addRecipe(recipe)
        } else {
            store.updateRecipe(recipe)
        }
        onSave?(recipe)
        dismiss()
    }
}

/// One selected ingredient: its name (tap to edit the food) and the amount the recipe uses, typed
/// in the food's own unit.
private struct IngredientAmountRow: View {
    let food: FoodItem
    @Binding var quantity: Double
    let cost: String?
    let onOpen: () -> Void

    @State private var text = ""

    var body: some View {
        HStack {
            Button(action: onOpen) {
                VStack(alignment: .leading) {
                    Text(food.name).foregroundStyle(.primary)
                    Text("\(food.scaledCalories(quantity: quantity)) kcal" + (cost.map { " · \($0)" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
            Spacer()
            TextField("0", text: $text)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text(food.unit.shortLabel).foregroundStyle(.secondary)
        }
        .onAppear { text = RecipeIngredientEditorView.number(quantity * food.doseSize) }
        .onChange(of: text) { _, newValue in
            if food.doseSize > 0, let amount = Double(newValue.replacingOccurrences(of: ",", with: ".")), amount > 0 {
                quantity = amount / food.doseSize
            }
        }
    }
}

/// One ingredient of a recipe: how much of it the recipe uses (in the food's own unit), and a way
/// into the food itself — which changes it in every recipe and in the diary, since there's only
/// one version of each food.
struct RecipeIngredientEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let food: FoodItem
    let onSave: (Double) -> Void

    @State private var amountText: String
    @State private var showingFoodEditor = false

    init(food: FoodItem, quantity: Double, onSave: @escaping (Double) -> Void) {
        self.food = food
        self.onSave = onSave
        _amountText = State(initialValue: Self.number(quantity * food.doseSize))
    }

    /// The food as it is now (it may have just been edited).
    private var current: FoodItem { store.foodItems.first { $0.id == food.id } ?? food }

    private var quantity: Double? {
        guard current.doseSize > 0,
              let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")), amount > 0 else { return nil }
        return amount / current.doseSize
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Quantidade por omissão")
                        Spacer()
                        TextField("0", text: $amountText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(current.unit.shortLabel)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("A quantidade por omissão desta receita. Os registos já feitos mantêm as suas quantidades.")
                }

                if let quantity {
                    Section("Nesta Quantidade") {
                        NutritionFactsRows(amounts: current.nutrition(quantity: quantity))
                    }
                }

                Section {
                    Button {
                        showingFoodEditor = true
                    } label: {
                        Label("Editar \(current.name)", systemImage: "pencil")
                    }
                } footer: {
                    Text("Há uma só versão de cada alimento: mudar os valores aqui muda-os em todas as receitas que o usam e nos registos do diário feitos com ele.")
                }
            }
            .navigationTitle(current.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        if let quantity { onSave(quantity) }
                        dismiss()
                    }
                    .disabled(quantity == nil)
                }
            }
            .sheet(isPresented: $showingFoodEditor) {
                FoodItemEditorView(itemToEdit: current)
            }
        }
    }

    /// "20 g", "1.5 unidade", "250 ml" — what `quantity` doses of `food` amount to.
    static func amountLabel(food: FoodItem, quantity: Double) -> String {
        "\(number(quantity * food.doseSize)) \(food.unit.shortLabel)"
    }

    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}

#Preview {
    RecipeEditorView()
        .environment(DataStore())
}
