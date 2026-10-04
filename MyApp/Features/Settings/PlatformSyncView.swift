import SwiftUI

/// The platform account (signing in happens on `LoginView`), syncing, signing out — which syncs
/// first and then erases this iPhone's data — and the usage-statistics opt-out.
struct PlatformSyncView: View {
    @Environment(DataStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(PlatformSyncManager.self) private var platformSync

    @State private var analyticsEnabled = AppAnalytics.isEnabled
    @State private var showSignOutConfirmation = false
    @State private var signOutFailure: String?
    @State private var errorMessage: String?

    private var client: SupabaseClient { platformSync.client }

    var body: some View {
        Form {
            if !platformSync.isAvailable {
                Section {
                    ContentUnavailableView(
                        "Plataforma não configurada",
                        systemImage: "icloud.slash",
                        description: Text("Adiciona o ficheiro Supabase-Debug.plist (ou Supabase-Release.plist) com o URL e a publishable key da plataforma à pasta MyApp/Resources/Config e volta a compilar a app. Modelo em Config/Supabase.example.plist.")
                    )
                }
            } else if let session = client.session {
                Section {
                    LabeledContent("Conta", value: session.email ?? "—")
                    NavigationLink {
                        ChangePasswordView()
                    } label: {
                        Label("Alterar Palavra-passe", systemImage: "key")
                    }
                    Button("Terminar Sessão", role: .destructive) {
                        showSignOutConfirmation = true
                    }
                    .disabled(platformSync.isBusy)
                } header: {
                    Text("Plataforma IronMan Project")
                } footer: {
                    Text("Ligado a \(client.config?.url.host() ?? "—") como atleta. Ao terminar sessão, tudo é sincronizado e os dados deste iPhone são apagados — ficam na plataforma e voltam ao iniciar sessão.")
                }

                syncSection
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
        .confirmationDialog("Terminar sessão?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Terminar Sessão", role: .destructive) { Task { await signOut(discardingUnsynced: false) } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Primeiro é tudo enviado para a plataforma; depois os dados deste iPhone são apagados. Os dados da app Saúde não são afetados.")
        }
        .alert("Não foi possível sincronizar", isPresented: Binding(get: { signOutFailure != nil }, set: { if !$0 { signOutFailure = nil } })) {
            Button("Sair e Perder Alterações", role: .destructive) { Task { await signOut(discardingUnsynced: true) } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("\(signOutFailure ?? "")\n\nSe saíres mesmo assim, as alterações deste iPhone que ainda não chegaram à plataforma perdem-se.")
        }
        .alert("Erro", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var syncSection: some View {
        Section {
            Button {
                Task { await sync() }
            } label: {
                Label("Sincronizar Agora", systemImage: "arrow.triangle.2.circlepath")
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
                Text("A app sincroniza sozinha quando abres e quando sais dela, para o dashboard ter sempre os teus dados. O que mudares no dashboard chega aqui na sincronização seguinte.")
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

    private func sync() async {
        do {
            try await platformSync.sync(store: store, healthKit: healthKit)
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signOut(discardingUnsynced: Bool) async {
        do {
            try await platformSync.signOutErasingData(store: store, healthKit: healthKit, discardingUnsynced: discardingUnsynced)
            AppAnalytics.log(.platformSignOut)
        } catch {
            signOutFailure = error.localizedDescription
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
