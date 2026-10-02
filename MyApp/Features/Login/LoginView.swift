import SwiftUI

/// Shown instead of the app while there's no platform session: the athlete signs in with the
/// platform account (the same as the dashboard), and everything is downloaded from the platform
/// before the app opens. Only shown when a platform is configured (Supabase plist present).
struct LoginView: View {
    @Environment(DataStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(PlatformSyncManager.self) private var platformSync

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !platformSync.isLoadingAccount
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text("IRONMAN PROJECT")
                        .font(.system(size: 32, weight: .black, design: .default))
                        .tracking(1)
                    Text("2027")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.top, 60)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Iniciar Sessão")
                        .font(.title2.weight(.bold))
                    Text("Usa a tua conta de atleta da plataforma (a mesma do dashboard). Os teus dados são descarregados da plataforma — diário, alimentos, receitas, suplementos, planos, medidas e fotos.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .padding(12)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    SecureField("Palavra-passe", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { if canSubmit { Task { await signIn() } } }
                        .padding(12)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            if platformSync.isLoadingAccount {
                                ProgressView().tint(.white)
                                Text("A descarregar os teus dados…")
                            } else {
                                Text("Entrar")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                }
                .padding(20)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)

                Text("Sem conta? O acesso à plataforma é por convite.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.black.ignoresSafeArea())
        .trackScreen("Login")
    }

    private func signIn() async {
        errorMessage = nil
        focusedField = nil
        do {
            try await platformSync.signIn(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                store: store,
                healthKit: healthKit
            )
            password = ""
            AppAnalytics.log(.platformSignIn)
            Haptics.success()
        } catch SupabaseError.notAthlete {
            errorMessage = "Esta app é só para a conta de atleta. Usa o dashboard para ver os dados."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    LoginView()
        .environment(DataStore())
        .environment(HealthKitManager())
        .environment(PlatformSyncManager())
}
