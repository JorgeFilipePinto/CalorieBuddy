import SwiftUI

struct RecipeEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let recipeToEdit: Recipe?

    @State private var name = ""
    @State private var items: [RecipeItem] = []
    @State private var showingAddComponent = false
    @State private var showingJSONImport = false

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
                Section("Receita") {
                    TextField("Nome da receita", text: $name)
                }

                Section {
                    ForEach(items) { item in
                        if let food = store.foodItems.first(where: { $0.id == item.foodItemID }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(food.name)
                                    HStack(spacing: 4) {
                                        Text("\(quantityLabel(item.quantity)) × \(food.doseLabel)")
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
                            }
                        }
                    }
                    .onDelete { offsets in items.remove(atOffsets: offsets) }

                    Button {
                        showingAddComponent = true
                    } label: {
                        Label("Adicionar Alimento", systemImage: "plus")
                    }
                    .disabled(store.foodItems.isEmpty)
                } header: {
                    Text("Alimentos")
                } footer: {
                    if store.foodItems.isEmpty {
                        Text("Cria primeiro alimentos no catálogo.")
                    } else if !items.isEmpty {
                        Text("Total: \(totalCalories) kcal" + (totalCost > 0 ? " · \(totalCost.formatted(.currency(code: currencyCode)))" : ""))
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
            .sheet(isPresented: $showingAddComponent) {
                RecipeComponentPickerView(existingFoodIDs: Set(items.map(\.foodItemID))) { foodItemID, quantity in
                    items.append(RecipeItem(foodItemID: foodItemID, quantity: quantity))
                }
            }
            .sheet(isPresented: $showingJSONImport) {
                JSONImportSheet(
                    title: "Importar Receita",
                    exampleJSON: AIJSONImport.recipeExample,
                    instructions: "Descreve a refeição a uma IA (ChatGPT ou semelhante) e pede-lhe este formato — útil quando não sabes ao detalhe o valor nutricional de cada componente. \"quantity\" é o número de doses de cada alimento. Um alimento com o mesmo nome de um já existente no catálogo é reutilizado em vez de criado outra vez."
                ) { json in
                    try handleJSONImport(json)
                }
            }
        }
    }

    private func quantityLabel(_ quantity: Double) -> String {
        quantity.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(quantity))
            : String(format: "%.1f", quantity)
    }

    private func populateIfEditing() {
        guard let recipe = recipeToEdit else { return }
        name = recipe.name
        items = recipe.items
    }

    private func handleJSONImport(_ json: String) throws {
        let payload = try AIJSONImport.decodeRecipe(from: json)
        if name.trimmingCharacters(in: .whitespaces).isEmpty, let payloadName = payload.name {
            name = payloadName.trimmingCharacters(in: .whitespaces)
        }
        for itemPayload in payload.items {
            let food = resolvedFoodItem(for: itemPayload.food)
            items.append(RecipeItem(foodItemID: food.id, quantity: itemPayload.quantity ?? 1))
        }
    }

    /// Reuses an existing catalog food with the same name (case-insensitive) instead of creating
    /// a duplicate every time the same ingredient shows up in another AI-generated recipe.
    private func resolvedFoodItem(for payload: FoodImportPayload) -> FoodItem {
        if let existing = store.foodItems.first(where: {
            $0.name.localizedCaseInsensitiveCompare(payload.name) == .orderedSame
        }) {
            return existing
        }
        let newItem = payload.makeFoodItem()
        store.addFoodItem(newItem)
        return newItem
    }

    private func save() {
        let recipe = Recipe(
            id: recipeToEdit?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            items: items,
            isFavorite: recipeToEdit?.isFavorite ?? false,
            createdAt: recipeToEdit?.createdAt ?? Date()
        )
        if recipeToEdit == nil {
            store.addRecipe(recipe)
        } else {
            store.updateRecipe(recipe)
        }
        dismiss()
    }
}

/// Lets the user pick one catalog food (not already in the recipe) and how many servings of it.
private struct RecipeComponentPickerView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existingFoodIDs: Set<UUID>
    let onAdd: (UUID, Double) -> Void

    @State private var selectedFoodID: UUID?
    @State private var quantityText = "1"
    @State private var showingNewFoodItem = false

    private var availableFoods: [FoodItem] {
        store.foodItems.filter { !existingFoodIDs.contains($0.id) }
    }

    private var quantity: Double? {
        Double(quantityText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Alimento", selection: $selectedFoodID) {
                        Text("Escolhe...").tag(UUID?.none)
                        ForEach(availableFoods) { food in
                            Text(food.name).tag(Optional(food.id))
                        }
                    }
                    HStack {
                        Text("Quantidade")
                        Spacer()
                        TextField("1", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                Section {
                    Button {
                        showingNewFoodItem = true
                    } label: {
                        Label("Criar Novo Alimento", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("O novo alimento fica guardado no catálogo e é adicionado à receita automaticamente.")
                }
            }
            .navigationTitle("Adicionar Alimento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adicionar") {
                        if let selectedFoodID, let quantity {
                            onAdd(selectedFoodID, quantity)
                        }
                        dismiss()
                    }
                    .disabled(selectedFoodID == nil || quantity == nil)
                }
            }
            .sheet(isPresented: $showingNewFoodItem) {
                FoodItemEditorView { newItem in
                    onAdd(newItem.id, 1)
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    RecipeEditorView()
        .environment(DataStore())
}
