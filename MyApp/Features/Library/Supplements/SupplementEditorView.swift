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

    @State private var prices: [PriceEntry] = []
    @State private var showingAddPrice = false

    @State private var stocks: [SupplementStock] = []
    @State private var lowStockThresholdText = ""
    @State private var editingStock: StockEditTarget?

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
                            .keyboardType(.decimalPad)
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
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    } else {
                        HStack {
                            Text("Peso por dose")
                            Spacer()
                            TextField("30", text: $doseSizeText)
                                .keyboardType(.decimalPad)
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

                Section("Macros por Dose (opcional)") {
                    TextField("Calorias (kcal)", text: $caloriesText)
                        .keyboardType(.numberPad)
                    TextField("Proteína (g)", text: $proteinText)
                        .keyboardType(.decimalPad)
                    TextField("Hidratos de Carbono (g)", text: $carbsText)
                        .keyboardType(.decimalPad)
                    TextField("Gordura (g)", text: $fatText)
                        .keyboardType(.decimalPad)
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
                                .keyboardType(.decimalPad)
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
                            .keyboardType(.decimalPad)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: populateIfEditing)
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
        prices = supplement.prices
        stocks = supplement.stocks
        lowStockThresholdText = supplement.lowStockThreshold.map(formatted) ?? ""
    }

    private func save() {
        guard let categoryID, let totalSize, let doseSize = computedDoseSize else { return }
        let supplement = Supplement(
            id: supplementToEdit?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            categoryID: categoryID,
            unit: unit,
            totalSize: totalSize,
            doseSize: doseSize,
            calories: Int(caloriesText),
            protein: Double(proteinText),
            carbs: Double(carbsText),
            fat: Double(fatText),
            prices: prices,
            stocks: stocks.filter { store.stockLocation(withID: $0.locationID) != nil },
            lowStockThreshold: Double(lowStockThresholdText.replacingOccurrences(of: ",", with: ".")),
            isFavorite: supplementToEdit?.isFavorite ?? false,
            createdAt: supplementToEdit?.createdAt ?? Date()
        )
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
