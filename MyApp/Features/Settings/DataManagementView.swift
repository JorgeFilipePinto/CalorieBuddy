import SwiftUI
import UniformTypeIdentifiers

/// Everything that exports, replaces or erases the app's data, kept off the main Settings screen
/// so none of it is one stray tap away. Sections go from harmless to dangerous: exporting copies,
/// importing/restoring replace (always confirmed, previous state kept as backup), the JSON editor
/// changes data directly, and deleting everything sits alone at the bottom.
struct DataManagementView: View {
    @Environment(DataStore.self) private var store

    @State private var activeExportURL: URL?
    @State private var showActiveMover = false
    @State private var backupExportURL: URL?
    @State private var showBackupMover = false

    @State private var isImporting = false
    @State private var pendingImportURL: URL?
    @State private var showImportConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var showingJSONEditor = false
    @State private var showingDeleteAllConfirmation = false

    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Button {
                    exportActive()
                } label: {
                    SettingsRowLabel(title: "Exportar Base de Dados", systemImage: "square.and.arrow.down", color: .blue)
                }

                Button {
                    exportBackup()
                } label: {
                    SettingsRowLabel(title: "Exportar Backup", systemImage: "square.and.arrow.down.on.square", color: .blue)
                }
                .disabled(!store.hasBackup)
            } header: {
                Text("Exportar")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Guarda uma cópia num ficheiro — não altera nada na app. O ficheiro inclui tudo: registos diários, catálogo de alimentos, receitas, plano alimentar, suplementos, categorias, stocks, lojas, preços e definições. As fotos (de alimentos, receitas, suplementos e evolução física) não vão no ficheiro: ficam guardadas à parte, no telemóvel.")
                    if let backupTimestamp = store.backupTimestamp {
                        Text("Último backup: \(backupTimestamp.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text("Ainda não existe nenhum backup. É criado automaticamente sempre que importares uma base de dados.")
                    }
                }
            }

            Section {
                Button {
                    isImporting = true
                } label: {
                    SettingsRowLabel(title: "Importar Base de Dados", systemImage: "square.and.arrow.up", color: .orange)
                }

                Button {
                    showRestoreConfirmation = true
                } label: {
                    SettingsRowLabel(title: "Restaurar Backup", systemImage: "arrow.uturn.backward", color: .orange)
                }
                .disabled(!store.hasBackup)
            } header: {
                Text("Importar e Restaurar")
            } footer: {
                Text("Substituem os dados atuais. Pedem sempre confirmação e guardam a versão anterior como backup.")
            }

            Section {
                Button {
                    showingJSONEditor = true
                } label: {
                    SettingsRowLabel(title: "Ver / Editar JSON", systemImage: "curlybraces", color: .gray)
                }
            } header: {
                Text("Avançado")
            } footer: {
                Text("Mostra o JSON completo da base de dados ativa, exatamente como seria exportado. Guardar altera os teus dados diretamente e cria um backup da versão anterior, tal como importar um ficheiro.")
            }

            Section {
                Button {
                    showingDeleteAllConfirmation = true
                } label: {
                    SettingsRowLabel(title: "Eliminar Todos os Dados", systemImage: "trash.fill", color: .red, isDestructive: true)
                }
            } header: {
                Text("Zona de Perigo")
            } footer: {
                Text("Elimina permanentemente tudo o que esta app tem guardado no telemóvel, incluindo o backup. Pede confirmação com pressão longa de 5 segundos.")
            }
        }
        .navigationTitle("Gestão de Dados")
        .trackScreen("Gestão de Dados")
        .sheet(isPresented: $showingJSONEditor) {
            JSONEditorView()
        }
        .sheet(isPresented: $showingDeleteAllConfirmation) {
            DeleteAllDataConfirmationView()
        }
        .fileMover(isPresented: $showActiveMover, file: activeExportURL) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .fileMover(isPresented: $showBackupMover, file: backupExportURL) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                pendingImportURL = url
                showImportConfirmation = true
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Substituir a base de dados ativa?",
            isPresented: $showImportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Importar e Substituir", role: .destructive) {
                performImport()
            }
            Button("Cancelar", role: .cancel) {
                pendingImportURL = nil
            }
        } message: {
            Text("A base de dados atual será guardada automaticamente como backup antes de ser substituída pelo ficheiro importado.")
        }
        .confirmationDialog(
            "Restaurar o backup?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restaurar", role: .destructive) {
                performRestore()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("A base de dados ativa e o backup vão trocar imediatamente de lugar.")
        }
        .alert(
            "Erro",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func exportActive() {
        do {
            activeExportURL = try store.exportActiveSnapshotURL()
            showActiveMover = true
            AppAnalytics.log(.databaseExported)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportBackup() {
        do {
            backupExportURL = try store.exportBackupSnapshotURL()
            showBackupMover = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performImport() {
        guard let url = pendingImportURL else { return }
        do {
            try store.importDatabase(from: url)
            AppAnalytics.log(.databaseImported)
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingImportURL = nil
    }

    private func performRestore() {
        do {
            try store.restoreBackup()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        DataManagementView()
    }
    .environment(DataStore())
}
