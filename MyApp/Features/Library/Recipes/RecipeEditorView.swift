import SwiftUI

struct RecipeEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let recipeToEdit: Recipe?

    @State private var name = ""
    @State private var photoID: UUID?
    @State private var labelPhotoIDs: [UUID] = []
    @State private var items: [RecipeItem] = []
    @State private var showingAddComponent = false
    @State private var showingJSONImport = false
    @State private var editingItem: RecipeItem?

    init(recipeToEdit: Recipe? = nil) {
        self.recipeToEdit = recipeToEdit
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
                    ForEach(items) { item in
                        if let food = store.foodItems.first(where: { $0.id == item.foodItemID }) {
                            Button {
                                editingItem = item
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(food.name)
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 4) {
                                            Text(RecipeIngredientEditorView.amountLabel(food: food, quantity: item.quantity))
                                            if let itemCost = store.cost(for: food, quantity: item.quantity) {
                                                Text("· \(itemCost.formatted(.currency(code: currencyCode)))")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(food.scaledCalories(quantity: item.quantity)) kcal")
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .tint(.primary)
                        }
                    }
                    .onDelete { offsets in items.remove(atOffsets: offsets) }

                    Button {
                        showingAddComponent = true
                    } label: {
                        Label("Adicionar Alimentos", systemImage: "plus")
                    }
                    .disabled(store.foodItems.isEmpty)
                } header: {
                    Text("Ingredientes · Quantidades por Omissão")
                } footer: {
                    if store.foodItems.isEmpty {
                        Text("Cria primeiro alimentos no catálogo.")
                    } else if !items.isEmpty {
                        Text("Total: \(totalCalories) kcal" + (totalCost > 0 ? " · \(totalCost.formatted(.currency(code: currencyCode)))" : "")
                             + ". Ao registar no diário escolhes quanto comeste de cada ingrediente; estas quantidades são só o ponto de partida.")
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
                ToolbarItem(placement: .topBarTrailing) {
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
            .sheet(isPresented: $showingAddComponent) {
                RecipeComponentPickerView(existingFoodIDs: Set(items.map(\.foodItemID))) { foodItemID, quantity in
                    items.append(RecipeItem(foodItemID: foodItemID, quantity: quantity))
                }
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
        dismiss()
    }
}

/// Adds ingredients: search the catalog and pick one or several foods (not already in the
/// recipe), then their amounts. A barcode can be scanned too, or a new food created.
private struct RecipeComponentPickerView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existingFoodIDs: Set<UUID>
    let onAdd: (UUID, Double) -> Void

    @State private var selection: [UUID] = []
    @State private var showingAmounts = false
    @State private var showingNewFoodItem = false
    /// Barcode to prefill the new food with (scanned but not in the catalog).
    @State private var newFoodBarcode: String?
    @State private var showingScanner = false
    /// What the scanner read, handled once its sheet is gone (an alert can't show over it).
    @State private var scannedCode: String?
    @State private var unknownBarcode: String?
    @State private var alreadyInRecipe: String?

    var body: some View {
        NavigationStack {
            FoodSelectionList(selection: $selection, excluded: existingFoodIDs) {
                Section {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Digitalizar Código de Barras", systemImage: "barcode.viewfinder")
                    }
                    Button {
                        newFoodBarcode = nil
                        showingNewFoodItem = true
                    } label: {
                        Label("Criar Novo Alimento", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("Escolhe vários alimentos de uma vez. Um código que já está no catálogo seleciona esse alimento; um código novo abre a criação manual com o código preenchido.")
                }
            }
            .navigationTitle("Adicionar Alimentos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selection.isEmpty ? "Seguinte" : "Seguinte (\(selection.count))") { showingAmounts = true }
                        .disabled(selection.isEmpty)
                }
            }
            .navigationDestination(isPresented: $showingAmounts) {
                FoodAmountsView(foodIDs: selection, confirmTitle: "Adicionar") { items, _, _ in
                    for item in items { onAdd(item.foodItemID, item.quantity) }
                    dismiss()
                }
            }
            .sheet(isPresented: $showingNewFoodItem) {
                FoodItemEditorView(initialBarcode: newFoodBarcode) { newItem in
                    onAdd(newItem.id, 1)
                    dismiss()
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
            .alert("Já Está na Receita", isPresented: Binding(
                get: { alreadyInRecipe != nil },
                set: { if !$0 { alreadyInRecipe = nil } }
            )) {
                Button("OK", role: .cancel) { alreadyInRecipe = nil }
            } message: {
                Text("\(alreadyInRecipe ?? "Este alimento") já faz parte da receita — toca nele na lista para mudar a quantidade.")
            }
        }
    }

    /// A known code selects its food; an unknown one warns and then opens the manual editor with
    /// the code filled in.
    private func handleScannedCode() {
        guard let code = scannedCode else { return }
        scannedCode = nil
        guard let food = store.foodItem(forBarcode: code) else {
            unknownBarcode = code
            return
        }
        if existingFoodIDs.contains(food.id) {
            alreadyInRecipe = food.name
        } else if !selection.contains(food.id) {
            selection.append(food.id)
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
                            .keyboardType(.decimalPad)
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
            .navigationBarTitleDisplayMode(.inline)
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
