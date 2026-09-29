import SwiftUI

/// Automatic/manual cloud backup of the database to Firestore and restore, plus the analytics
/// opt-out. No login: the app has a single user (see `CloudBackupManager`).
struct CloudBackupView: View {
    @Environment(DataStore.self) private var store
    @Environment(CloudBackupManager.self) private var cloudBackup

    @State private var analyticsEnabled = AppAnalytics.isEnabled
    @State private var showRestoreConfirmation = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var cloudBackup = cloudBackup
        Form {
            if !cloudBackup.isAvailable {
                Section {
                    ContentUnavailableView(
                        "Firebase não configurada",
                        systemImage: "icloud.slash",
                        description: Text("Adiciona o ficheiro GoogleService-Info.plist do teu projeto Firebase à pasta MyApp e volta a compilar a app.")
                    )
                }
            } else {
                Section {
                    Toggle("Backup automático", isOn: $cloudBackup.autoBackupEnabled)
                    Button {
                        Task { await backUp() }
                    } label: {
                        Label("Fazer Backup Agora", systemImage: "icloud.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showRestoreConfirmation = true
                    } label: {
                        Label("Restaurar da Nuvem", systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(cloudBackup.lastCloudBackup == nil)
                } header: {
                    HStack {
                        Text("Backup na Nuvem")
                        if cloudBackup.isBusy {
                            Spacer()
                            ProgressView()
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Guarda toda a base de dados (registos, catálogo, receitas, plano alimentar, suplementos e definições) no Firestore, em documentos legíveis na consola Firebase. Com o backup automático, as alterações são enviadas sempre que sais da app. Os dados da app Saúde não são enviados.")
                        if let lastCloudBackup = cloudBackup.lastCloudBackup {
                            Text("Último backup na nuvem: \(lastCloudBackup.formatted(date: .abbreviated, time: .shortened))")
                        } else {
                            Text("Ainda não existe nenhum backup na nuvem.")
                        }
                    }
                }
                .disabled(cloudBackup.isBusy)
            }

            Section {
                Toggle("Partilhar estatísticas de uso", isOn: $analyticsEnabled)
                    .onChange(of: analyticsEnabled) { _, newValue in
                        AppAnalytics.isEnabled = newValue
                    }
                    .disabled(!cloudBackup.isAvailable)
            } header: {
                Text("Estatísticas (Firebase Analytics)")
            } footer: {
                Text("Envia apenas que ações usas (ex.: registaste uma receita ao almoço) para os gráficos da consola Firebase — nunca calorias, peso ou dados da app Saúde.")
            }
        }
        .navigationTitle("Nuvem e Estatísticas")
        .trackScreen("Nuvem e Estatísticas")
        .task { await cloudBackup.refreshLastBackupDate() }
        .confirmationDialog(
            "Restaurar o backup da nuvem?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restaurar", role: .destructive) {
                Task { await restore() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("A base de dados deste iPhone é substituída pela da nuvem. A atual fica guardada como backup local.")
        }
        .alert(
            "Nuvem",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .alert(
            "Erro",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func backUp() async {
        do {
            try await cloudBackup.backUp(store)
            message = "Backup enviado para a nuvem."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        do {
            try await cloudBackup.restore(into: store)
            message = "Base de dados restaurada a partir da nuvem."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        CloudBackupView()
    }
    .environment(DataStore())
    .environment(CloudBackupManager())
}
