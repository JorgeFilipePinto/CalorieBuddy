import SwiftUI

/// Quick-log sheet for a supplement: pick it, which stock to draw from (if any), and how much
/// via two dropdowns — a whole number of doses (1–10) plus an extra percentage of a dose.
struct SupplementPickerView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @State private var selectedSupplementID: UUID?
    @State private var selectedStockID: UUID?
    @State private var wholeDoses = 1
    @State private var percentage = 0

    @State private var showingLowStockAlert = false
    @State private var lowStockSupplementName = ""

    private let percentageOptions = [0, 25, 50, 75]

    private var selectedSupplement: Supplement? {
        selectedSupplementID.flatMap { store.supplement(withID: $0) }
    }

    private var quantity: Double {
        Double(wholeDoses) + Double(percentage) / 100
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Suplemento") {
                    if store.supplements.isEmpty {
                        ContentUnavailableView(
                            "Sem Suplementos",
                            systemImage: "pills.fill",
                            description: Text("Adiciona suplementos no separador Alimentos.")
                        )
                    } else {
                        Picker("Suplemento", selection: $selectedSupplementID) {
                            Text("Escolhe...").tag(UUID?.none)
                            ForEach(store.supplements) { supplement in
                                Text(supplement.name).tag(Optional(supplement.id))
                            }
                        }
                    }
                }

                if let selectedSupplement {
                    if !selectedSupplement.stocks.isEmpty {
                        Section("Stock") {
                            Picker("Retirar de", selection: $selectedStockID) {
                                Text("Nenhum (não descontar)").tag(UUID?.none)
                                ForEach(selectedSupplement.stocks) { stock in
                                    let locationName = store.stockLocation(withID: stock.locationID)?.name ?? "Local"
                                    Text("\(locationName) (\(formatted(stock.remaining)) \(selectedSupplement.unit.shortLabel))")
                                        .tag(Optional(stock.id))
                                }
                            }
                        }
                    }

                    Section {
                        HStack {
                            Text("Doses")
                            Spacer()
                            Picker("Doses", selection: $wholeDoses) {
                                ForEach(1...10, id: \.self) { count in
                                    Text("\(count)").tag(count)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()

                            Text("+")
                                .foregroundStyle(.secondary)

                            Picker("Percentagem", selection: $percentage) {
                                ForEach(percentageOptions, id: \.self) { percent in
                                    Text("\(percent)%").tag(percent)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        let calorieText = selectedSupplement.calories.map { _ in
                            " · \(selectedSupplement.scaledCalories(quantity: quantity)) kcal"
                        } ?? ""
                        Text("Total: \(formatted(quantity)) doses" + calorieText)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Quantidade")
                    }
                }
            }
            .navigationTitle("Suplemento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registar") { log() }
                        .disabled(selectedSupplement == nil)
                }
            }
            .alert("Stock Baixo", isPresented: $showingLowStockAlert) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text("O stock de \(lowStockSupplementName) está a acabar — talvez seja altura de comprar mais.")
            }
        }
    }

    private func log() {
        guard let selectedSupplement else { return }
        let isLowStock = store.logSupplement(
            selectedSupplement,
            stockID: selectedStockID,
            quantity: quantity,
            date: date
        )
        if isLowStock {
            lowStockSupplementName = selectedSupplement.name
            showingLowStockAlert = true
        } else {
            dismiss()
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.2f", value)
    }
}

#Preview {
    SupplementPickerView(date: .now)
        .environment(DataStore())
}
