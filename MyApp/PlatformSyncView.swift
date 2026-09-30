import SwiftUI

/// Sign-in to the IronMan Project platform, sync/restore, and the usage-statistics opt-out.
struct PlatformSyncView: View {
    @Environment(DataStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(PlatformSyncManager.self) private var platformSync

    @State private var email = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var analyticsEnabled = AppAnalytics.isEnabled
    @State private var showRestoreConfirmation = false
    @State private var showServerBackupChoice = false
    @State private var showReplaceConfirmation = false
    @State private var errorMessage: String?

    private var client: SupabaseClient { platformSync.client }

    var body: some View {
        @Bindable var platformSync = platformSync
        Form {
            if !platformSync.isAvailable {
                Section {
                    ContentUnavailableView(
                        "Plataforma não configurada",
                        systemImage: "icloud.slash",
                        description: Text("Adiciona o ficheiro Supabase-Debug.plist (ou Supabase-Release.plist) com o URL e a publishable key da plataforma à pasta MyApp e volta a compilar a app. Modelo em Config/Supabase.example.plist.")
                    )
                }
            } else if let session = client.session {
                Section {
                    LabeledContent("Conta", value: session.email ?? "—")
                    Button("Terminar Sessão", role: .destructive) {
                        Task { await client.signOut() }
                    }
                } header: {
                    Text("Plataforma IronMan Project")
                } footer: {
                    Text("Ligado a \(client.config?.url.host() ?? "—") como atleta.")
                }

                syncSection
            } else {
                signInSection
            }

            Section {
                Toggle("Partilhar estatísticas de uso", isOn: $analyticsEnabled)
                    .onChange(of: analyticsEnabled) { _, newValue in
                        AppAnalytics.isEnabled = newValue
                    }
            } header: {
                Text("Estatísticas")
            } footer: {
                Text("Envia para a plataforma apenas que ações usas (ex.: registaste uma receita ao almoço) — nunca calorias, peso ou dados da app Saúde.")
            }
        }
        .navigationTitle("Plataforma")
        .trackScreen("Plataforma")
        .confirmationDialog("Restaurar da plataforma?", isPresented: $showRestoreConfirmation, titleVisibility: .visible) {
            Button("Restaurar", role: .destructive) { Task { await restore() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("A base de dados atual é substituída pelo backup da plataforma e fica guardada como backup local. Os dados da app Saúde não são afetados.")
        }
        .confirmationDialog("Já existe um backup na plataforma", isPresented: $showServerBackupChoice, titleVisibility: .visible) {
            Button("Restaurar da Plataforma") { Task { await restore() } }
            Button("Substituir pelos Dados deste iPhone", role: .destructive) { showReplaceConfirmation = true }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Este iPhone ainda não sincronizou, mas a plataforma já tem um backup desta app (de outro iPhone ou de uma instalação anterior).")
        }
        .alert("Substituir o backup da plataforma?", isPresented: $showReplaceConfirmation) {
            Button("Substituir", role: .destructive) { Task { await sync(replacingServerBackup: true) } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Os registos que estão na plataforma e não existem neste iPhone são apagados de lá (ficam marcados como apagados).")
        }
        .alert("Erro", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var signInSection: some View {
        Section {
            TextField("Email", text: $email)
                .textContentType(.username)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
            SecureField("Palavra-passe", text: $password)
                .textContentType(.password)
            Button {
                Task { await signIn() }
            } label: {
                HStack {
                    Text("Iniciar Sessão")
                    if isSigningIn {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(email.isEmpty || password.isEmpty || isSigningIn)
        } header: {
            Text("Plataforma IronMan Project")
        } footer: {
            Text("Usa a tua conta de atleta da plataforma (a mesma do dashboard). Depois, o diário, o catálogo, os planos alimentares e os dados da app Saúde passam a ser sincronizados com o dashboard da nutricionista e do treinador.")
        }
    }

    private var syncSection: some View {
        @Bindable var platformSync = platformSync
        return Section {
            Toggle("Sincronização automática", isOn: $platformSync.autoSyncEnabled)
            Button {
                Task { await sync() }
            } label: {
                Label("Sincronizar Agora", systemImage: "arrow.triangle.2.circlepath")
            }
            Button(role: .destructive) {
                showRestoreConfirmation = true
            } label: {
                Label("Restaurar da Plataforma", systemImage: "icloud.and.arrow.down")
            }
        } header: {
            HStack {
                Text("Sincronização")
                if platformSync.isBusy {
                    Spacer()
                    ProgressView()
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Com a sincronização automática, as alterações são enviadas quando abres e quando sais da app. Os planos alimentares editados no dashboard chegam aqui na sincronização seguinte.")
                if let lastSync = platformSync.lastSync {
                    Text("Última sincronização: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                } else {
                    Text("Ainda não sincronizaste este iPhone.")
                }
                if let summary = platformSync.lastSummary {
                    Text(summary)
                }
                ForEach(platformSync.warnings, id: \.self) { warning in
                    Text(warning).foregroundStyle(.orange)
                }
                if let error = platformSync.lastError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .disabled(platformSync.isBusy)
    }

    private func signIn() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await client.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            password = ""
            await sync()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sync(replacingServerBackup: Bool = false) async {
        do {
            try await platformSync.sync(store: store, healthKit: healthKit, replacingServerBackup: replacingServerBackup)
            Haptics.success()
        } catch PlatformSyncError.serverHasBackup {
            showServerBackupChoice = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        do {
            try await platformSync.restore(into: store)
            // Sends anything the backup didn't have yet (Apple Health, pending events).
            await sync()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        PlatformSyncView()
    }
    .environment(DataStore())
    .environment(HealthKitManager())
    .environment(PlatformSyncManager())
}
