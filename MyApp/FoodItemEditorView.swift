import SwiftUI

struct FoodItemEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let itemToEdit: FoodItem?

    @State private var name = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var servingLabel = "100 g"
    @State private var barcode: String?
    @State private var showScanner = false

    init(itemToEdit: FoodItem? = nil) {
        self.itemToEdit = itemToEdit
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Int(caloriesText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alimento") {
                    TextField("Nome", text: $name)
                    TextField("Porção (ex: 100 g, 1 unidade)", text: $servingLabel)
                    TextField("Calorias por porção (kcal)", text: $caloriesText)
                        .keyboardType(.numberPad)
                }

                Section("Macros por Porção (opcional)") {
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
                            Button("Remover", role: .destructive) { self.barcode = nil }
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
                    barcode = code
                }
            }
        }
    }

    private func populateIfEditing() {
        guard let item = itemToEdit else { return }
        name = item.name
        caloriesText = String(item.calories)
        proteinText = item.protein.map { String($0) } ?? ""
        carbsText = item.carbs.map { String($0) } ?? ""
        fatText = item.fat.map { String($0) } ?? ""
        servingLabel = item.servingLabel
        barcode = item.barcode
    }

    private func save() {
        guard let calories = Int(caloriesText) else { return }
        let trimmedServing = servingLabel.trimmingCharacters(in: .whitespaces)
        let item = FoodItem(
            id: itemToEdit?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            calories: calories,
            protein: Double(proteinText),
            carbs: Double(carbsText),
            fat: Double(fatText),
            servingLabel: trimmedServing.isEmpty ? "1 porção" : trimmedServing,
            barcode: barcode
        )
        if itemToEdit == nil {
            store.addFoodItem(item)
        } else {
            store.updateFoodItem(item)
        }
        dismiss()
    }
}

#Preview {
    FoodItemEditorView()
        .environment(DataStore())
}
