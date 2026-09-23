import SwiftUI

/// Manage sports supplements: proteins, energy gels, isotonics, electrolytes, etc. Favorites
/// come first, then the rest grouped by their (user-extensible) category.
struct SupplementsListView: View {
    @Environment(DataStore.self) private var store

    @State private var showingAddSupplement = false
    @State private var supplementToEdit: Supplement?
    @State private var searchText = ""
    @State private var sortOrder: ItemSortOrder = .dateAdded

    private var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }

    private var visibleSupplements: [Supplement] {
        store.supplements.filteredAndSorted(searchText: searchText, order: sortOrder)
    }

    private var favorites: [Supplement] { visibleSupplements.filter(\.isFavorite) }

    private var categoriesWithSupplements: [(category: SupplementCategory, supplements: [Supplement])] {
        let others = visibleSupplements.filter { !$0.isFavorite }
        return store.supplementCategories.compactMap { category in
            let matching = others.filter { $0.categoryID == category.id }
            return matching.isEmpty ? nil : (category, matching)
        }
    }

    var body: some View {
        List {
            if store.supplements.isEmpty {
                ContentUnavailableView(
                    "Sem Suplementos",
                    systemImage: "pills.fill",
                    description: Text("Adiciona proteínas, géis, isotónicos ou eletrólitos.")
                )
            } else if visibleSupplements.isEmpty {
                Text("Sem resultados para \"\(searchText)\".")
                    .foregroundStyle(.secondary)
            } else {
                if !favorites.isEmpty {
                    Section("Favoritos") {
                        ForEach(favorites) { supplement in
                            row(for: supplement)
                        }
                    }
                }
                ForEach(categoriesWithSupplements, id: \.category.id) { entry in
                    Section(entry.category.name) {
                        ForEach(entry.supplements) { supplement in
                            row(for: supplement)
                        }
                    }
                }
            }
        }
        .navigationTitle("Suplementos")
        .searchable(text: $searchText, prompt: "Procurar por nome")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Picker("Ordenar por", selection: $sortOrder) {
                    ForEach(ItemSortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
                .pickerStyle(.menu)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSupplement = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSupplement) {
            SupplementEditorView()
        }
        .sheet(item: $supplementToEdit) { supplement in
            SupplementEditorView(supplementToEdit: supplement)
        }
    }

    private func row(for supplement: Supplement) -> some View {
        Button {
            supplementToEdit = supplement
        } label: {
            supplementRow(supplement)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button {
                store.toggleFavorite(supplement)
            } label: {
                Label(supplement.isFavorite ? "Remover Favorito" : "Favorito", systemImage: supplement.isFavorite ? "star.slash" : "star.fill")
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteSupplement(supplement)
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }

    private func supplementRow(_ supplement: Supplement) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(supplement.name)
                    if supplement.isFavorite {
                        Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                    }
                }
                HStack(spacing: 4) {
                    Text("dose \(supplement.doseLabel)")
                    if let calories = supplement.calories {
                        Text("· \(calories) kcal")
                    }
                    if let doseCost = store.cost(for: supplement, quantity: 1) {
                        Text("· \(doseCost.formatted(.currency(code: currencyCode)))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !supplement.stocks.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(supplement.stocks) { stock in
                            let isLow = supplement.lowStockThreshold.map { stock.remaining <= $0 } ?? false
                            let locationName = store.stockLocation(withID: stock.locationID)?.name ?? "Local"
                            Label(
                                "\(locationName): \(formatted(stock.remaining)) \(supplement.unit.shortLabel)",
                                systemImage: isLow ? "exclamationmark.triangle.fill" : "shippingbox"
                            )
                            .foregroundStyle(isLow ? .red : .secondary)
                        }
                    }
                    .font(.caption2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

#Preview {
    NavigationStack {
        SupplementsListView()
    }
    .environment(DataStore())
}
