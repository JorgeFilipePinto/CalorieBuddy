import SwiftUI

struct StoreEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let storeToEdit: Store?

    @State private var name = ""

    init(storeToEdit: Store? = nil) {
        self.storeToEdit = storeToEdit
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome da loja", text: $name)
            }
            .navigationTitle(storeToEdit == nil ? "Nova Loja" : "Editar Loja")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear { name = storeToEdit?.name ?? "" }
        }
    }

    private func save() {
        let entry = Store(id: storeToEdit?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespaces))
        if storeToEdit == nil {
            store.addStore(entry)
        } else {
            store.updateStore(entry)
        }
        dismiss()
    }
}

#Preview {
    StoreEditorView()
        .environment(DataStore())
}
