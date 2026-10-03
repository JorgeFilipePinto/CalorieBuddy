import SwiftUI

/// The "Digitalizar Código de Barras" flow from a day's "+" menu: scan a barcode, check it
/// against the supplements and the food catalog, then:
/// - a supplement → log it (doses, then which stock it came from);
/// - a known food → log it straight away;
/// - an unknown code → either create a food with it, or add it to a supplement already in the
///   library (only existing ones — supplements aren't created here) and log that.
///
/// All steps share this one sheet — the content just swaps as the flow progresses — so
/// scanning, creating, and quantifying reads as a single guided action instead of several
/// separately-launched sheets.
struct ScanAndLogEntryView: View {
    @Environment(DataStore.self) private var store
    let date: Date

    private enum Step {
        case scanning
        case unknownCode(String)
        case choosingSupplement(barcode: String)
        case creatingItem(barcode: String)
        case confirmingQuantity(FoodItem)
        case loggingSupplement(Supplement)
    }

    @State private var step: Step = .scanning

    var body: some View {
        switch step {
        case .scanning:
            BarcodeScannerView(onScan: handleScanned, dismissesAfterScan: false)
        case .unknownCode(let barcode):
            UnknownBarcodeView(
                barcode: barcode,
                hasSupplements: !store.supplements.isEmpty,
                newFood: { step = .creatingItem(barcode: barcode) },
                existingSupplement: { step = .choosingSupplement(barcode: barcode) }
            )
        case .choosingSupplement(let barcode):
            LinkBarcodeToSupplementView(barcode: barcode) { supplement in
                step = .loggingSupplement(supplement)
            }
        case .creatingItem(let barcode):
            FoodItemEditorView(initialBarcode: barcode, dismissesAfterSave: false) { newItem in
                step = .confirmingQuantity(newItem)
            }
        case .confirmingQuantity(let item):
            LogScannedItemView(item: item, date: date)
        case .loggingSupplement(let supplement):
            SupplementPickerView(date: date, supplement: supplement)
        }
    }

    private func handleScanned(_ code: String) {
        if let supplement = store.supplement(forBarcode: code) {
            step = .loggingSupplement(supplement)
        } else if let match = store.foodItem(forBarcode: code) {
            step = .confirmingQuantity(match)
        } else {
            step = .unknownCode(code)
        }
    }
}

/// A code nothing in the app has yet: a new food, or a supplement that's already in the library.
private struct UnknownBarcodeView: View {
    @Environment(\.dismiss) private var dismiss

    let barcode: String
    let hasSupplements: Bool
    let newFood: () -> Void
    let existingSupplement: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(barcode, systemImage: "barcode")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Este código ainda não está em nenhum alimento nem suplemento.")
                }
                Section {
                    Button(action: newFood) {
                        Label("Novo Alimento", systemImage: "fork.knife")
                    }
                    if hasSupplements {
                        Button(action: existingSupplement) {
                            Label("É um Suplemento que Já Tenho", systemImage: "pills.fill")
                        }
                    }
                } footer: {
                    if hasSupplements {
                        Text("Num suplemento, o código fica guardado e da próxima vez é reconhecido logo.")
                    }
                }
            }
            .navigationTitle("Código Desconhecido")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}

/// Picks one of the existing supplements and adds the scanned code to it.
private struct LinkBarcodeToSupplementView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let barcode: String
    let linked: (Supplement) -> Void

    @State private var search = ""

    private var supplements: [Supplement] {
        let all = store.supplements.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(supplements) { supplement in
                Button {
                    if let updated = store.addBarcode(barcode, toSupplement: supplement.id) {
                        linked(updated)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(supplement.name)
                            .foregroundStyle(.primary)
                        Text("dose \(supplement.doseLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // Rows read as a list to pick from, not as red action buttons.
                .tint(.primary)
            }
            .searchable(text: $search, prompt: "Procurar suplemento")
            .navigationTitle("Qual Suplemento?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
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
                        AppAnalytics.log(.entryLogged(source: .barcode, mealType: mealType))
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
