import SwiftUI

/// Create, rename, nest and delete the food categories the catalog is grouped by — two levels:
/// categories and their subcategories (Proteína → Carne, Peixe, Ovos). Deleting one moves its
/// foods to its parent (uncategorised for a top-level one).
struct FoodCategoriesView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var target: Target?
    @State private var categoryToDelete: FoodCategory?

    /// What the editor sheet edits: an existing category, or a new one (under `parentID`).
    private struct Target: Identifiable {
        let category: FoodCategory?
        let parentID: UUID?
        let id = UUID()
    }

    var body: some View {
        List {
            ForEach(store.topLevelFoodCategories) { category in
                Section {
                    row(category, isSub: false)
                    ForEach(store.subcategories(of: category)) { sub in
                        row(sub, isSub: true)
                    }
                    Button {
                        target = Target(category: nil, parentID: category.id)
                    } label: {
                        Label("Subcategoria em \(category.name)", systemImage: "plus")
                            .font(.subheadline)
                    }
                }
            }
            Section {
            } footer: {
                Text("Toca numa categoria para a renomear ou mudar de sítio; desliza para a eliminar (os alimentos passam para a categoria de cima, ou ficam sem categoria).")
            }
        }
        .navigationTitle("Categorias")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Concluído") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    target = Target(category: nil, parentID: nil)
                } label: {
                    Label("Nova Categoria", systemImage: "plus")
                }
            }
        }
        .sheet(item: $target) { target in
            NavigationStack {
                FoodCategoryEditorView(category: target.category, initialParentID: target.parentID)
            }
        }
        .confirmationDialog(
            "Eliminar \"\(categoryToDelete?.name ?? "")\"?",
            isPresented: Binding(get: { categoryToDelete != nil }, set: { if !$0 { categoryToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let categoryToDelete { store.deleteFoodCategory(categoryToDelete) }
            }
        } message: {
            Text(categoryToDelete?.parentID != nil
                 ? "Os alimentos passam para a categoria de cima."
                 : "Os alimentos desta categoria ficam sem categoria e as subcategorias passam a categorias.")
        }
        .trackScreen("Categorias de Alimentos")
    }

    private func row(_ category: FoodCategory, isSub: Bool) -> some View {
        Button {
            target = Target(category: category, parentID: category.parentID)
        } label: {
            HStack {
                if isSub {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary).font(.caption)
                }
                Text(category.name)
                    .foregroundStyle(.primary)
                    .fontWeight(isSub ? .regular : .semibold)
                Spacer()
                Text("\(count(category))").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .swipeActions {
            Button("Eliminar", role: .destructive) { categoryToDelete = category }
        }
    }

    private func count(_ category: FoodCategory) -> Int {
        store.foodItems.filter { $0.categoryID == category.id }.count
    }
}

/// Name and place (top level, or inside another category) of a food category.
private struct FoodCategoryEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let category: FoodCategory?
    let initialParentID: UUID?

    @State private var name = ""
    @State private var parentID: UUID?
    @State private var didLoad = false

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    /// Another category with this name at the same level.
    private var isDuplicate: Bool {
        store.foodCategories.contains {
            $0.id != category?.id && $0.parentID == parentID && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    /// A category with subcategories stays top-level (two levels only).
    private var canNest: Bool { category.map { store.subcategories(of: $0).isEmpty } ?? true }

    var body: some View {
        Form {
            Section {
                TextField("Nome (ex: Carne)", text: $name)
                Picker("Dentro de", selection: $parentID) {
                    Text("Nenhuma (categoria principal)").tag(UUID?.none)
                    if canNest {
                        ForEach(store.topLevelFoodCategories.filter { $0.id != category?.id }) { parent in
                            Text(parent.name).tag(UUID?.some(parent.id))
                        }
                    }
                }
            } footer: {
                if !canNest {
                    Text("Tem subcategorias, por isso fica como categoria principal.")
                } else if isDuplicate {
                    Text("Já existe uma categoria com este nome aqui.").foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(category == nil ? (initialParentID == nil ? "Nova Categoria" : "Nova Subcategoria") : "Categoria")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { save() }
                    .disabled(trimmed.isEmpty || isDuplicate)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            name = category?.name ?? ""
            parentID = initialParentID
        }
    }

    private func save() {
        if let category {
            if trimmed != category.name { store.renameFoodCategory(category, to: trimmed) }
            if parentID != category.parentID { store.setParent(of: category, to: parentID) }
        } else {
            store.addFoodCategory(FoodCategory(name: trimmed, parentID: parentID))
        }
        dismiss()
    }
}
