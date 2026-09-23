import SwiftUI

/// The "Digitalizar Código de Barras" flow from a day's "+" menu: scan a barcode, check it
/// against the food catalog, then either log it straight away (already known) or create it
/// first (first time seeing this barcode) before logging it.
///
/// All three steps share this one sheet — the content just swaps as the flow progresses — so
/// scanning, creating, and quantifying reads as a single guided action instead of three
/// separately-launched sheets.
struct ScanAndLogEntryView: View {
    @Environment(DataStore.self) private var store
    let date: Date

    private enum Step {
        case scanning
        case creatingItem(barcode: String)
        case confirmingQuantity(FoodItem)
    }

    @State private var step: Step = .scanning

    var body: some View {
        switch step {
        case .scanning:
            BarcodeScannerView(onScan: handleScanned, dismissesAfterScan: false)
        case .creatingItem(let barcode):
            FoodItemEditorView(initialBarcode: barcode, dismissesAfterSave: false) { newItem in
                step = .confirmingQuantity(newItem)
            }
        case .confirmingQuantity(let item):
            LogScannedItemView(item: item, date: date)
        }
    }

    private func handleScanned(_ code: String) {
        if let match = store.foodItem(forBarcode: code) {
            step = .confirmingQuantity(match)
        } else {
            step = .creatingItem(barcode: code)
        }
    }
}

/// A read-only recap of the matched food item, plus a quantity and meal picker — logging a
/// known item after a scan needs nothing else.
private struct LogScannedItemView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let item: FoodItem
    let date: Date

    @State private var quantityText = "1"
    @State private var mealType: MealType

    init(item: FoodItem, date: Date) {
        self.item = item
        self.date = date
        _mealType = State(initialValue: MealType.suggested(for: date))
    }

    private var quantity: Double? {
        Double(quantityText.replacingOccurrences(of: ",", with: "."))
    }

    private var scaledCalories: Int? {
        quantity.map { item.scaledCalories(quantity: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alimento") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.brand.map { "\(item.name) (\($0))" } ?? item.name)
                            .font(.headline)
                        Text("dose \(item.doseLabel) · \(item.scaledCalories(quantity: 1)) kcal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Quantidade") {
                    HStack {
                        Text("Doses (\(item.doseLabel))")
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

                Section("Refeição") {
                    Picker("Refeição", selection: $mealType) {
                        ForEach(MealType.allCases) { meal in
                            Label(meal.displayName, systemImage: meal.symbolName).tag(meal)
                        }
                    }
                }
            }
            .navigationTitle("Registar Alimento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registar") {
                        guard let quantity else { return }
                        store.logFoodItem(item, quantity: quantity, mealType: mealType, date: date)
                        dismiss()
                    }
                    .disabled(quantity == nil)
                }
            }
        }
    }
}

#Preview {
    ScanAndLogEntryView(date: .now)
        .environment(DataStore())
}
