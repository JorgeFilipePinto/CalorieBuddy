import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(DataStore.self) private var store

    @State private var goalText: String = ""

    @State private var activeExportURL: URL?
    @State private var showActiveMover = false
    @State private var backupExportURL: URL?
    @State private var showBackupMover = false

    @State private var isImporting = false
    @State private var pendingImportURL: URL?
    @State private var showImportConfirmation = false
    @State private var showRestoreConfirmation = false

    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Objetivo Diário") {
                HStack {
                    Text("Calorias (kcal)")
                    Spacer()
                    TextField("2000", text: $goalText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .onChange(of: goalText) { _, newValue in
                            guard let value = Int(newValue) else { return }
                            var settings = store.settings
                            settings.dailyCalorieGoal = value
                            store.updateSettings(settings)
                        }
                }
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
                if let backupTimestamp = store.backupTimestamp {
                    Text("Último backup: \(backupTimestamp.formatted(date: .abbreviated, time: .shortened))")
                } else {
                    Text("Ainda não existe nenhum backup. É criado automaticamente sempre que importares uma base de dados.")
                }
            }
        }
        .navigationTitle("Definições")
        .onAppear { goalText = String(store.settings.dailyCalorieGoal) }
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
}
