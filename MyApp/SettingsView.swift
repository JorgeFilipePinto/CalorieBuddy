import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
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
                NavigationLink {
                    NutritionPlansListView()
                } label: {
                    Label("Planos Alimentares", systemImage: "target")
                }
            } footer: {
                Text("Define os objetivos diários de calorias, macros e água — com valores diferentes para dias de treino e de descanso, tal como no plano do nutricionista.")
            }

            Section {
                NavigationLink {
                    CloudBackupView()
                } label: {
                    Label("Nuvem e Estatísticas", systemImage: "icloud")
                }
            } footer: {
                Text("Backup automático da base de dados na Firebase e estatísticas de uso.")
            }

            Section {
                NavigationLink {
                    StoresListView()
                } label: {
                    Label("Lojas", systemImage: "storefront")
                }
            } footer: {
                Text("Cria, edita ou elimina as lojas onde registas preços dos alimentos.")
            }

            Section {
                Button {
                    exportActive()
                } label: {
                    Label("Download da Base de Dados Ativa", systemImage: "square.and.arrow.down")
                }

                Button {
                    exportBackup()
                } label: {
                    Label("Download do Backup", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(!store.hasBackup)

                Button {
                    isImporting = true
                } label: {
                    Label("Upload / Importar Base de Dados", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    showRestoreConfirmation = true
                } label: {
                    Label("Restaurar Backup", systemImage: "arrow.uturn.backward")
                }
                .disabled(!store.hasBackup)
            } header: {
                Text("Gestão de Dados")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("O ficheiro inclui tudo: registos diários, catálogo de alimentos, receitas, plano alimentar, suplementos, categorias, stocks, lojas, preços e definições. Podes editá-lo ou acrescentar dados à mão antes de o importares de volta.")
                    if let backupTimestamp = store.backupTimestamp {
                        Text("Último backup: \(backupTimestamp.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text("Ainda não existe nenhum backup. É criado automaticamente sempre que importares uma base de dados.")
                    }
                }
            }

            Section {
                Button {
                    showingJSONEditor = true
                } label: {
                    Label("Ver / Editar JSON", systemImage: "curlybraces")
                }
            } header: {
                Text("Base de Dados (JSON)")
            } footer: {
                Text("Mostra o JSON completo da base de dados ativa, exatamente como seria exportado. Guardar altera os teus dados diretamente e cria um backup da versão anterior, tal como importar um ficheiro.")
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteAllConfirmation = true
                } label: {
                    Label("Eliminar Todos os Dados", systemImage: "trash.fill")
                }
            } header: {
                Text("Zona de Perigo")
            } footer: {
                Text("Elimina permanentemente tudo o que esta app tem guardado no telemóvel, incluindo o backup. Pede confirmação com pressão longa de 5 segundos.")
            }
        }
        .navigationTitle("Definições")
        .trackScreen("Definições")
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
        SettingsView()
    }
    .environment(DataStore())
    .environment(CloudBackupManager())
}
