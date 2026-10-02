import SwiftUI

/// Manages saved recipes — groups of catalog foods that can be logged together in one action.
struct RecipesListView: View {
    @Environment(DataStore.self) private var store

    @State private var showingAddRecipe = false
    @State private var showingJSONImport = false
    @State private var jsonImportName = ""
    @State private var recipeToEdit: Recipe?
    @State private var searchText = ""
    @State private var sortOrder: ItemSortOrder = .name

    private var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }

    private var visibleRecipes: [Recipe] {
        store.recipes.filteredAndSorted(searchText: searchText, order: sortOrder)
    }

    private var favorites: [Recipe] { visibleRecipes.filter(\.isFavorite) }
    private var others: [Recipe] { visibleRecipes.filter { !$0.isFavorite } }
    private var alphabeticalGroups: [(letter: String, items: [Recipe])] { others.groupedAlphabetically }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                if sortOrder == .name, !alphabeticalGroups.isEmpty {
                    AlphabetIndexScrollBar(availableLetters: Set(alphabeticalGroups.map(\.letter))) { letter in
                        withAnimation { proxy.scrollTo(letter, anchor: .top) }
                    }
                }
                List {
                    if store.recipes.isEmpty {
                        ContentUnavailableView(
                            "Sem Receitas",
                            systemImage: "list.bullet.rectangle",
                            description: Text("Cria uma receita combinando alimentos do catálogo.")
                        )
                    } else {
                        if !favorites.isEmpty {
                            Section("Favoritos") {
                                ForEach(favorites) { recipe in
                                    row(for: recipe)
                                }
                            }
                        }
                        if others.isEmpty && favorites.isEmpty {
                            Text("Sem resultados para \"\(searchText)\".")
                                .foregroundStyle(.secondary)
                        } else if sortOrder == .name {
                            ForEach(alphabeticalGroups, id: \.letter) { group in
                                Section(group.letter) {
                                    ForEach(group.items) { recipe in
                                        row(for: recipe)
                                    }
                                }
                                .id(group.letter)
                            }
                        } else {
                            Section(favorites.isEmpty ? "" : "Todas") {
                                ForEach(others) { recipe in
                                    row(for: recipe)
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
        .navigationTitle("Receitas")
        .trackScreen("Receitas")
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
                Menu {
                    Button {
                        showingAddRecipe = true
                    } label: {
                        Label("Nova Receita", systemImage: "square.and.pencil")
                    }
                    Button {
                        jsonImportName = ""
                        showingJSONImport = true
                    } label: {
                        Label("Importar JSON (IA)", systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddRecipe) {
            RecipeEditorView()
        }
        .sheet(isPresented: $showingJSONImport) {
            JSONImportSheet(
                title: "Importar Receita",
                prompt: AIJSONImport.recipePrompt,
                instructions: "Útil quando não sabes ao detalhe o valor nutricional de cada ingrediente. Os ingredientes novos são adicionados ao catálogo; um com o mesmo nome de um alimento já existente é reutilizado.",
                additionalFields: {
                    Section {
                        TextField("Nome (opcional)", text: $jsonImportName)
                    } header: {
                        Text("Receita")
                    } footer: {
                        Text("Em branco, usa o nome que a IA der à receita.")
                    }
                },
                isReadyToImport: { true }
            ) { json in
                try handleJSONImport(json)
            }
        }
        .sheet(item: $recipeToEdit) { recipe in
            RecipeEditorView(recipeToEdit: recipe)
        }
    }

    /// Creates the recipe straight from the AI's answer: its ingredients come from (or are added
    /// to) the catalog, and the name typed in the sheet wins over the one the AI gave.
    private func handleJSONImport(_ json: String) throws {
        let payload = try AIJSONImport.decodeRecipe(from: json)
        let typedName = jsonImportName.trimmingCharacters(in: .whitespaces)
        let name = typedName.isEmpty ? (payload.name ?? "").trimmingCharacters(in: .whitespaces) : typedName
        guard !name.isEmpty else { throw AIImportError.missingRecipeName }

        store.addRecipe(Recipe(name: name, items: payload.items.map(store.recipeItem(for:))))
    }

    private func row(for recipe: Recipe) -> some View {
        Button {
            recipeToEdit = recipe
        } label: {
            HStack {
                PhotoThumbnail(photoID: recipe.photoID, placeholder: "fork.knife")
                VStack(alignment: .leading) {
                    HStack(spacing: 4) {
                        Text(recipe.name)
                        if recipe.isFavorite {
                            Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                        }
                    }
                    Text(recipeSubtitle(recipe))
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
                store.toggleFavorite(recipe)
            } label: {
                Label(recipe.isFavorite ? "Remover Favorito" : "Favorito", systemImage: recipe.isFavorite ? "star.slash" : "star.fill")
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteRecipe(recipe)
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }

    private func recipeSubtitle(_ recipe: Recipe) -> String {
        let cost = store.totalCost(for: recipe)
        var text = "\(recipe.items.count) alimentos · \(store.totalCalories(for: recipe)) kcal"
        if cost > 0 {
            text += " · \(cost.formatted(.currency(code: currencyCode)))"
        }
        return text
    }
}

#Preview {
    NavigationStack {
        RecipesListView()
    }
    .environment(DataStore())
}
