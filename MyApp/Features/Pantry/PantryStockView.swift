import SwiftUI

/// Everything in stock, one row per food (all its lots added up), at every location or one,
/// searchable. Tapping a food shows its lots.
struct PantryStockView: View {
    @Environment(DataStore.self) private var store

    @State private var locationID: UUID?
    @State private var searchText = ""
    @State private var showingEntry = false

    private struct FoodStock: Identifiable {
        let food: FoodItem
        let total: Double
        let nextExpiry: Date?
        let hasExpired: Bool
        var id: UUID { food.id }
    }

    private var rows: [FoodStock] {
        let today = Calendar.current.startOfDay(for: .now)
        let lots = store.pantryLots.filter { locationID == nil || $0.locationID == locationID }
        let byFood = Dictionary(grouping: lots, by: \.foodItemID)
        return store.foodItems
            .filter { byFood[$0.id] != nil }
            .filteredAndSorted(searchText: searchText, order: .name)
            .map { food in
                let foodLots = byFood[food.id] ?? []
                return FoodStock(
                    food: food,
                    total: foodLots.reduce(0) { $0 + $1.remaining },
                    nextExpiry: foodLots.compactMap(\.expiresOn).min(),
                    hasExpired: foodLots.contains { $0.expiresOn.map { $0 < today } ?? false }
                )
            }
    }

    var body: some View {
        List {
            if store.pantryLocations.count > 1 {
                Picker("Local", selection: $locationID) {
                    Text("Todos").tag(UUID?.none)
                    ForEach(store.pantryLocations) { location in
                        Text(location.name).tag(UUID?.some(location.id))
                    }
                }
            }

            if store.pantryLots.isEmpty {
                ContentUnavailableView {
                    Label("Stock vazio", systemImage: "refrigerator")
                } description: {
                    Text("Regista o que compraste para saberes o que tens em casa e quando expira.")
                } actions: {
                    Button("Registar Entrada") { showingEntry = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if rows.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                Section("\(rows.count) \(rows.count == 1 ? "alimento" : "alimentos")") {
                    ForEach(rows) { row in
                        NavigationLink {
                            PantryFoodLotsView(foodID: row.food.id)
                        } label: {
                            stockRow(row)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Procurar no stock")
        .navigationTitle("Stock de Alimentos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEntry = true
                } label: {
                    Label("Registar Entrada", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEntry) {
            PantryEntryView()
        }
    }

    private func stockRow(_ row: FoodStock) -> some View {
        HStack {
            PhotoThumbnail(photoID: row.food.photoID, placeholder: "carrot")
            VStack(alignment: .leading, spacing: 2) {
                Text(row.food.brand.map { "\(row.food.name) (\($0))" } ?? row.food.name)
                if let nextExpiry = row.nextExpiry {
                    Text(row.hasExpired ? "Tem lotes fora de validade" : "Validade: \(nextExpiry.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(row.hasExpired ? .red : .secondary)
                }
            }
            Spacer()
            Text(PantryFormat.amount(row.total, unit: row.food.unit))
                .monospacedDigit()
        }
    }
}

/// One food's lots: where each is, how much is left and its expiry date. Each can be edited
/// (e.g. after using some outside a meal prep) or removed.
struct PantryFoodLotsView: View {
    @Environment(DataStore.self) private var store

    let foodID: UUID

    @State private var lotToEdit: PantryLot?
    @State private var showingEntry = false
    @State private var showingFood = false

    private var food: FoodItem? { store.foodItems.first { $0.id == foodID } }

    private var lots: [PantryLot] {
        store.pantryLots
            .filter { $0.foodItemID == foodID }
            .sorted { ($0.expiresOn ?? .distantFuture) < ($1.expiresOn ?? .distantFuture) }
    }

    var body: some View {
        List {
            if let food {
                Section {
                    LabeledContent("Total", value: PantryFormat.amount(lots.reduce(0) { $0 + $1.remaining }, unit: food.unit))
                    LabeledContent("Dentro da validade", value: PantryFormat.amount(store.pantryStock(of: foodID), unit: food.unit))
                }

                Section {
                    ForEach(lots) { lot in
                        Button {
                            lotToEdit = lot
                        } label: {
                            lotRow(lot, food: food)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        store.deletePantryLots(withIDs: Set(offsets.map { lots[$0].id }))
                    }
                } header: {
                    Text("Lotes")
                } footer: {
                    Text("Cada entrada fica com o seu local e validade. Nas marmitas usa-se primeiro o que expira mais cedo. Desliza para retirar.")
                }

                Section {
                    Button {
                        showingFood = true
                    } label: {
                        Label("Ver Alimento no Catálogo", systemImage: "carrot")
                    }
                }
            }
        }
        .navigationTitle(food?.name ?? "Alimento")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEntry = true
                } label: {
                    Label("Registar Entrada", systemImage: "plus")
                }
            }
        }
        .sheet(item: $lotToEdit) { lot in
            NavigationStack {
                PantryLotEditorView(lot: lot)
            }
        }
        .sheet(isPresented: $showingEntry) {
            PantryEntryView(preselected: [foodID])
        }
        .sheet(isPresented: $showingFood) {
            if let food {
                FoodItemEditorView(itemToEdit: food)
            }
        }
    }

    private func lotRow(_ lot: PantryLot, food: FoodItem) -> some View {
        let today = Calendar.current.startOfDay(for: .now)
        let expired = lot.expiresOn.map { $0 < today } ?? false
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.pantryLocation(withID: lot.locationID)?.name ?? "—")
                Group {
                    if let expiresOn = lot.expiresOn {
                        Text((expired ? "Expirou a " : "Válido até ") + expiresOn.formatted(date: .abbreviated, time: .omitted))
                    } else {
                        Text("Sem validade")
                    }
                }
                .font(.caption)
                .foregroundStyle(expired ? .red : .secondary)
            }
            Spacer()
            Text(PantryFormat.amount(lot.remaining, unit: food.unit))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

/// Edits one lot: what's left, where it is and its expiry date — or removes it.
struct PantryLotEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let lot: PantryLot

    @State private var amountText = ""
    @State private var inputUnit: MeasurementUnit = .gram
    @State private var locationID: UUID?
    @State private var hasExpiry = false
    @State private var expiresOn = Date.now
    @State private var didLoad = false

    private var food: FoodItem? { store.foodItems.first { $0.id == lot.foodItemID } }

    private var amount: Double? {
        LabelNutritionText.number(amountText).map { $0 * inputUnit.baseMultiplier }
    }

    var body: some View {
        Form {
            if let food {
                Section {
                    LabeledContent("Alimento", value: food.name)
                    HStack {
                        Text("Quantidade")
                        Spacer()
                        TextField("0", text: $amountText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        UnitMenu(unit: $inputUnit, baseUnit: food.unit.baseUnit)
                    }
                    Picker("Local", selection: $locationID) {
                        ForEach(store.pantryLocations) { location in
                            Text(location.name).tag(UUID?.some(location.id))
                        }
                    }
                    Toggle("Tem validade", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Validade", selection: $expiresOn, displayedComponents: .date)
                    }
                } footer: {
                    Text("A 0 o lote sai do stock.")
                }

                Section {
                    Button("Retirar do Stock", role: .destructive) {
                        store.deletePantryLots(withIDs: [lot.id])
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Lote")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { save() }
                    .disabled(amount == nil || locationID == nil)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        inputUnit = food?.unit.baseUnit ?? .gram
        amountText = RecipeIngredientEditorView.number(lot.remaining)
        locationID = lot.locationID
        hasExpiry = lot.expiresOn != nil
        expiresOn = lot.expiresOn ?? .now
    }

    private func save() {
        guard let amount, let locationID else { return }
        var updated = lot
        updated.remaining = amount
        updated.locationID = locationID
        updated.expiresOn = hasExpiry ? Calendar.current.startOfDay(for: expiresOn) : nil
        store.updatePantryLot(updated)
        dismiss()
    }
}

/// g ↔ kg, ml ↔ L; nothing to choose for units.
struct UnitMenu: View {
    @Binding var unit: MeasurementUnit
    let baseUnit: MeasurementUnit

    var body: some View {
        let options = MeasurementUnit.compatible(with: baseUnit)
        if options.count > 1 {
            Picker("Unidade", selection: $unit) {
                ForEach(options) { option in
                    Text(option.shortLabel).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        } else {
            Text(baseUnit == .unit ? "unid." : baseUnit.shortLabel)
                .foregroundStyle(.secondary)
        }
    }
}
