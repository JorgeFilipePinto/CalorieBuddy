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
    @State private var photoID: UUID?
    @State private var labelPhotoIDs: [UUID] = []
    @State private var brand = ""
    @State private var categoryID: UUID?
    @State private var unit: MeasurementUnit = .gram
    @State private var doseSizeText = "100"
    @State private var nutritionBasis: NutritionBasis = .per100
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var saturatedFatText = ""
    @State private var sugarsText = ""
    @State private var fiberText = ""
    @State private var saltText = ""
    @State private var micronutrients: [Micronutrient: Double] = [:]
    @State private var barcodes: [String] = []
    @State private var showScanner = false
    @State private var prices: [PriceEntry] = []
    @State private var showingAddPrice = false

    /// Free-text vitamins/minerals from before the fixed list that it doesn't recognise.
    @State private var minerals: [NutrientValue] = []
    @State private var vitamins: [NutrientValue] = []

    @State private var showingJSONImport = false
    /// Its own weight change when cooked, in % (empty = the meal-prep reference for its name).
    @State private var cookingChangeText = ""
    /// A preparation to open (`nil` id-less = new one).
    @State private var preparationToEdit: PreparationTarget?

    private struct PreparationTarget: Identifiable {
        let existing: FoodItem?
        var id: UUID { existing?.id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")! }
    }

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

    private var basisDescription: String {
        nutritionBasis == .per100 ? "por \(per100Label)" : "por dose"
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
        // A preparation (Frango grelhado) is edited as one: its label comes from the raw food.
        if let itemToEdit, let base = store.baseFood(of: itemToEdit) {
            NavigationStack {
                FoodPreparationEditorView(base: base, existing: itemToEdit)
            }
        } else {
            editor
        }
    }

    private var editor: some View {
        NavigationStack {
            Form {
                #if canImport(UIKit)
                Section("Foto") {
                    PhotoPickerField(photoID: $photoID)
                }
                NutritionLabelPhotosSection(photoIDs: $labelPhotoIDs)
                #endif

                Section("Alimento") {
                    TextField("Nome", text: $name)
                    TextField("Marca (opcional)", text: $brand)
                    Picker("Categoria", selection: $categoryID) {
                        Text("Sem categoria").tag(UUID?.none)
                        ForEach(store.orderedFoodCategories) { category in
                            Text(store.categoryTitle(category)).tag(UUID?.some(category.id))
                        }
                    }
                    Picker("Unidade", selection: $unit) {
                        ForEach(MeasurementUnit.allCases) { measurementUnit in
                            Text(measurementUnit.shortLabel).tag(measurementUnit)
                        }
                    }
                    HStack {
                        Text("Tamanho da dose")
                        Spacer()
                        TextField("100", text: $doseSizeText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
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

                    LabelNutritionFields(text: labelText)
                } header: {
                    Text("Declaração Nutricional")
                } footer: {
                    Text(nutritionBasis == .per100
                        ? "Valores tal como aparecem no rótulo, por \(per100Label)."
                        : "Valores para uma dose de \(doseSizeText.isEmpty ? "?" : doseSizeText) \(unit.shortLabel).")
                }

                MicronutrientsSection(values: $micronutrients, basis: basisDescription)

                if !minerals.isEmpty || !vitamins.isEmpty {
                    Section {
                        nutrientRows($minerals)
                        nutrientRows($vitamins)
                    } header: {
                        Text("Outros Nutrientes")
                    } footer: {
                        Text("Registados antes da lista fixa e que ela não reconhece. Desliza para remover.")
                    }
                }

                if unit.baseUnit != .unit {
                    cookingSection
                }

                if let itemToEdit, itemToEdit.canHavePreparations {
                    preparationsSection(itemToEdit)
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
                    title: "Importar Alimento",
                    prompt: AIJSONImport.foodPrompt(categories: store.foodCategories.map(\.name)),
                    instructions: "Útil quando não há rótulo à mão. Se a resposta tiver vários alimentos, o primeiro preenche este formulário e os restantes são adicionados diretamente ao catálogo."
                ) { json in
                    try handleJSONImport(json)
                }
            }
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
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                TextField("un.", text: $value.unit)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 50)
            }
        }
        .onDelete { offsets in values.wrappedValue.remove(atOffsets: offsets) }
    }

    /// Applies AI-provided JSON to this form: the first food fills the fields for review before
    /// saving, and any further ones (from a pasted array) are added straight to the catalog.
    private func handleJSONImport(_ json: String) throws {
        let payloads = try AIJSONImport.decodeFoodItems(from: json)
        guard let first = payloads.first else { throw AIImportError.empty }
        applyFoodPayload(first)
        for extra in payloads.dropFirst() {
            store.catalogFood(for: extra)
        }
    }

    private func applyFoodPayload(_ payload: FoodImportPayload) {
        name = payload.name.trimmingCharacters(in: .whitespaces)
        brand = payload.brand?.trimmingCharacters(in: .whitespaces) ?? ""
        unit = payload.resolvedUnit
        doseSizeText = formatted(payload.doseSize ?? 100)
        nutritionBasis = payload.resolvedNutritionBasis
        caloriesText = String(payload.calories)
        proteinText = payload.protein.map { String($0) } ?? ""
        carbsText = payload.carbs.map { String($0) } ?? ""
        fatText = payload.fat.map { String($0) } ?? ""
        let imported = payload.makeFoodItem()
        saturatedFatText = LabelNutritionText.text(imported.saturatedFat)
        sugarsText = LabelNutritionText.text(imported.sugars)
        fiberText = LabelNutritionText.text(imported.fiber)
        saltText = LabelNutritionText.text(imported.salt)
        if !imported.micronutrients.isEmpty { micronutrients = imported.micronutrients.typedMicronutrients }
        if !imported.minerals.isEmpty { minerals = imported.minerals }
        if !imported.vitamins.isEmpty { vitamins = imported.vitamins }
        if let category = store.foodCategory(named: payload.category) { categoryID = category.id }
        if let barcode = payload.resolvedBarcode, !barcodes.contains(barcode) { barcodes.append(barcode) }
        if let change = imported.cookingWeightChange { cookingChangeText = RecipeIngredientEditorView.number(change) }
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
        photoID = item.photoID
        labelPhotoIDs = item.labelPhotoIDs
        brand = item.brand ?? ""
        categoryID = item.categoryID
        unit = item.unit
        doseSizeText = formatted(item.doseSize)
        nutritionBasis = item.nutritionBasis
        caloriesText = String(item.calories)
        proteinText = item.protein.map { String($0) } ?? ""
        carbsText = item.carbs.map { String($0) } ?? ""
        fatText = item.fat.map { String($0) } ?? ""
        saturatedFatText = LabelNutritionText.text(item.saturatedFat)
        sugarsText = LabelNutritionText.text(item.sugars)
        fiberText = LabelNutritionText.text(item.fiber)
        saltText = LabelNutritionText.text(item.salt)
        micronutrients = item.micronutrients.typedMicronutrients
        barcodes = item.barcodes
        prices = item.prices
        minerals = item.minerals
        vitamins = item.vitamins
        cookingChangeText = item.cookingWeightChange.map { RecipeIngredientEditorView.number($0) } ?? ""
    }

    private var cookingChange: Double? {
        LabelNutritionText.number(cookingChangeText.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "−", with: "-"))
    }

    /// The food's preparations (grelhado, cozido…), each a food of its own with the label worked out
    /// from this one; a new one starts from the reference for the method.
    private func preparationsSection(_ base: FoodItem) -> some View {
        Section {
            ForEach(store.preparations(of: base)) { preparation in
                Button {
                    preparationToEdit = PreparationTarget(existing: preparation)
                } label: {
                    HStack {
                        Label(preparation.name, systemImage: preparation.preparation?.symbolName ?? "flame")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(PantryFormat.percent(preparation.cookingWeightChange ?? 0)) · \(preparation.scaledCalories(quantity: 100 / max(preparation.baseDoseAmount, 1))) kcal/100")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                preparationToEdit = PreparationTarget(existing: nil)
            } label: {
                Label("Adicionar Preparação", systemImage: "plus")
            }
        } header: {
            Text("Preparações")
        } footer: {
            Text("Cozido, grelhado, assado, estufado… cada um com o peso que ganha ou perde. Os valores vêm deste alimento (cru) e acompanham-no quando o alteras. Nas marmitas, uma receita com a preparação usa o stock deste alimento.")
        }
        .sheet(item: $preparationToEdit) { target in
            NavigationStack {
                FoodPreparationEditorView(base: base, existing: target.existing)
            }
        }
    }

    /// The weight change when cooked, for meal prep: its own value, or the reference for its name.
    private var cookingSection: some View {
        let reference = CookingYield.reference(for: name, in: store.cookingYields)
        return Section {
            HStack {
                Text("Variação ao cozinhar")
                Spacer()
                TextField(reference.map { PantryFormat.percent($0.weightChange) } ?? "0", text: $cookingChangeText)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("%").foregroundStyle(.secondary)
            }
        } header: {
            Text("Confeção")
        } footer: {
            if let reference, cookingChange == nil {
                Text("Vazio = referência \"\(reference.name)\" (\(PantryFormat.percent(reference.weightChange))), da Despensa → Variação na Confeção. Escreve um valor só para este alimento.")
            } else {
                Text("Quanto o peso muda de cru para cozinhado (+160 = arroz, −25 = frango), para calcular as marmitas. Vazio = sem variação.")
            }
        }
    }

    private func save() {
        guard let calories = Int(caloriesText),
              let doseSize = Double(doseSizeText.replacingOccurrences(of: ",", with: ".")) else { return }
        let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
        let cleanedMinerals = minerals.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let cleanedVitamins = vitamins.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }

        var item = FoodItem(
            id: itemToEdit?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            brand: trimmedBrand.isEmpty ? nil : trimmedBrand,
            unit: unit,
            doseSize: doseSize,
            nutritionBasis: nutritionBasis,
            calories: calories,
            protein: LabelNutritionText.number(proteinText),
            carbs: LabelNutritionText.number(carbsText),
            fat: LabelNutritionText.number(fatText),
            minerals: cleanedMinerals,
            vitamins: cleanedVitamins,
            barcodes: barcodes,
            prices: prices,
            isFavorite: itemToEdit?.isFavorite ?? false,
            createdAt: itemToEdit?.createdAt ?? Date(),
            photoID: photoID,
            categoryID: categoryID
        )
        item.labelPhotoIDs = labelPhotoIDs
        item.cookingWeightChange = unit.baseUnit == .unit ? nil : cookingChange
        item.saturatedFat = LabelNutritionText.number(saturatedFatText)
        item.sugars = LabelNutritionText.number(sugarsText)
        item.fiber = LabelNutritionText.number(fiberText)
        item.salt = LabelNutritionText.number(saltText)
        // Keep keys this version doesn't know (written by a newer app or the dashboard).
        var storedMicros = (itemToEdit?.micronutrients ?? [:]).filter { Micronutrient(rawValue: $0.key) == nil }
        storedMicros.merge(micronutrients.stored) { _, new in new }
        item.micronutrients = storedMicros
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
