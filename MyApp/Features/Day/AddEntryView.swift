import SwiftUI

struct AddEntryView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let entryToEdit: FoodEntry?
    /// "Duplicar": a new entry prefilled from this one, in the current meal and at the current time.
    let duplicateOf: FoodEntry?
    let defaultDate: Date

    @State private var name = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var mealType: MealType
    @State private var date: Date = .now

    @State private var notes = ""
    @State private var photoID: UUID?
    @State private var showingEstimate = false

    @State private var barcode: String?
    @State private var matchedFoodItemID: UUID?
    @State private var saveToCatalog = false
    @State private var showScanner = false

    init(entryToEdit: FoodEntry? = nil, duplicateOf: FoodEntry? = nil, defaultDate: Date = .now) {
        self.entryToEdit = entryToEdit
        self.duplicateOf = duplicateOf
        self.defaultDate = defaultDate
        _mealType = State(initialValue: MealType.suggested(for: defaultDate))
    }

    private var isValid: Bool {
        // Energy and the macros are optional: a sporadic meal can be logged with just a name.
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Typed energy, else worked out from the macros (4/4/9), else 0.
    private var resolvedCalories: Int {
        if let typed = Int(caloriesText) { return typed }
        let protein = Double(proteinText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let carbs = Double(carbsText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let fat = Double(fatText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return Int((protein * 4 + carbs * 4 + fat * 9).rounded())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alimento") {
                    TextField("Nome", text: $name)
                    TextField("Calorias (kcal, opcional)", text: $caloriesText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Picker("Refeição", selection: $mealType) {
                        ForEach(MealType.allCases) { meal in
                            Label(meal.displayName, systemImage: meal.symbolName).tag(meal)
                        }
                    }
                    DatePicker("Data", selection: $date)
                }

                #if canImport(UIKit)
                Section {
                    PhotoPickerField(photoID: $photoID)
                } header: {
                    Text("Foto (opcional)")
                }
                #endif

                Section {
                    TextField("O que é e o que tem", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Descrição (opcional)")
                } footer: {
                    Text("Para refeições esporádicas que não estão no catálogo: guarda a foto e a descrição e melhora o registo mais tarde. Sem calorias, saem dos macros.")
                }

                Section("Macros (opcional)") {
                    TextField("Proteína (g)", text: $proteinText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Hidratos de Carbono (g)", text: $carbsText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Gordura (g)", text: $fatText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }

                Section("Código de Barras") {
                    if let barcode {
                        HStack {
                            Label(barcode, systemImage: "barcode")
                            Spacer()
                            Button("Remover", role: .destructive) {
                                self.barcode = nil
                                matchedFoodItemID = nil
                                saveToCatalog = false
                            }
                        }
                        if matchedFoodItemID != nil {
                            Label("Preenchido a partir do catálogo", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Toggle("Guardar no catálogo para digitalizações futuras", isOn: $saveToCatalog)
                        }
                    } else {
                        Button {
                            showScanner = true
                        } label: {
                            Label("Digitalizar Código de Barras", systemImage: "barcode.viewfinder")
                        }
                    }
                }
            }
            .navigationTitle(duplicateOf != nil ? "Duplicar Registo" : entryToEdit == nil ? "Novo Registo" : "Editar Registo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .barTrailing) {
                    Button {
                        showingEstimate = true
                    } label: {
                        Label("Estimar com IA", systemImage: "sparkles")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: populateIfEditing)
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView(onScan: handleScanned)
            }
            .sheet(isPresented: $showingEstimate) {
                JSONImportSheet(
                    title: "Estimar Refeição",
                    prompt: AIJSONImport.mealEstimatePrompt,
                    instructions: "Para refeições esporádicas: descreve o prato e junta fotos; a IA estima os macros e preenche este formulário. É uma estimativa — podes corrigir os valores. A primeira foto fica guardada com o registo.",
                    onImportKeepingPhotos: { json, photos in
                        try handleEstimate(json, photos: photos)
                    }
                )
            }
        }
    }

    private func populateIfEditing() {
        if let source = duplicateOf {
            name = source.name
            caloriesText = String(source.calories)
            proteinText = source.protein.map { String($0) } ?? ""
            carbsText = source.carbs.map { String($0) } ?? ""
            fatText = source.fat.map { String($0) } ?? ""
            notes = source.notes ?? ""
            photoID = source.photoID
            barcode = source.barcode
            // The meal of the moment and the time now: the point is to log it again, here.
            mealType = MealType.suggested(for: .now)
            date = .now
            return
        }
        guard let entry = entryToEdit else {
            date = defaultDate
            return
        }
        name = entry.name
        caloriesText = String(entry.calories)
        proteinText = entry.protein.map { String($0) } ?? ""
        carbsText = entry.carbs.map { String($0) } ?? ""
        fatText = entry.fat.map { String($0) } ?? ""
        mealType = entry.mealType
        date = entry.date
        barcode = entry.barcode
        notes = entry.notes ?? ""
        photoID = entry.photoID
        matchedFoodItemID = entry.barcode.flatMap { store.foodItem(forBarcode: $0)?.id }
    }

    /// Fills the form from the AI's estimate: what the user already typed is kept (name, description,
    /// photo), the numbers are replaced.
    private func handleEstimate(_ json: String, photos: ImportedPhotos) throws {
        let estimate = try AIJSONImport.decodeMealEstimate(from: json)
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = estimate.name }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let description = estimate.description { notes = description }
        caloriesText = String(estimate.calories)
        proteinText = estimate.protein.map { String($0) } ?? ""
        carbsText = estimate.carbs.map { String($0) } ?? ""
        fatText = estimate.fat.map { String($0) } ?? ""
        if photoID == nil, let data = photos.product { photoID = PhotoStore.save(jpeg: data) }
    }

    private func handleScanned(_ code: String) {
        barcode = code
        if let match = store.foodItem(forBarcode: code) {
            matchedFoodItemID = match.id
            name = match.name
            caloriesText = String(match.scaledCalories(quantity: 1))
            proteinText = match.scaledProtein(quantity: 1).map { String($0) } ?? ""
            carbsText = match.scaledCarbs(quantity: 1).map { String($0) } ?? ""
            fatText = match.scaledFat(quantity: 1).map { String($0) } ?? ""
            saveToCatalog = false
        } else {
            matchedFoodItemID = nil
            saveToCatalog = true
        }
    }

    private func save() {
        let calories = resolvedCalories
        let protein = Double(proteinText.replacingOccurrences(of: ",", with: "."))
        let carbs = Double(carbsText.replacingOccurrences(of: ",", with: "."))
        let fat = Double(fatText.replacingOccurrences(of: ",", with: "."))
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        var entry = FoodEntry(
            id: entryToEdit?.id ?? UUID(),
            name: trimmedName,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            mealType: mealType,
            date: date,
            barcode: barcode,
            groupID: entryToEdit?.groupID,
            groupName: entryToEdit?.groupName
        )
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        entry.photoID = photoID
        // This form edits energy and the macros only: keep the rest of what was logged.
        if let entryToEdit {
            entry.extraNutrition = entryToEdit.nutrition
            // Still the catalog food's values (only the meal or time changed): keep following it.
            // Values typed over by hand stop following the food.
            if entry.calories == entryToEdit.calories, entry.protein == entryToEdit.protein,
               entry.carbs == entryToEdit.carbs, entry.fat == entryToEdit.fat {
                entry.foodItemID = entryToEdit.foodItemID
                entry.quantity = entryToEdit.quantity
                entry.recipeID = entryToEdit.recipeID
            }
        }
        if let source = duplicateOf {
            // A new entry of its own: what was eaten stays (values, catalog food and amount when the
            // values weren't changed here); the recipe group does not come along.
            entry.extraNutrition = source.nutrition
            if entry.calories == source.calories, entry.protein == source.protein, entry.carbs == source.carbs, entry.fat == source.fat {
                entry.foodItemID = source.foodItemID
                entry.quantity = source.quantity
            }
            store.addDuplicatedEntry(entry)
            AppAnalytics.log(.entryLogged(source: .manual, mealType: mealType))
        } else if entryToEdit == nil {
            store.addEntry(entry)
            AppAnalytics.log(.entryLogged(source: barcode == nil ? .manual : .barcode, mealType: mealType))
        } else {
            store.updateEntry(entry)
        }

        if saveToCatalog, matchedFoodItemID == nil, let barcode {
            store.addFoodItem(FoodItem(
                name: trimmedName,
                unit: .unit,
                doseSize: 1,
                nutritionBasis: .perDose,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                barcodes: [barcode]
            ))
        }

        dismiss()
    }
}

#Preview {
    AddEntryView()
        .environment(DataStore())
}
