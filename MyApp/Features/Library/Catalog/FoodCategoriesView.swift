import SwiftUI

/// Create, rename and delete the food categories the catalog is grouped by. Deleting one keeps
/// its foods, uncategorised.
struct FoodCategoriesView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editing: FoodCategory?
    @State private var isAdding = false
    @State private var name = ""
    @State private var categoryToDelete: FoodCategory?

    var body: some View {
        List {
            Section {
                ForEach(store.foodCategories) { category in
                    Button {
                        name = category.name
                        editing = category
                    } label: {
                        HStack {
                            Text(category.name).foregroundStyle(.primary)
                            Spacer()
                            Text("\(count(category))").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .swipeActions {
                        Button("Eliminar", role: .destructive) { categoryToDelete = category }
                    }
                }
            } footer: {
                Text("Toca numa categoria para a renomear; desliza para a eliminar (os alimentos ficam sem categoria).")
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
                    name = ""
                    isAdding = true
                } label: {
                    Label("Nova Categoria", systemImage: "plus")
                }
            }
        }
        .alert("Nova Categoria", isPresented: $isAdding) {
            TextField("Nome", text: $name)
            Button("Cancelar", role: .cancel) {}
            Button("Adicionar") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !exists(trimmed) else { return }
                store.addFoodCategory(FoodCategory(name: trimmed))
            }
        }
        .alert("Renomear Categoria", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Nome", text: $name)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if let editing, !trimmed.isEmpty { store.renameFoodCategory(editing, to: trimmed) }
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
            Text("Os alimentos desta categoria ficam sem categoria.")
        }
        .trackScreen("Categorias de Alimentos")
    }

    private func count(_ category: FoodCategory) -> Int {
        store.foodItems.filter { $0.categoryID == category.id }.count
    }

    private func exists(_ name: String) -> Bool {
        store.foodCategories.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }
}
