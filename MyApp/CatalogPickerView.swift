import SwiftUI

/// Quick-log sheet: pick a catalog food, a quantity and a meal, and log it in one step.
struct CatalogPickerView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @State private var selectedItem: FoodItem?
    @State private var quantityText = "1"
    @State private var mealType: MealType

    init(date: Date) {
        self.date = date
        _mealType = State(initialValue: MealType.suggested(for: date))
    }

    private var quantity: Double? {
        Double(quantityText.replacingOccurrences(of: ",", with: "."))
    }

    private var scaledCalories: Int? {
        guard let selectedItem, let quantity else { return nil }
        return selectedItem.scaledCalories(quantity: quantity)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alimento") {
                    if store.foodItems.isEmpty {
                        ContentUnavailableView(
                            "Catálogo vazio",
                            systemImage: "tray",
                            description: Text("Adiciona alimentos no separador Alimentos.")
                        )
                    } else {
                        Picker("Alimento", selection: $selectedItem) {
                            Text("Escolhe...").tag(FoodItem?.none)
                            ForEach(store.foodItems) { item in
                                Text(item.name).tag(Optional(item))
                            }
                        }
                    }
                }

                if let selectedItem {
                    Section("Quantidade") {
                        HStack {
                            Text("Doses (\(selectedItem.doseLabel))")
                            Spacer()
                            TextField("1", text: $quantityText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        if let scaledCalories {
                            Text("\(scaledCalories) kcal")
                                .foregroundStyle(.secondary)
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
            .navigationTitle("Do Catálogo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registar") {
                        guard let selectedItem, let quantity else { return }
                        store.logFoodItem(selectedItem, quantity: quantity, mealType: mealType, date: date)
                        dismiss()
                    }
                    .disabled(selectedItem == nil || quantity == nil)
                }
            }
        }
    }
}

#Preview {
    CatalogPickerView(date: .now)
        .environment(DataStore())
}
