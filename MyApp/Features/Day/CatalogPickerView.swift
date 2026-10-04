import SwiftUI

/// Quick-log sheet: search the catalog and pick one or several foods, then say how much of each
/// and the meal — they're all logged at once.
struct CatalogPickerView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @State private var selection: [UUID] = []
    @State private var showingAmounts = false

    var body: some View {
        NavigationStack {
            FoodSelectionList(selection: $selection)
                .navigationTitle("Do Catálogo")
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
                    FoodAmountsView(foodIDs: selection, confirmTitle: "Registar", initialMeal: MealType.suggested(for: date)) { items, meal in
                        store.logFoodItems(items, mealType: meal, date: date)
                        for _ in items { AppAnalytics.log(.entryLogged(source: .catalog, mealType: meal)) }
                        dismiss()
                    }
                }
        }
    }
}

#Preview {
    CatalogPickerView(date: .now)
        .environment(DataStore())
}
