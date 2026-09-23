import SwiftUI

/// Manages the reusable food catalog and the recipes built from it. This is where "already
/// inserted" foods live so they can be scanned/picked quickly, or grouped into a recipe.
struct FoodLibraryView: View {
    @Environment(DataStore.self) private var store

    @State private var showingAddFoodItem = false
    @State private var foodItemToEdit: FoodItem?
    @State private var showingAddRecipe = false
    @State private var recipeToEdit: Recipe?

    var body: some View {
        List {
            Section("Receitas") {
                if store.recipes.isEmpty {
                    Text("Sem receitas guardadas.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.recipes) { recipe in
                        Button {
                            recipeToEdit = recipe
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(recipe.name)
                                    Text("\(recipe.items.count) alimentos · \(store.totalCalories(for: recipe)) kcal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets { store.deleteRecipe(store.recipes[index]) }
                    }
                }
            }

            Section("Catálogo de Alimentos") {
                if store.foodItems.isEmpty {
                    Text("Sem alimentos guardados.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.foodItems) { item in
                        Button {
                            foodItemToEdit = item
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                    HStack(spacing: 4) {
                                        Text("\(item.servingLabel) · \(item.calories) kcal")
                                        if item.barcode != nil {
                                            Image(systemName: "barcode")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets { store.deleteFoodItem(store.foodItems[index]) }
                    }
                }
            }
        }
        .navigationTitle("Alimentos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddFoodItem = true
                    } label: {
                        Label("Novo Alimento", systemImage: "carrot")
                    }
                    Button {
                        showingAddRecipe = true
                    } label: {
                        Label("Nova Receita", systemImage: "list.bullet.rectangle")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddFoodItem) {
            FoodItemEditorView()
        }
        .sheet(item: $foodItemToEdit) { item in
            FoodItemEditorView(itemToEdit: item)
        }
        .sheet(isPresented: $showingAddRecipe) {
            RecipeEditorView()
        }
        .sheet(item: $recipeToEdit) { recipe in
            RecipeEditorView(recipeToEdit: recipe)
        }
    }
}

#Preview {
    NavigationStack {
        FoodLibraryView()
    }
    .environment(DataStore())
}
