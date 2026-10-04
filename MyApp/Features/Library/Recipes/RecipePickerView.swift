import SwiftUI

/// Quick-log sheet: pick a saved recipe, then say how much of each ingredient was eaten
/// (`RecipeLogView`) and in which meal.
struct RecipePickerView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @State private var path: [UUID] = []
    @State private var searchText = ""

    /// Matches the recipe's name or any of its ingredients ("frango" finds every recipe with chicken).
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
        NavigationStack(path: $path) {
            List {
                if store.recipes.isEmpty {
                    ContentUnavailableView(
                        "Sem receitas",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Cria receitas no separador Alimentos.")
                    )
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    if searchText.isEmpty {
                        UsageSuggestionsSection(
                            suggestions: { store.suggestedRecipes($0) },
                            title: { $0.name },
                            subtitle: { subtitle(for: $0) },
                            isSelected: { _ in false },
                            select: { path = [$0.id] }
                        )
                    }
                    let favorites = visible.filter(\.isFavorite)
                    if !favorites.isEmpty {
                        Section("Favoritas (\(favorites.count))") {
                            ForEach(favorites) { recipeRow($0) }
                        }
                    }
                    let others = visible.filter { !$0.isFavorite }
                    if !others.isEmpty {
                        Section {
                            ForEach(others) { recipeRow($0) }
                        } header: {
                            Text(favorites.isEmpty ? "Receitas (\(others.count))" : "Outras (\(others.count))")
                        } footer: {
                            Text("A seguir escolhes quanto comeste de cada ingrediente. As calorias aqui são para as quantidades da receita.")
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Procurar receita ou ingrediente")
            .navigationTitle("Registar Receita")
            .navigationDestination(for: UUID.self) { id in
                if let recipe = store.recipe(withID: id) {
                    RecipeLogView(recipe: recipe, date: date, mealType: MealType.suggested(for: date)) {
                        dismiss()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private func recipeRow(_ recipe: Recipe) -> some View {
        NavigationLink(value: recipe.id) {
            HStack {
                PhotoThumbnail(photoID: recipe.photoID, placeholder: "list.bullet.rectangle")
                VStack(alignment: .leading) {
                    Text(recipe.name)
                    Text(subtitle(for: recipe))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func subtitle(for recipe: Recipe) -> String {
        "\(recipe.items.count) alimentos · \(store.totalCalories(for: recipe)) kcal"
    }
}

#Preview {
    RecipePickerView(date: .now)
        .environment(DataStore())
}
