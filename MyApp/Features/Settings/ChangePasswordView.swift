import SwiftUI

/// Changes the platform account's password (the same one used on the dashboard): the current
/// password, then the new one twice, checked against the platform's rules as it's typed.
struct ChangePasswordView: View {
    @Environment(PlatformSyncManager.self) private var platformSync
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didChange = false

    private var unmet: [String] { PasswordRules.unmet(new) }
    private var matches: Bool { !confirmation.isEmpty && new == confirmation }
    private var canSave: Bool { !current.isEmpty && unmet.isEmpty && matches && new != current && !isSaving }

    var body: some View {
        Form {
            Section {
                SecureField("Palavra-passe atual", text: $current)
                    .textContentType(.password)
            } footer: {
                Text("Para confirmar que és tu.")
            }

            Section {
                SecureField("Nova palavra-passe", text: $new)
                    .textContentType(.newPassword)
                SecureField("Repetir nova palavra-passe", text: $confirmation)
                    .textContentType(.newPassword)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(["Pelo menos \(PasswordRules.minimumLength) caracteres", "Uma letra minúscula", "Uma letra maiúscula", "Um algarismo"], id: \.self) { rule in
                        requirement(rule, isMet: !new.isEmpty && !unmet.contains(rule))
                    }
                    requirement("As duas palavras-passe são iguais", isMet: matches)
                    if !new.isEmpty, new == current {
                        Text("A nova palavra-passe tem de ser diferente da atual.")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text("Alterar Palavra-passe")
                        if isSaving {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!canSave)
            } footer: {
                Text("A nova palavra-passe passa a valer também no dashboard. Esta app continua com a sessão iniciada.")
            }
        }
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .navigationTitle("Palavra-passe")
        .trackScreen("Alterar Palavra-passe")
        .alert("Erro", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Palavra-passe Alterada", isPresented: $didChange) {
            Button("OK") { dismiss() }
        } message: {
            Text("Usa a nova palavra-passe da próxima vez que iniciares sessão, aqui ou no dashboard.")
        }
    }

    private func requirement(_ text: String, isMet: Bool) -> some View {
        Label(text, systemImage: isMet ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isMet ? .green : .secondary)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await platformSync.client.changePassword(current: current, new: new)
            current = ""
            new = ""
            confirmation = ""
            Haptics.success()
            didChange = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ChangePasswordView()
    }
    .environment(PlatformSyncManager())
}
