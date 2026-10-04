import SwiftUI

/// Manages the reusable food catalog — items that can be scanned, quick-logged, or combined
/// into recipes.
struct FoodCatalogListView: View {
    @Environment(DataStore.self) private var store

    @State private var showingAddFoodItem = false
    @State private var showingJSONImport = false
    @State private var foodItemToEdit: FoodItem?
    @State private var searchText = ""
    @State private var sortOrder: ItemSortOrder = .name
    @State private var showingCategories = false
    @AppStorage("CalorieBuddy.catalogGroupedByCategory") private var groupedByCategory = true
    /// Multi-select mode: rows toggle a check mark instead of opening the editor.
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var confirmingDelete = false

    private var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }

    private var visibleItems: [FoodItem] {
        store.foodItems.filteredAndSorted(searchText: searchText, order: sortOrder)
    }

    private var favorites: [FoodItem] { visibleItems.filter(\.isFavorite) }
    private var others: [FoodItem] { visibleItems.filter { !$0.isFavorite } }
    private var alphabeticalGroups: [(letter: String, items: [FoodItem])] { others.groupedAlphabetically }

    /// One section per category (in the categories' order), then the uncategorised foods.
    private var categoryGroups: [(id: String, title: String, items: [FoodItem])] {
        var groups: [(id: String, title: String, items: [FoodItem])] = store.foodCategories.compactMap { category in
            let items = others.filter { $0.categoryID == category.id }
            return items.isEmpty ? nil : (category.id.uuidString, category.name, items)
        }
        let known = Set(store.foodCategories.map(\.id))
        let rest = others.filter { $0.categoryID.map { !known.contains($0) } ?? true }
        if !rest.isEmpty { groups.append(("none", "Sem categoria", rest)) }
        return groups
    }

    private var showsAlphabetIndex: Bool { !groupedByCategory && sortOrder == .name && !alphabeticalGroups.isEmpty }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                if showsAlphabetIndex {
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
                        } else if groupedByCategory {
                            ForEach(categoryGroups, id: \.id) { group in
                                Section("\(group.title) (\(group.items.count))") {
                                    ForEach(group.items) { item in
                                        row(for: item)
                                    }
                                }
                            }
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
                .refreshable {
                    Haptics.light()
                    store.reloadFromDisk()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                SelectionDeleteBar(count: selectedIDs.count, noun: ("alimento", "alimentos")) { confirmingDelete = true }
            }
        }
        .confirmationDialog(
            selectedIDs.count == 1 ? "Eliminar 1 alimento?" : "Eliminar \(selectedIDs.count) alimentos?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                store.deleteFoodItems(withIDs: selectedIDs)
                Haptics.light()
                selectedIDs = []
                isSelecting = false
            }
        } message: {
            Text("Também saem das receitas que os usam. O que já está registado no diário mantém-se.")
        }
        .navigationTitle(isSelecting ? "\(selectedIDs.count) Selecionados" : "Catálogo de Alimentos")
        .trackScreen("Catálogo de Alimentos")
        .searchable(text: $searchText, prompt: "Procurar por nome")
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    let allVisible = Set(visibleItems.map(\.id))
                    Button(allVisible.isSubset(of: selectedIDs) ? "Nenhum" : "Todos") {
                        selectedIDs = allVisible.isSubset(of: selectedIDs) ? [] : allVisible
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        isSelecting = false
                        selectedIDs = []
                    }
                }
            } else {
            ToolbarItem(placement: .topBarLeading) {
                Picker("Ordenar por", selection: $sortOrder) {
                    ForEach(ItemSortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
                .pickerStyle(.menu)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Selecionar") { isSelecting = true }
                    .disabled(store.foodItems.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddFoodItem = true
                    } label: {
                        Label("Novo Alimento", systemImage: "square.and.pencil")
                    }
                    Toggle(isOn: $groupedByCategory) {
                        Label("Agrupar por Categoria", systemImage: "square.grid.2x2")
                    }
                    Button {
                        showingCategories = true
                    } label: {
                        Label("Gerir Categorias", systemImage: "tag")
                    }
                    Button {
                        showingJSONImport = true
                    } label: {
                        Label("Importar JSON (IA)", systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            }
        }
        .sheet(isPresented: $showingAddFoodItem) {
            FoodItemEditorView()
        }
        .sheet(isPresented: $showingJSONImport) {
            JSONImportSheet(
                title: "Importar Alimentos",
                prompt: AIJSONImport.foodPrompt,
                instructions: "Útil quando não há rótulo à mão. Todos os alimentos da resposta são adicionados ao catálogo; um alimento com o mesmo nome de um já existente é mantido como está."
            ) { json in
                let payloads = try AIJSONImport.decodeFoodItems(from: json)
                guard !payloads.isEmpty else { throw AIImportError.empty }
                for payload in payloads {
                    store.catalogFood(for: payload)
                }
            }
        }
        .sheet(isPresented: $showingCategories) {
            NavigationStack { FoodCategoriesView() }
        }
        .sheet(item: $foodItemToEdit) { item in
            FoodItemEditorView(itemToEdit: item)
        }
    }

    private func row(for item: FoodItem) -> some View {
        Button {
            if isSelecting {
                toggleSelection(item.id)
            } else {
                foodItemToEdit = item
            }
        } label: {
            HStack {
                if isSelecting {
                    SelectionMark(isSelected: selectedIDs.contains(item.id))
                }
                PhotoThumbnail(photoID: item.photoID, placeholder: "carrot")
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
                if !isSelecting {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            if !isSelecting {
            Button {
                store.toggleFavorite(item)
            } label: {
                Label(item.isFavorite ? "Remover Favorito" : "Favorito", systemImage: item.isFavorite ? "star.slash" : "star.fill")
            }
            .tint(.yellow)
            }
        }
        .swipeActions(edge: .trailing) {
            if !isSelecting {
                Button(role: .destructive) {
                    store.deleteFoodItem(item)
                } label: {
                    Label("Eliminar", systemImage: "trash")
                }
            }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        Haptics.light()
    }
}

#Preview {
    NavigationStack {
        FoodCatalogListView()
    }
    .environment(DataStore())
}
