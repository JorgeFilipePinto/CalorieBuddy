import SwiftUI

struct RecipeEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let recipeToEdit: Recipe?

    @State private var name = ""
    @State private var items: [RecipeItem] = []
    @State private var showingAddComponent = false

    init(recipeToEdit: Recipe? = nil) {
        self.recipeToEdit = recipeToEdit
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !items.isEmpty
    }

    private var totalCalories: Int {
        items.reduce(0) { partial, item in
            guard let food = store.foodItems.first(where: { $0.id == item.foodItemID }) else { return partial }
            return partial + Int((Double(food.calories) * item.quantity).rounded())
        }
    }

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
                                    Text("\(quantityLabel(item.quantity)) × \(food.servingLabel)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(Int((Double(food.calories) * item.quantity).rounded())) kcal")
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
                        Text("Total: \(totalCalories) kcal")
                    }
                }
            }
            .navigationTitle(recipeToEdit == nil ? "Nova Receita" : "Editar Receita")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
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

    private func save() {
        let recipe = Recipe(
            id: recipeToEdit?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            items: items
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

    private var availableFoods: [FoodItem] {
        store.foodItems.filter { !existingFoodIDs.contains($0.id) }
    }

    private var quantity: Double? {
        Double(quantityText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
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
        }
    }
}

#Preview {
    RecipeEditorView()
        .environment(DataStore())
}
