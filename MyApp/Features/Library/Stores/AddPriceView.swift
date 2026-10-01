import SwiftUI

/// Lets the user attach a price at an existing store, or create a new store on the spot.
/// Shared by the food and supplement editors — pricing/promotion/package logic is identical.
struct AddPriceView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let compatibleUnits: [MeasurementUnit]
    let onAdd: (UUID, Double, Double, MeasurementUnit, Bool, Double?) -> Void

    @State private var selectedStoreID: UUID?
    @State private var newStoreName = ""
    @State private var price: Double = 0
    @State private var packageSize: Double
    @State private var packageUnit: MeasurementUnit
    @State private var isPromotion = false
    @State private var regularPrice: Double = 0

    init(
        compatibleUnits: [MeasurementUnit],
        defaultPackageSize: Double = 1,
        onAdd: @escaping (UUID, Double, Double, MeasurementUnit, Bool, Double?) -> Void
    ) {
        self.compatibleUnits = compatibleUnits
        self.onAdd = onAdd
        _packageSize = State(initialValue: defaultPackageSize)
        _packageUnit = State(initialValue: compatibleUnits.first ?? .unit)
    }

    private var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Loja") {
                    if store.stores.isEmpty {
                        Text("Ainda não tens lojas guardadas.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Loja", selection: $selectedStoreID) {
                            Text("Escolhe...").tag(UUID?.none)
                            ForEach(store.stores) { existingStore in
                                Text(existingStore.name).tag(Optional(existingStore.id))
                            }
                        }
                    }
                    HStack {
                        TextField("Ou cria uma loja nova", text: $newStoreName)
                        Button("Criar") {
                            let trimmed = newStoreName.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            let newStore = Store(name: trimmed)
                            store.addStore(newStore)
                            selectedStoreID = newStore.id
                            newStoreName = ""
                        }
                        .disabled(newStoreName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Embalagem") {
                    HStack {
                        Text("Tamanho")
                        Spacer()
                        TextField("1", value: $packageSize, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Picker("Unidade", selection: $packageUnit) {
                            ForEach(compatibleUnits) { compatibleUnit in
                                Text(compatibleUnit.shortLabel).tag(compatibleUnit)
                            }
                        }
                        .labelsHidden()
                    }
                }

                Section("Preço") {
                    TextField("0,00", value: $price, format: .currency(code: currencyCode))
                        .keyboardType(.decimalPad)
                    Toggle("Este preço é uma promoção", isOn: $isPromotion)
                    if isPromotion {
                        TextField("Preço normal (sem promoção)", value: $regularPrice, format: .currency(code: currencyCode))
                            .keyboardType(.decimalPad)
                    }
                }
            }
            .navigationTitle("Adicionar Preço")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adicionar") {
                        if let selectedStoreID {
                            onAdd(selectedStoreID, price, packageSize, packageUnit, isPromotion, isPromotion ? regularPrice : nil)
                        }
                        dismiss()
                    }
                    .disabled(selectedStoreID == nil)
                }
            }
        }
    }
}

#Preview {
    AddPriceView(compatibleUnits: [.gram, .kilogram]) { _, _, _, _, _, _ in }
        .environment(DataStore())
}
