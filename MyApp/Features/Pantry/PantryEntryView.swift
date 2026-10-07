import SwiftUI

/// Registers stock coming in (e.g. after shopping): pick the foods — searching the catalog, with
/// what's already in stock shown under each, or creating a food that isn't there yet so it's
/// tracked like the rest — or scanning their barcodes one after another — then for each one how
/// much came in, where it goes and until when.
struct PantryEntryView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selection: [UUID]
    @State private var showingAmounts: Bool
    @State private var showingNewFood = false
    /// Barcode to prefill the new food with (scanned but not in the catalog).
    @State private var newFoodBarcode: String?
    @State private var showingScanner = false
    /// What the scanner read, handled once its sheet is gone (an alert can't show over it).
    @State private var scannedCode: String?
    @State private var unknownBarcode: String?
    /// The last scan's result, shown under the buttons ("Azeite selecionado").
    @State private var scanMessage: String?
    @State private var showingAIImport = false
    /// Amount / location / expiry read by the AI, by food, for the next step.
    @State private var prefill: [UUID: PantryEntryPrefill] = [:]

    init(preselected: [UUID] = []) {
        _selection = State(initialValue: preselected)
        _showingAmounts = State(initialValue: !preselected.isEmpty)
    }

    var body: some View {
        NavigationStack {
            FoodSelectionList(selection: $selection, detail: stockDetail, showsSuggestions: false) {
                Section {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Digitalizar Código de Barras", systemImage: "barcode.viewfinder")
                    }
                    Button {
                        showingAIImport = true
                    } label: {
                        Label("Importar com IA (talão ou fotos)", systemImage: "sparkles")
                    }
                    Button {
                        newFoodBarcode = nil
                        showingNewFood = true
                    } label: {
                        Label("Novo Alimento", systemImage: "plus.circle")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let scanMessage {
                            Label(scanMessage, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Text("Digitaliza os produtos um a um: um código do catálogo seleciona o alimento; um código novo cria-o com o código preenchido. Ou procura no catálogo abaixo.")
                    }
                }
                if !inStock.isEmpty {
                    Section("Em Stock (\(inStock.count))") {
                        ForEach(inStock) { food in
                            Button {
                                toggle(food.id)
                            } label: {
                                HStack {
                                    SelectionMark(isSelected: selection.contains(food.id))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(food.brand.map { "\(food.name) (\($0))" } ?? food.name)
                                        if let detail = stockDetail(food) {
                                            Text(detail).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Entrada de Stock")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
                PantryEntryAmountsView(foodIDs: selection, prefill: prefill) { dismiss() }
            }
            .sheet(isPresented: $showingNewFood) {
                FoodItemEditorView(initialBarcode: newFoodBarcode) { food in
                    if !selection.contains(food.id) { selection.append(food.id) }
                    scanMessage = newFoodBarcode == nil ? nil : "\(food.name) criado e selecionado"
                }
            }
            .sheet(isPresented: $showingAIImport) {
                JSONImportSheet(
                    title: "Importar Stock",
                    prompt: AIJSONImport.stockPrompt(categories: store.foodCategories.map(\.name),
                                                     locations: store.pantryLocations.map(\.name)),
                    instructions: "Tira uma foto ao talão das compras ou às embalagens (com a validade à vista). Os alimentos que não estão no catálogo são criados; os que já estão (mesmo nome ou código de barras) são reutilizados. A seguir revês as quantidades, locais e validades antes de guardar."
                ) { json in
                    try importStock(json)
                }
            }
            .sheet(isPresented: $showingScanner, onDismiss: handleScannedCode) {
                BarcodeScannerView { code in scannedCode = code }
            }
            .alert("Alimento Não Encontrado", isPresented: Binding(
                get: { unknownBarcode != nil },
                set: { if !$0 { unknownBarcode = nil } }
            )) {
                Button("Criar Alimento") {
                    newFoodBarcode = unknownBarcode
                    unknownBarcode = nil
                    showingNewFood = true
                }
                Button("Cancelar", role: .cancel) { unknownBarcode = nil }
            } message: {
                Text("O código \(unknownBarcode ?? "") não está em nenhum alimento do catálogo. Cria o alimento com os dados do rótulo — fica no catálogo com este código e entra no stock.")
            }
        }
    }

    /// Takes the AI's lines in: each food found or created in the catalog and selected, with what
    /// the AI read prefilled for the quantities step (opened right after).
    private func importStock(_ json: String) throws {
        let payloads = try AIJSONImport.decodeStock(from: json)
        guard !payloads.isEmpty else { throw AIImportError.empty }
        for payload in payloads {
            let food = store.catalogFood(for: payload.food)
            let importedUnit = payload.food.resolvedUnit
            // The amount counts only in the same kind of unit as the catalog food (g, ml or units).
            let amount = payload.amount.flatMap { value -> Double? in
                guard value > 0, importedUnit.baseUnit == food.unit.baseUnit else { return nil }
                return value * importedUnit.baseMultiplier
            }
            var line = prefill[food.id] ?? PantryEntryPrefill()
            if let amount { line.amount = (line.amount ?? 0) + amount }
            line.expiresOn = payload.resolvedExpiry ?? line.expiresOn
            if let name = payload.location, let location = store.pantryLocations.first(where: {
                SearchMatch.normalized($0.name) == SearchMatch.normalized(name.trimmingCharacters(in: .whitespaces))
            }) {
                line.locationID = location.id
            }
            prefill[food.id] = line
            if !selection.contains(food.id) { selection.append(food.id) }
        }
        scanMessage = "\(payloads.count) \(payloads.count == 1 ? "produto importado" : "produtos importados") — revê e toca em Seguinte"
        // After the import sheet has closed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showingAmounts = true }
    }

    /// What's in stock now — usually what gets bought again.
    private var inStock: [FoodItem] {
        let ids = Set(store.pantryLots.map(\.foodItemID))
        return store.foodItems.filter { ids.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A known code selects its food (kept selected if it already was — e.g. two packs scanned);
    /// an unknown one warns and then opens the food editor with the code filled in.
    private func handleScannedCode() {
        guard let code = scannedCode else { return }
        scannedCode = nil
        guard let food = store.foodItem(forBarcode: code) else {
            scanMessage = nil
            unknownBarcode = code
            return
        }
        if !selection.contains(food.id) { selection.append(food.id) }
        scanMessage = "\(food.name) selecionado"
        Haptics.success()
    }

    private func toggle(_ id: UUID) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }
        Haptics.light()
    }

    private func stockDetail(_ food: FoodItem) -> String? {
        let total = store.pantryStock(of: food.id, includingExpired: true)
        return total > 0 ? "Em stock: \(PantryFormat.amount(total, unit: food.unit))" : nil
    }
}

/// What the AI import read for a food, used to start its line in the quantities step.
struct PantryEntryPrefill {
    /// In the food's base unit.
    var amount: Double?
    var locationID: UUID?
    var expiresOn: Date?
}

/// Second step: per food, the amount that came in (g/kg, ml/L or units), its location and
/// expiry date. A location can be set for all at once.
private struct PantryEntryAmountsView: View {
    @Environment(DataStore.self) private var store

    let onDone: () -> Void

    private struct Line: Identifiable {
        let foodID: UUID
        var amountText = ""
        var unit: MeasurementUnit
        var locationID: UUID?
        var hasExpiry = false
        var expiresOn = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        var id: UUID { foodID }

        var amount: Double? {
            guard let value = LabelNutritionText.number(amountText), value > 0 else { return nil }
            return value * unit.baseMultiplier
        }
    }

    @State private var lines: [Line] = []
    @State private var newLocationName = ""
    private let foodIDs: [UUID]
    private let prefill: [UUID: PantryEntryPrefill]

    init(foodIDs: [UUID], prefill: [UUID: PantryEntryPrefill] = [:], onDone: @escaping () -> Void) {
        self.foodIDs = foodIDs
        self.prefill = prefill
        self.onDone = onDone
    }

    private var isValid: Bool {
        !lines.isEmpty && lines.allSatisfy { $0.amount != nil && $0.locationID != nil }
    }

    var body: some View {
        Form {
            if store.pantryLocations.isEmpty {
                Section {
                    ForEach(["Despensa", "Frigorífico", "Congelador"], id: \.self) { name in
                        Button {
                            addLocation(name)
                        } label: {
                            Label("Criar \"\(name)\"", systemImage: "plus")
                        }
                    }
                    HStack {
                        TextField("Outro local", text: $newLocationName)
                        Button("Criar") { addLocation(newLocationName) }
                            .disabled(newLocationName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Locais de Stock")
                } footer: {
                    Text("Ainda não tens locais. Cria pelo menos um (podes geri-los depois nas definições da Despensa).")
                }
            } else if lines.count > 1 {
                Section {
                    Picker("Local para todos", selection: Binding(
                        get: { Set(lines.map(\.locationID)).count == 1 ? lines.first?.locationID : nil },
                        set: { id in for index in lines.indices { lines[index].locationID = id } }
                    )) {
                        Text("—").tag(UUID?.none)
                        ForEach(store.pantryLocations) { location in
                            Text(location.name).tag(UUID?.some(location.id))
                        }
                    }
                }
            }

            ForEach($lines) { $line in
                if let food = food(line.foodID) {
                    Section {
                        HStack {
                            Text("Quantidade")
                            Spacer()
                            TextField("0", text: $line.amountText)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            UnitMenu(unit: $line.unit, baseUnit: food.unit.baseUnit)
                        }
                        Picker("Local", selection: $line.locationID) {
                            if line.locationID == nil { Text("—").tag(UUID?.none) }
                            ForEach(store.pantryLocations) { location in
                                Text(location.name).tag(UUID?.some(location.id))
                            }
                        }
                        Toggle("Tem validade", isOn: $line.hasExpiry)
                        if line.hasExpiry {
                            DatePicker("Validade", selection: $line.expiresOn, displayedComponents: .date)
                        }
                    } header: {
                        Text(food.brand.map { "\(food.name) (\($0))" } ?? food.name)
                    } footer: {
                        let stock = store.pantryStock(of: food.id, includingExpired: true)
                        if stock > 0 {
                            Text("Já tens \(PantryFormat.amount(stock, unit: food.unit)) em stock.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Quantidades")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { save() }
                    .disabled(!isValid)
            }
        }
        .onAppear(perform: load)
        .onChange(of: foodIDs) { load() }
    }

    private func load() {
        let defaultLocation = store.pantryLocations.first?.id
        let existing = Dictionary(lines.map { ($0.foodID, $0) }) { first, _ in first }
        lines = foodIDs.compactMap { id in
            if let line = existing[id] { return line }
            guard let food = food(id) else { return nil }
            if let read = prefill[id] {
                var line = Line(foodID: id, amountText: read.amount.map { PantryFormat.plainNumber($0) } ?? "",
                                unit: food.unit.baseUnit, locationID: read.locationID ?? defaultLocation)
                if let expiresOn = read.expiresOn {
                    line.hasExpiry = true
                    line.expiresOn = expiresOn
                }
                return line
            }
            // Starts with one package-ish amount: a dose for units, nothing typed otherwise.
            return Line(foodID: id, amountText: food.unit.baseUnit == .unit ? "1" : "", unit: food.unit.baseUnit,
                        locationID: defaultLocation)
        }
    }

    private func addLocation(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let location = PantryLocation(name: trimmed)
        store.addPantryLocation(location)
        newLocationName = ""
        for index in lines.indices where lines[index].locationID == nil {
            lines[index].locationID = location.id
        }
    }

    private func save() {
        let lots = lines.compactMap { line -> PantryLot? in
            guard let amount = line.amount, let locationID = line.locationID else { return nil }
            return PantryLot(foodItemID: line.foodID, locationID: locationID, remaining: amount,
                             expiresOn: line.hasExpiry ? Calendar.current.startOfDay(for: line.expiresOn) : nil)
        }
        store.addPantryLots(lots)
        Haptics.success()
        onDone()
    }

    private func food(_ id: UUID) -> FoodItem? {
        store.foodItems.first { $0.id == id }
    }
}
