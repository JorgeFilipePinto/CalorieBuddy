import SwiftUI

/// A consolidated view of every stock across every supplement, grouped by location (e.g. "Casa",
/// "Trabalho") — separate sections per place, since that's how the physical stock is actually
/// organized — so the amounts on hand are visible at a glance without opening each supplement.
/// Low stock is flagged the same way as in the supplement editor.
struct StocksListView: View {
    @Environment(DataStore.self) private var store

    @State private var supplementToEdit: Supplement?

    private struct StockRow: Identifiable {
        let id: UUID
        let supplement: Supplement
        let stock: SupplementStock
    }

    private var rowsByLocation: [(location: StockLocation, rows: [StockRow])] {
        let allRows = store.supplements.flatMap { supplement in
            supplement.stocks.map { StockRow(id: $0.id, supplement: supplement, stock: $0) }
        }
        return store.stockLocations.compactMap { location in
            let matching = allRows
                .filter { $0.stock.locationID == location.id }
                .sorted { $0.supplement.name.localizedStandardCompare($1.supplement.name) == .orderedAscending }
            return matching.isEmpty ? nil : (location, matching)
        }
    }

    var body: some View {
        List {
            if rowsByLocation.isEmpty {
                ContentUnavailableView(
                    "Sem Stocks",
                    systemImage: "shippingbox",
                    description: Text("Cria stocks dentro de cada suplemento (ex: Casa, Trabalho) para os veres aqui.")
                )
            } else {
                ForEach(rowsByLocation, id: \.location.id) { entry in
                    Section(entry.location.name) {
                        ForEach(entry.rows) { row in
                            Button {
                                supplementToEdit = row.supplement
                            } label: {
                                stockRow(row)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Stocks")
        .sheet(item: $supplementToEdit) { supplement in
            SupplementEditorView(supplementToEdit: supplement)
        }
    }

    private func stockRow(_ row: StockRow) -> some View {
        let isLow = row.supplement.lowStockThreshold.map { row.stock.remaining <= $0 } ?? false
        return HStack {
            Text(row.supplement.name)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(formatted(row.stock.remaining)) \(row.supplement.unit.shortLabel)")
                    .foregroundStyle(isLow ? .red : .primary)
                if isLow {
                    Label("Comprar", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

#Preview {
    NavigationStack {
        StocksListView()
    }
    .environment(DataStore())
}
