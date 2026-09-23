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
                        .keyboardType(.numberPad)
                    Picker("Refeição", selection: $mealType) {
                        ForEach(MealType.allCases) { meal in
                            Label(meal.displayName, systemImage: meal.symbolName).tag(meal)
                        }
                    }
                    DatePicker("Data", selection: $date)
                }

                Section("Macros (opcional)") {
                    TextField("Proteína (g)", text: $proteinText)
                        .keyboardType(.decimalPad)
                    TextField("Hidratos de Carbono (g)", text: $carbsText)
                        .keyboardType(.decimalPad)
                    TextField("Gordura (g)", text: $fatText)
                        .keyboardType(.decimalPad)
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

        let entry = FoodEntry(
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
        if entryToEdit == nil {
            store.addEntry(entry)
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
