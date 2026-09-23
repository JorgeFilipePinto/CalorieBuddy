import SwiftUI

struct FoodItemEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let itemToEdit: FoodItem?
    /// Barcode to pre-fill when creating a brand-new item (e.g. one just scanned but not yet in
    /// the catalog). Ignored when editing an existing item.
    let initialBarcode: String?
    /// Called right after the item is saved (added or updated), before the sheet dismisses.
    /// Lets a caller (e.g. the recipe editor, or the scan-and-log flow) react to a newly created item.
    var onSave: ((FoodItem) -> Void)?
    /// Whether saving dismisses this view on its own. Defaults to `true`, matching every call
    /// site that presents this as its own standalone sheet. Pass `false` when this view is
    /// instead swapped out for other content by a parent driving a multi-step flow (e.g.
    /// `ScanAndLogEntryView`) — there, dismissing here would close the whole flow instead of
    /// advancing to its next step.
    var dismissesAfterSave: Bool = true

    @State private var name = ""
    @State private var brand = ""
    @State private var unit: MeasurementUnit = .gram
    @State private var doseSizeText = "100"
    @State private var nutritionBasis: NutritionBasis = .per100
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var barcodes: [String] = []
    @State private var showScanner = false
    @State private var prices: [PriceEntry] = []
    @State private var showingAddPrice = false

    @State private var showMinerals = false
    @State private var minerals: [NutrientValue] = []
    @State private var showVitamins = false
    @State private var vitamins: [NutrientValue] = []

    init(
        itemToEdit: FoodItem? = nil,
        initialBarcode: String? = nil,
        dismissesAfterSave: Bool = true,
        onSave: ((FoodItem) -> Void)? = nil
    ) {
        self.itemToEdit = itemToEdit
        self.initialBarcode = initialBarcode
        self.dismissesAfterSave = dismissesAfterSave
        self.onSave = onSave
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Int(caloriesText) != nil
            && Double(doseSizeText.replacingOccurrences(of: ",", with: ".")) != nil
    }

    private var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }

    /// "100 g" or "100 ml" — the fixed reference amount for the "per 100" nutrition basis.
    private var per100Label: String {
        unit.baseUnit == .milliliter ? "100 ml" : "100 \(MeasurementUnit.gram.shortLabel)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alimento") {
                    TextField("Nome", text: $name)
                    TextField("Marca (opcional)", text: $brand)
                    Picker("Unidade", selection: $unit) {
                        ForEach(MeasurementUnit.allCases) { measurementUnit in
                            Text(measurementUnit.shortLabel).tag(measurementUnit)
                        }
                    }
                    HStack {
                        Text("Tamanho da dose")
                        Spacer()
                        TextField("100", text: $doseSizeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(unit.shortLabel).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Valores indicados", selection: $nutritionBasis) {
                        ForEach(NutritionBasis.allCases) { basis in
                            Text(basis == .per100 ? "Por \(per100Label)" : "Por dose").tag(basis)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Calorias (kcal)", text: $caloriesText)
                        .keyboardType(.numberPad)
                    TextField("Proteína (g)", text: $proteinText)
                        .keyboardType(.decimalPad)
                    TextField("Hidratos de Carbono (g)", text: $carbsText)
                        .keyboardType(.decimalPad)
                    TextField("Gordura (g)", text: $fatText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Macros")
                } footer: {
                    Text(nutritionBasis == .per100
                        ? "Valores tal como aparecem no rótulo, por \(per100Label)."
                        : "Valores para uma dose de \(doseSizeText.isEmpty ? "?" : doseSizeText) \(unit.shortLabel).")
                }

                Section {
                    Toggle("Minerais", isOn: $showMinerals.animation())
                    if showMinerals {
                        nutrientRows($minerals)
                    }
                }

                Section {
                    Toggle("Vitaminas", isOn: $showVitamins.animation())
                    if showVitamins {
                        nutrientRows($vitamins)
                    }
                }

                Section {
                    ForEach(barcodes, id: \.self) { code in
                        Label(code, systemImage: "barcode")
                    }
                    .onDelete { offsets in barcodes.remove(atOffsets: offsets) }

                    Button {
                        showScanner = true
                    } label: {
                        Label("Digitalizar Código de Barras", systemImage: "barcode.viewfinder")
                    }
                } header: {
                    Text("Códigos de Barras")
                } footer: {
                    Text("Adiciona vários códigos ao mesmo alimento (ex: tamanhos ou embalagens diferentes) para não teres entradas repetidas no catálogo.")
                }

                Section {
                    ForEach(prices) { priceEntry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.store(withID: priceEntry.storeID)?.name ?? "Loja")
                                Text("embalagem de \(formatted(priceEntry.packageSize)) \(priceEntry.packageUnit.shortLabel)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if priceEntry.isPromotion {
                                    HStack(spacing: 4) {
                                        Text("Promoção")
                                        if let regularPrice = priceEntry.regularPrice {
                                            Text("· normal \(regularPrice, format: .currency(code: currencyCode))")
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Text(priceEntry.price, format: .currency(code: currencyCode))
                                .foregroundStyle(priceEntry.isPromotion ? .orange : .secondary)
                        }
                    }
                    .onDelete { offsets in prices.remove(atOffsets: offsets) }

                    Button {
                        showingAddPrice = true
                    } label: {
                        Label("Adicionar Preço", systemImage: "plus")
                    }
                } header: {
                    Text("Preços")
                } footer: {
                    Text("O preço é da embalagem comprada — a app calcula automaticamente o custo da dose usada nas receitas.")
                }
            }
            .navigationTitle(itemToEdit == nil ? "Novo Alimento" : "Editar Alimento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: populateIfEditing)
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView { code in
                    if !barcodes.contains(code) {
                        barcodes.append(code)
                    }
                }
            }
            .sheet(isPresented: $showingAddPrice) {
                AddPriceView(compatibleUnits: MeasurementUnit.compatible(with: unit)) { storeID, price, packageSize, packageUnit, isPromotion, regularPrice in
                    prices.append(PriceEntry(
                        storeID: storeID,
                        price: price,
                        packageSize: packageSize,
                        packageUnit: packageUnit,
                        isPromotion: isPromotion,
                        regularPrice: regularPrice
                    ))
                }
            }
        }
    }

    @ViewBuilder
    private func nutrientRows(_ values: Binding<[NutrientValue]>) -> some View {
        ForEach(values) { $value in
            HStack {
                TextField("Nome", text: $value.name)
                TextField("Qtd.", value: $value.amount, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                TextField("un.", text: $value.unit)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 50)
            }
        }
        .onDelete { offsets in values.wrappedValue.remove(atOffsets: offsets) }
        .onAppear {
            if values.wrappedValue.isEmpty {
                values.wrappedValue.append(NutrientValue(name: "", amount: 0, unit: "mg"))
            }
        }

        Button {
            values.wrappedValue.append(NutrientValue(name: "", amount: 0, unit: "mg"))
        } label: {
            Label("Adicionar", systemImage: "plus")
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.2f", value)
    }

    private func populateIfEditing() {
        guard let item = itemToEdit else {
            if let initialBarcode {
                barcodes = [initialBarcode]
            }
            return
        }
        name = item.name
        brand = item.brand ?? ""
        unit = item.unit
        doseSizeText = formatted(item.doseSize)
        nutritionBasis = item.nutritionBasis
        caloriesText = String(item.calories)
        proteinText = item.protein.map { String($0) } ?? ""
        carbsText = item.carbs.map { String($0) } ?? ""
        fatText = item.fat.map { String($0) } ?? ""
        barcodes = item.barcodes
        prices = item.prices
        minerals = item.minerals
        showMinerals = !item.minerals.isEmpty
        vitamins = item.vitamins
        showVitamins = !item.vitamins.isEmpty
    }

    private func save() {
        guard let calories = Int(caloriesText),
              let doseSize = Double(doseSizeText.replacingOccurrences(of: ",", with: ".")) else { return }
        let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
        let cleanedMinerals = showMinerals ? minerals.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty } : []
        let cleanedVitamins = showVitamins ? vitamins.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty } : []

        let item = FoodItem(
            id: itemToEdit?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            brand: trimmedBrand.isEmpty ? nil : trimmedBrand,
            unit: unit,
            doseSize: doseSize,
            nutritionBasis: nutritionBasis,
            calories: calories,
            protein: Double(proteinText),
            carbs: Double(carbsText),
            fat: Double(fatText),
            minerals: cleanedMinerals,
            vitamins: cleanedVitamins,
            barcodes: barcodes,
            prices: prices,
            isFavorite: itemToEdit?.isFavorite ?? false,
            createdAt: itemToEdit?.createdAt ?? Date()
        )
        if itemToEdit == nil {
            store.addFoodItem(item)
        } else {
            store.updateFoodItem(item)
        }
        onSave?(item)
        if dismissesAfterSave {
            dismiss()
        }
    }
}

#Preview {
    FoodItemEditorView()
        .environment(DataStore())
}
