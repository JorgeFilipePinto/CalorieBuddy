import SwiftUI

/// Quick-log sheet: pick a saved recipe and a meal, logging every food in it at once.
struct RecipePickerView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @State private var selectedRecipe: Recipe?
    @State private var mealType: MealType

    init(date: Date) {
        self.date = date
        _mealType = State(initialValue: MealType.suggested(for: date))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Receita") {
                    if store.recipes.isEmpty {
                        ContentUnavailableView(
                            "Sem receitas",
                            systemImage: "list.bullet.rectangle",
                            description: Text("Cria receitas no separador Alimentos.")
                        )
                    } else {
                        ForEach(store.recipes) { recipe in
                            Button {
                                selectedRecipe = recipe
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(recipe.name)
                                        Text("\(recipe.items.count) alimentos · \(store.totalCalories(for: recipe)) kcal")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedRecipe?.id == recipe.id {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Refeição") {
                    Picker("Refeição", selection: $mealType) {
                        ForEach(MealType.allCases) { meal in
                            Label(meal.displayName, systemImage: meal.symbolName).tag(meal)
                        }
                    }
                }
            }
            .navigationTitle("Registar Receita")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registar") {
                        if let selectedRecipe {
                            store.logRecipe(selectedRecipe, mealType: mealType, date: date)
                        }
                        dismiss()
                    }
                    .disabled(selectedRecipe == nil)
                }
            }
        }
    }
}

#Preview {
    RecipePickerView(date: .now)
        .environment(DataStore())
}
