import SwiftUI

/// Quick-log sheet: pick a saved recipe, then say how much of each ingredient was eaten
/// (`RecipeLogView`) and in which meal.
struct RecipePickerView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                UsageSuggestionsSection(
                    suggestions: { store.suggestedRecipes($0) },
                    title: { $0.name },
                    subtitle: { subtitle(for: $0) },
                    isSelected: { _ in false },
                    select: { path = [$0.id] }
                )
                Section {
                    if store.recipes.isEmpty {
                        ContentUnavailableView(
                            "Sem receitas",
                            systemImage: "list.bullet.rectangle",
                            description: Text("Cria receitas no separador Alimentos.")
                        )
                    } else {
                        ForEach(store.recipes) { recipe in
                            NavigationLink(value: recipe.id) {
                                VStack(alignment: .leading) {
                                    Text(recipe.name)
                                    Text(subtitle(for: recipe))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Receita")
                } footer: {
                    if !store.recipes.isEmpty {
                        Text("A seguir escolhes quanto comeste de cada ingrediente. As calorias aqui são para as quantidades da receita.")
                    }
                }
            }
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

    private func subtitle(for recipe: Recipe) -> String {
        "\(recipe.items.count) alimentos · \(store.totalCalories(for: recipe)) kcal"
    }
}

#Preview {
    RecipePickerView(date: .now)
        .environment(DataStore())
}
