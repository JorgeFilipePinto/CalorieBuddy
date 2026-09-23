import SwiftUI

/// Shows the active database's raw JSON and lets the user hand-edit it from within the app.
/// Saving behaves exactly like importing a file: the previous active database is preserved
/// as the backup first.
struct JSONEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var showSaveConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView(
                        "Não Foi Possível Carregar",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else {
                    TextEditor(text: $text)
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .padding(4)
                }
            }
            .navigationTitle("JSON da Base de Dados")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        showSaveConfirmation = true
                    }
                    .disabled(loadError != nil)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog(
                "Guardar alterações?",
                isPresented: $showSaveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Guardar e Substituir", role: .destructive) { save() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("A base de dados atual será guardada como backup antes de aplicar este JSON.")
            }
            .alert(
                "Erro ao Guardar",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func load() {
        do {
            text = try store.activeDatabaseJSON()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        do {
            try store.applyEditedJSON(text)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    JSONEditorView()
        .environment(DataStore())
}
