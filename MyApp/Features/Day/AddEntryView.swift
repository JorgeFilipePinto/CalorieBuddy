import SwiftUI

struct AddEntryView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let entryToEdit: FoodEntry?
    let defaultDate: Date

    @State private var name = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var mealType: MealType
    @State private var date: Date = .now

    @State private var barcode: String?
    @State private var matchedFoodItemID: UUID?
    @State private var saveToCatalog = false
    @State private var showScanner = false

    init(entryToEdit: FoodEntry? = nil, defaultDate: Date = .now) {
        self.entryToEdit = entryToEdit
        self.defaultDate = defaultDate
        _mealType = State(initialValue: MealType.suggested(for: defaultDate))
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Int(caloriesText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alimento") {
                    TextField("Nome", text: $name)
                    TextField("Calorias (kcal)", text: $caloriesText)
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
            .navigationTitle(entryToEdit == nil ? "Novo Registo" : "Editar Registo")
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
                BarcodeScannerView(onScan: handleScanned)
            }
        }
    }

    private func populateIfEditing() {
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
        matchedFoodItemID = entry.barcode.flatMap { store.foodItem(forBarcode: $0)?.id }
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
        guard let calories = Int(caloriesText) else { return }
        let protein = Double(proteinText)
        let carbs = Double(carbsText)
        let fat = Double(fatText)
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
        if entryToEdit == nil {
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
