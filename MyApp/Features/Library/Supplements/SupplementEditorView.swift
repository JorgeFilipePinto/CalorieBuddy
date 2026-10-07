import SwiftUI

struct SupplementEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let supplementToEdit: Supplement?

    private enum DoseDefinitionMode: String, CaseIterable, Identifiable {
        case doseCount, doseWeight
        var id: String { rawValue }
        var label: String {
            self == .doseCount ? "Nº de Doses" : "Peso da Dose"
        }
    }

    @State private var name = ""
    @State private var photoID: UUID?
    @State private var labelPhotoIDs: [UUID] = []
    @State private var categoryID: UUID?
    @State private var showingCategoryPicker = false

    @State private var unit: MeasurementUnit = .gram
    @State private var totalSizeText = ""
    @State private var doseMode: DoseDefinitionMode = .doseCount
    @State private var doseCountText = ""
    @State private var doseSizeText = ""

    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var saturatedFatText = ""
    @State private var sugarsText = ""
    @State private var fiberText = ""
    @State private var saltText = ""
    @State private var nutritionBasis: NutritionBasis = .perDose
    @State private var micronutrients: [Micronutrient: Double] = [:]

    @State private var prices: [PriceEntry] = []
    @State private var showingAddPrice = false

    @State private var barcodes: [String] = []
    @State private var showingScanner = false

    @State private var stocks: [SupplementStock] = []
    @State private var lowStockThresholdText = ""
    @State private var editingStock: StockEditTarget?
    @State private var showingJSONImport = false

    private struct StockEditTarget: Identifiable { let id: UUID }

    init(supplementToEdit: Supplement? = nil) {
        self.supplementToEdit = supplementToEdit
    }

    private var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }

    private var totalSize: Double? {
        Double(totalSizeText.replacingOccurrences(of: ",", with: "."))
    }

    /// The dose size in `unit`, derived from whichever of "number of doses" / "dose weight"
    /// the user chose to enter.
    private var computedDoseSize: Double? {
        guard let totalSize else { return nil }
        switch doseMode {
        case .doseCount:
            guard let count = Double(doseCountText.replacingOccurrences(of: ",", with: ".")), count > 0 else { return nil }
            return totalSize / count
        case .doseWeight:
            guard let size = Double(doseSizeText.replacingOccurrences(of: ",", with: ".")), size > 0 else { return nil }
            return size
        }
    }

    /// The label fields, edited together.
    private var labelText: Binding<LabelNutritionText> {
        Binding(
            get: {
                LabelNutritionText(calories: caloriesText, fat: fatText, saturatedFat: saturatedFatText, carbs: carbsText,
                                   sugars: sugarsText, fiber: fiberText, protein: proteinText, salt: saltText)
            },
            set: { text in
                caloriesText = text.calories
                fatText = text.fat
                saturatedFatText = text.saturatedFat
                carbsText = text.carbs
                sugarsText = text.sugars
                fiberText = text.fiber
                proteinText = text.protein
                saltText = text.salt
            }
        )
    }

    /// "100 g" / "100 ml" — the reference amount of the "per 100" basis.
    private var per100Label: String {
        unit.baseUnit == .milliliter ? "100 ml" : "100 \(MeasurementUnit.gram.shortLabel)"
    }

    private var basisDescription: String {
        nutritionBasis == .per100 ? "por \(per100Label)" : "por dose"
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && categoryID != nil
            && (totalSize ?? 0) > 0
            && (computedDoseSize ?? 0) > 0
    }

    private var categoryName: String {
        categoryID.flatMap { store.supplementCategory(withID: $0)?.name } ?? "Escolhe..."
    }

    var body: some View {
        NavigationStack {
            Form {
                #if canImport(UIKit)
                Section("Foto") {
                    PhotoPickerField(photoID: $photoID)
                }
                NutritionLabelPhotosSection(photoIDs: $labelPhotoIDs)
                #endif

                Section("Suplemento") {
                    TextField("Nome", text: $name)
                    Button {
                        showingCategoryPicker = true
                    } label: {
                        HStack {
                            Text("Categoria")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(categoryName)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Picker("Unidade", selection: $unit) {
                        ForEach(MeasurementUnit.allCases) { measurementUnit in
                            Text(measurementUnit.shortLabel).tag(measurementUnit)
                        }
                    }
                    HStack {
                        Text("Tamanho total")
                        Spacer()
                        TextField("900", text: $totalSizeText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(unit.shortLabel).foregroundStyle(.secondary)
                    }

                    Picker("Definir dose por", selection: $doseMode) {
                        ForEach(DoseDefinitionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if doseMode == .doseCount {
                        HStack {
                            Text("Número de doses")
                            Spacer()
                            TextField("30", text: $doseCountText)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    } else {
                        HStack {
                            Text("Peso por dose")
                            Spacer()
                            TextField("30", text: $doseSizeText)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text(unit.shortLabel).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Embalagem")
                } footer: {
                    if let dose = computedDoseSize, let totalSize {
                        let doseCount = dose > 0 ? totalSize / dose : 0
                        Text("≈ \(formatted(dose)) \(unit.shortLabel) por dose · \(formatted(doseCount)) doses na embalagem")
                    }
                }

                Section {
                    if unit != .unit {
                        Picker("Valores indicados", selection: $nutritionBasis) {
                            Text("Por \(per100Label)").tag(NutritionBasis.per100)
                            Text("Por dose").tag(NutritionBasis.perDose)
                        }
                        .pickerStyle(.segmented)
                    }
                    LabelNutritionFields(text: labelText)
                } header: {
                    Text("Declaração Nutricional (opcional)")
                } footer: {
                    Text("Copia uma das colunas do rótulo (\(basisDescription)). Conta para o dia sempre que registas uma toma.")
                }

                MicronutrientsSection(values: $micronutrients, basis: basisDescription)

                Section {
                    ForEach(barcodes, id: \.self) { code in
                        Label(code, systemImage: "barcode")
                    }
                    .onDelete { offsets in barcodes.remove(atOffsets: offsets) }

                    Button {
                        showingScanner = true
                    } label: {
                        Label("Digitalizar Código de Barras", systemImage: "barcode.viewfinder")
                    }
                } header: {
                    Text("Códigos de Barras")
                } footer: {
                    Text("Ao digitalizar este código no \"+\" de um dia, a app regista este suplemento.")
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
                    Text("O preço é da embalagem comprada — a app calcula automaticamente o custo da dose.")
                }

                Section {
                    ForEach($stocks) { $stock in
                        HStack {
                            Button {
                                editingStock = StockEditTarget(id: stock.id)
                            } label: {
                                Text(store.stockLocation(withID: stock.locationID)?.name ?? "Escolhe o local")
                                    .foregroundStyle(store.stockLocation(withID: stock.locationID) == nil ? .secondary : .primary)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            TextField("0", value: $stock.remaining, format: .number)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                            Text(unit.shortLabel).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in stocks.remove(atOffsets: offsets) }

                    Button {
                        addStockRow()
                    } label: {
                        Label("Adicionar Stock", systemImage: "plus")
                    }

                    HStack {
                        Text("Avisar para comprar quando restar")
                        Spacer()
                        TextField("—", text: $lowStockThresholdText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text(unit.shortLabel).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Stock")
                } footer: {
                    Text("Cria um stock por local onde guardas o suplemento (ex: Casa, Trabalho). Ao consumir, escolhes de qual está a sair. Deixa o alerta em branco para não usar.")
                }
            }
            .navigationTitle(supplementToEdit == nil ? "Novo Suplemento" : "Editar Suplemento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .barTrailing) {
                    Button {
                        showingJSONImport = true
                    } label: {
                        Label("Importar JSON (IA)", systemImage: "sparkles")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: populateIfEditing)
            .sheet(isPresented: $showingJSONImport) {
                JSONImportSheet(
                    title: "Importar Suplemento",
                    prompt: AIJSONImport.supplementPrompt(categories: store.supplementCategories.map(\.name)),
                    instructions: "Útil para preencher a embalagem, a dose e os macros a partir do rótulo. Se a resposta tiver vários suplementos, o primeiro preenche este formulário e os restantes são adicionados diretamente."
                ) { json in
                    try handleJSONImport(json)
                }
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView { code in
                    if !barcodes.contains(code) {
                        barcodes.append(code)
                    }
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                SupplementCategoryPickerView(selectedCategoryID: $categoryID)
            }
            .sheet(isPresented: $showingAddPrice) {
                AddPriceView(
                    compatibleUnits: MeasurementUnit.compatible(with: unit),
                    defaultPackageSize: totalSize ?? 1
                ) { storeID, price, packageSize, packageUnit, isPromotion, regularPrice in
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
            .sheet(item: $editingStock) { target in
                StockLocationPickerView(selectedLocationID: Binding(
                    get: { stocks.first(where: { $0.id == target.id })?.locationID },
                    set: { newValue in
                        guard let newValue, let index = stocks.firstIndex(where: { $0.id == target.id }) else { return }
                        stocks[index].locationID = newValue
                    }
                ))
            }
        }
    }

    private func addStockRow() {
        let newStock = SupplementStock(locationID: UUID(), remaining: 0)
        stocks.append(newStock)
        editingStock = StockEditTarget(id: newStock.id)
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func populateIfEditing() {
        guard let supplement = supplementToEdit else { return }
        photoID = supplement.photoID
        labelPhotoIDs = supplement.labelPhotoIDs
        name = supplement.name
        categoryID = supplement.categoryID
        unit = supplement.unit
        totalSizeText = formatted(supplement.totalSize)
        doseMode = .doseWeight
        doseSizeText = formatted(supplement.doseSize)
        doseCountText = formatted(supplement.doseCount)
        caloriesText = supplement.calories.map(String.init) ?? ""
        proteinText = supplement.protein.map { String($0) } ?? ""
        carbsText = supplement.carbs.map { String($0) } ?? ""
        fatText = supplement.fat.map { String($0) } ?? ""
        saturatedFatText = LabelNutritionText.text(supplement.saturatedFat)
        sugarsText = LabelNutritionText.text(supplement.sugars)
        fiberText = LabelNutritionText.text(supplement.fiber)
        saltText = LabelNutritionText.text(supplement.salt)
        nutritionBasis = supplement.unit == .unit ? .perDose : supplement.nutritionBasis
        micronutrients = supplement.micronutrients.typedMicronutrients
        prices = supplement.prices
        stocks = supplement.stocks
        barcodes = supplement.barcodes
        lowStockThresholdText = supplement.lowStockThreshold.map(formatted) ?? ""
    }

    /// The first supplement in the AI's answer fills this form (prices and stocks entered here are
    /// kept); any others are added straight to the list.
    private func handleJSONImport(_ json: String) throws {
        let payloads = try AIJSONImport.decodeSupplements(from: json)
        guard let first = payloads.first else { throw AIImportError.empty }
        name = first.name.trimmingCharacters(in: .whitespaces)
        categoryID = store.supplementCategory(named: first.category).id
        unit = first.resolvedUnit
        totalSizeText = formatted(first.resolvedTotalSize)
        doseMode = .doseWeight
        doseSizeText = formatted(first.resolvedDoseSize)
        doseCountText = formatted(first.resolvedTotalSize / first.resolvedDoseSize)
        caloriesText = first.calories.map(String.init) ?? ""
        proteinText = first.protein.map { String($0) } ?? ""
        carbsText = first.carbs.map { String($0) } ?? ""
        fatText = first.fat.map { String($0) } ?? ""
        let imported = first.makeSupplement(categoryID: UUID())
        saturatedFatText = LabelNutritionText.text(imported.saturatedFat)
        sugarsText = LabelNutritionText.text(imported.sugars)
        fiberText = LabelNutritionText.text(imported.fiber)
        saltText = LabelNutritionText.text(imported.salt)
        nutritionBasis = .perDose
        if !imported.micronutrients.isEmpty { micronutrients = imported.micronutrients.typedMicronutrients }
        for extra in payloads.dropFirst() {
            store.catalogSupplement(for: extra)
        }
    }

    private func save() {
        guard let categoryID, let totalSize, let doseSize = computedDoseSize else { return }
        var supplement = Supplement(
            id: supplementToEdit?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            categoryID: categoryID,
            unit: unit,
            totalSize: totalSize,
            doseSize: doseSize,
            calories: LabelNutritionText.number(caloriesText).map { Int($0.rounded()) },
            protein: LabelNutritionText.number(proteinText),
            carbs: LabelNutritionText.number(carbsText),
            fat: LabelNutritionText.number(fatText),
            prices: prices,
            stocks: stocks.filter { store.stockLocation(withID: $0.locationID) != nil },
            lowStockThreshold: Double(lowStockThresholdText.replacingOccurrences(of: ",", with: ".")),
            isFavorite: supplementToEdit?.isFavorite ?? false,
            createdAt: supplementToEdit?.createdAt ?? Date(),
            photoID: photoID,
            barcodes: barcodes
        )
        supplement.labelPhotoIDs = labelPhotoIDs
        supplement.nutritionBasis = unit == .unit ? .perDose : nutritionBasis
        supplement.saturatedFat = LabelNutritionText.number(saturatedFatText)
        supplement.sugars = LabelNutritionText.number(sugarsText)
        supplement.fiber = LabelNutritionText.number(fiberText)
        supplement.salt = LabelNutritionText.number(saltText)
        // Keep keys this version doesn't know (written by a newer app or the dashboard).
        var storedMicros = (supplementToEdit?.micronutrients ?? [:]).filter { Micronutrient(rawValue: $0.key) == nil }
        storedMicros.merge(micronutrients.stored) { _, new in new }
        supplement.micronutrients = storedMicros
        if supplementToEdit == nil {
            store.addSupplement(supplement)
        } else {
            store.updateSupplement(supplement)
        }
        dismiss()
    }
}

#Preview {
    SupplementEditorView()
        .environment(DataStore())
}
