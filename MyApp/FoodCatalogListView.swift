import SwiftUI

/// Manages the reusable food catalog — items that can be scanned, quick-logged, or combined
/// into recipes.
struct FoodCatalogListView: View {
    @Environment(DataStore.self) private var store

    @State private var showingAddFoodItem = false
    @State private var foodItemToEdit: FoodItem?
    @State private var searchText = ""
    @State private var sortOrder: ItemSortOrder = .name

    private var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }

    private var visibleItems: [FoodItem] {
        store.foodItems.filteredAndSorted(searchText: searchText, order: sortOrder)
    }

    private var favorites: [FoodItem] { visibleItems.filter(\.isFavorite) }
    private var others: [FoodItem] { visibleItems.filter { !$0.isFavorite } }
    private var alphabeticalGroups: [(letter: String, items: [FoodItem])] { others.groupedAlphabetically }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                if sortOrder == .name, !alphabeticalGroups.isEmpty {
                    AlphabetIndexScrollBar(availableLetters: Set(alphabeticalGroups.map(\.letter))) { letter in
                        withAnimation { proxy.scrollTo(letter, anchor: .top) }
                    }
                }
                List {
                    if store.foodItems.isEmpty {
                        ContentUnavailableView(
                            "Sem Alimentos",
                            systemImage: "carrot",
                            description: Text("Adiciona alimentos ao catálogo para os reutilizares em registos e receitas.")
                        )
                    } else {
                        if !favorites.isEmpty {
                            Section("Favoritos") {
                                ForEach(favorites) { item in
                                    row(for: item)
                                }
                            }
                        }
                        if others.isEmpty && favorites.isEmpty {
                            Text("Sem resultados para \"\(searchText)\".")
                                .foregroundStyle(.secondary)
                        } else if sortOrder == .name {
                            ForEach(alphabeticalGroups, id: \.letter) { group in
                                Section(group.letter) {
                                    ForEach(group.items) { item in
                                        row(for: item)
                                    }
                                }
                                .id(group.letter)
                            }
                        } else {
                            Section(favorites.isEmpty ? "" : "Todos") {
                                ForEach(others) { item in
                                    row(for: item)
                                }
                            }
                        }
                    }
                }
                .refreshable { store.reloadFromDisk() }
            }
        }
        .navigationTitle("Catálogo de Alimentos")
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
                    showingAddFoodItem = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddFoodItem) {
            FoodItemEditorView()
        }
        .sheet(item: $foodItemToEdit) { item in
            FoodItemEditorView(itemToEdit: item)
        }
    }

    private func row(for item: FoodItem) -> some View {
        Button {
            foodItemToEdit = item
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    HStack(spacing: 4) {
                        Text(item.brand.map { "\(item.name) (\($0))" } ?? item.name)
                        if item.isFavorite {
                            Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                        }
                    }
                    HStack(spacing: 4) {
                        Text("dose \(item.doseLabel) · \(item.scaledCalories(quantity: 1)) kcal")
                        if let doseCost = store.cost(for: item, quantity: 1) {
                            Text("· \(doseCost.formatted(.currency(code: currencyCode)))")
                            if store.cheapestPrice(for: item)?.isPromotion == true {
                                Image(systemName: "tag.fill").foregroundStyle(.orange)
                            }
                        }
                        if !item.barcodes.isEmpty {
                            Label("\(item.barcodes.count)", systemImage: "barcode")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button {
                store.toggleFavorite(item)
            } label: {
                Label(item.isFavorite ? "Remover Favorito" : "Favorito", systemImage: item.isFavorite ? "star.slash" : "star.fill")
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteFoodItem(item)
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }
}

#Preview {
    NavigationStack {
        FoodCatalogListView()
    }
    .environment(DataStore())
}
