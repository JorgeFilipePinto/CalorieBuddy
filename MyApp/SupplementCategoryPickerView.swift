import SwiftUI

/// Picks a supplement category from the user-extensible list, with a final "+" row to create
/// a new one on the spot (it's saved globally and selected immediately).
struct SupplementCategoryPickerView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedCategoryID: UUID?

    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.supplementCategories) { category in
                    Button {
                        selectedCategoryID = category.id
                        dismiss()
                    } label: {
                        HStack {
                            Text(category.name)
                            Spacer()
                            if selectedCategoryID == category.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    newCategoryName = ""
                    showingNewCategoryAlert = true
                } label: {
                    Label("Nova Categoria", systemImage: "plus")
                }
            }
            .navigationTitle("Categoria")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .alert("Nova Categoria", isPresented: $showingNewCategoryAlert) {
                TextField("Nome", text: $newCategoryName)
                Button("Cancelar", role: .cancel) {}
                Button("Criar") {
                    let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    let category = SupplementCategory(name: trimmed)
                    store.addSupplementCategory(category)
                    selectedCategoryID = category.id
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    SupplementCategoryPickerView(selectedCategoryID: .constant(nil))
        .environment(DataStore())
}
