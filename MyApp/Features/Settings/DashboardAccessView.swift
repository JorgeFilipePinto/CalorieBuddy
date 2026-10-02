import SwiftUI

/// Definições → Acessos ao Dashboard: who can see the athlete's data on the platform dashboard,
/// with what role and which categories; invite, edit and revoke. Needs the athlete to be signed in
/// to the platform (Plataforma e Sincronização).
struct DashboardAccessView: View {
    @Environment(PlatformSyncManager.self) private var platformSync

    @State private var people: [DashboardPerson] = []
    @State private var links: [AccessLink] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingInvite = false
    @State private var showingLinkCreator = false
    @State private var personToEdit: DashboardPerson?
    @State private var linkToRevoke: AccessLink?

    private var service: DashboardAccessService { DashboardAccessService(client: platformSync.client) }

    var body: some View {
        List {
            if !platformSync.isAvailable || !platformSync.client.isSignedIn {
                ContentUnavailableView {
                    Label("Sem Sessão na Plataforma", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text("Inicia sessão com a tua conta de atleta para gerir quem tem acesso ao teu dashboard.")
                } actions: {
                    NavigationLink("Plataforma e Sincronização") { PlatformSyncView() }
                }
            } else {
                Section {
                    Button {
                        showingInvite = true
                    } label: {
                        SettingsRowLabel(title: "Convidar Pessoa", systemImage: "person.badge.plus", color: .blue)
                    }
                } footer: {
                    Text("A pessoa recebe um email com o link para criar a conta no dashboard. Só vê as categorias que escolheres — é a base de dados que o garante.")
                }

                Section {
                    Button {
                        showingLinkCreator = true
                    } label: {
                        SettingsRowLabel(title: "Criar Link de Acesso", systemImage: "link.badge.plus", color: .green)
                    }
                    ForEach(links) { link in
                        AccessLinkRow(link: link)
                            .swipeActions {
                                if link.status == .active {
                                    Button("Revogar", role: .destructive) { linkToRevoke = link }
                                }
                            }
                    }
                } header: {
                    Text("Links de Acesso")
                } footer: {
                    Text("Escolhes o que dá acesso e por quanto tempo, e partilhas o link como quiseres. Quem o abrir cria a conta no dashboard — e o link deixa logo de funcionar. Desliza para a esquerda num link ativo para o revogar.")
                }

                Section {
                    if people.isEmpty && !isLoading {
                        Text("Ainda ninguém tem acesso ao teu dashboard.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(people) { person in
                        Button {
                            personToEdit = person
                        } label: {
                            DashboardPersonRow(person: person)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Com Acesso")
                        if isLoading { ProgressView().controlSize(.small) }
                    }
                } footer: {
                    if !people.isEmpty {
                        Text("Toca numa pessoa para mudar o que vê ou revogar o acesso.")
                    }
                }
            }
        }
        .navigationTitle("Acessos ao Dashboard")
        .trackScreen("Acessos ao Dashboard")
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingInvite) {
            DashboardInviteView(service: service) { await load() }
        }
        .sheet(item: $personToEdit) { person in
            DashboardPersonEditorView(person: person, service: service) { await load() }
        }
        .sheet(isPresented: $showingLinkCreator) {
            AccessLinkCreatorView(service: service) { await load() }
        }
        .confirmationDialog(
            "Revogar este link?",
            isPresented: Binding(get: { linkToRevoke != nil }, set: { if !$0 { linkToRevoke = nil } }),
            titleVisibility: .visible,
            presenting: linkToRevoke
        ) { link in
            Button("Revogar Link", role: .destructive) { Task { await revokeLink(link) } }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Deixa de ser possível criar uma conta com ele.")
        }
        .alert("Erro", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        guard platformSync.isAvailable, platformSync.client.isSignedIn else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let loadedPeople = service.people()
            async let loadedLinks = service.links()
            (people, links) = try await (loadedPeople, loadedLinks)
        } catch {
            // Leaving the screen or a new pull-to-refresh cancels the request — not an error.
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func revokeLink(_ link: AccessLink) async {
        do {
            try await service.revokeLink(link.id)
            AppAnalytics.log(.dashboardAccessChanged(action: "revoke_link"))
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DashboardPersonRow: View {
    let person: DashboardPerson

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(person.email)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                badge(person.role.displayName, color: .blue)
                if person.isPending {
                    badge("Convite pendente", color: .orange)
                }
            }
            if person.categories.isEmpty {
                Text("Não vê nenhuma categoria")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    ForEach(AccessCategory.allCases.filter(person.categories.contains)) { category in
                        Label(category.displayName, systemImage: category.symbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel(AccessCategory.allCases.filter(person.categories.contains).map(\.displayName).joined(separator: ", "))
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Role picker and one toggle per category — shared by the invite and edit sheets.
private struct AccessFields: View {
    @Binding var role: AccessRole
    @Binding var categories: Set<AccessCategory>

    var body: some View {
        Section {
            Picker("Papel", selection: $role) {
                ForEach(AccessRole.allCases) { role in
                    Text(role.displayName).tag(role)
                }
            }
        } footer: {
            Text(role.detail)
        }

        Section {
            ForEach(AccessCategory.allCases) { category in
                Toggle(isOn: Binding(
                    get: { categories.contains(category) },
                    set: { isOn in
                        if isOn { categories.insert(category) } else { categories.remove(category) }
                    }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.displayName)
                            Text(category.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: category.symbolName)
                    }
                }
            }
        } header: {
            Text("O que pode ver")
        }
    }
}

private struct DashboardInviteView: View {
    @Environment(\.dismiss) private var dismiss
    let service: DashboardAccessService
    let onDone: () async -> Void

    @State private var email = ""
    @State private var role: AccessRole = .nutritionist
    @State private var categories = AccessRole.nutritionist.defaultCategories
    @State private var isSending = false
    @State private var errorMessage: String?

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { trimmedEmail.contains("@") && trimmedEmail.contains(".") }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("email@exemplo.com", text: $email)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("Email")
                }
                AccessFields(role: $role, categories: $categories)
            }
            .navigationTitle("Convidar Pessoa")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onChange(of: role) { categories = role.defaultCategories }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Enviar Convite") { Task { await send() } }
                            .disabled(!isValid)
                    }
                }
            }
            .alert("Erro", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            try await service.invite(email: trimmedEmail, role: role, categories: categories)
            AppAnalytics.log(.dashboardAccessChanged(action: "invite"))
            await onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DashboardPersonEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let person: DashboardPerson
    let service: DashboardAccessService
    let onDone: () async -> Void

    @State private var role: AccessRole
    @State private var categories: Set<AccessCategory>
    @State private var isWorking = false
    @State private var showingRevokeConfirmation = false
    @State private var errorMessage: String?
    @State private var resent = false

    init(person: DashboardPerson, service: DashboardAccessService, onDone: @escaping () async -> Void) {
        self.person = person
        self.service = service
        self.onDone = onDone
        _role = State(initialValue: person.role)
        _categories = State(initialValue: person.categories)
    }

    private var hasChanges: Bool { role != person.role || categories != person.categories }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Email", value: person.email)
                    LabeledContent("Estado", value: person.isPending ? "Convite pendente" : "Conta ativa")
                }

                AccessFields(role: $role, categories: $categories)

                if person.isPending {
                    Section {
                        Button {
                            Task { await resend() }
                        } label: {
                            SettingsRowLabel(title: resent ? "Convite Reenviado" : "Reenviar Convite",
                                             systemImage: resent ? "checkmark" : "envelope.arrow.triangle.branch",
                                             color: .orange)
                        }
                        .disabled(isWorking || resent)
                    } footer: {
                        Text("O link do convite expira ao fim de 1 hora.")
                    }
                }

                Section {
                    Button {
                        showingRevokeConfirmation = true
                    } label: {
                        SettingsRowLabel(title: "Revogar Acesso", systemImage: "person.badge.minus", color: .red, isDestructive: true)
                    }
                    .disabled(isWorking)
                } footer: {
                    Text("Apaga a conta desta pessoa na plataforma: deixa de conseguir entrar no dashboard de imediato. Para voltar a dar acesso, convida-a de novo.")
                }
            }
            .navigationTitle(person.email)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Guardar") { Task { await save() } }
                            .disabled(!hasChanges)
                    }
                }
            }
            .confirmationDialog(
                "Revogar o acesso de \(person.email)?",
                isPresented: $showingRevokeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Revogar Acesso", role: .destructive) { Task { await revoke() } }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("A conta é apagada e a pessoa deixa de ver o teu dashboard.")
            }
            .alert("Erro", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() async {
        await run(action: "update") {
            try await service.update(person.id, role: role, categories: categories)
        }
    }

    private func revoke() async {
        await run(action: "revoke") {
            try await service.revoke(person.id)
        }
    }

    private func resend() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.invite(email: person.email, role: role, categories: categories)
            resent = true
            await onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func run(action: String, _ work: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
            AppAnalytics.log(.dashboardAccessChanged(action: action))
            await onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Shareable links

private struct AccessLinkRow: View {
    let link: AccessLink

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(link.label?.isEmpty == false ? link.label! : link.role.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(statusTitle)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !link.categories.isEmpty {
                HStack(spacing: 10) {
                    ForEach(AccessCategory.allCases.filter(link.categories.contains)) { category in
                        Image(systemName: category.symbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel(AccessCategory.allCases.filter(link.categories.contains).map(\.displayName).joined(separator: ", "))
            }
        }
        .padding(.vertical, 2)
        .opacity(link.status == .active ? 1 : 0.6)
    }

    private var statusTitle: String {
        switch link.status {
        case .active: return "Ativo"
        case .used: return "Usado"
        case .expired: return "Expirado"
        case .revoked: return "Revogado"
        }
    }

    private var statusColor: Color {
        switch link.status {
        case .active: return .green
        case .used: return .blue
        case .expired: return .gray
        case .revoked: return .red
        }
    }

    private var detail: String {
        let role = link.role.displayName
        switch link.status {
        case .active:
            return "\(role) · válido até \(link.expiresAt.formatted(date: .abbreviated, time: .shortened))"
        case .used:
            let who = link.usedByEmail ?? "uma conta já revogada"
            let when = link.usedAt.map { " em \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""
            return "\(role) · usado por \(who)\(when)"
        case .expired:
            return "\(role) · expirou a \(link.expiresAt.formatted(date: .abbreviated, time: .shortened))"
        case .revoked:
            return "\(role) · revogado"
        }
    }
}

/// Creates a shareable link: what it gives access to and for how long, then shows the link once
/// (the platform only keeps a hash of it) to share or copy.
private struct AccessLinkCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    let service: DashboardAccessService
    let onDone: () async -> Void

    @State private var label = ""
    @State private var role: AccessRole = .nutritionist
    @State private var categories = AccessRole.nutritionist.defaultCategories
    @State private var validity: AccessLinkValidity = .oneWeek
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var created: (url: URL, expiresAt: Date)?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                if let created {
                    createdSections(created)
                } else {
                    Section {
                        TextField("Para quem é (opcional)", text: $label)
                    } header: {
                        Text("Etiqueta")
                    } footer: {
                        Text("Só para ti, para reconheceres o link na lista.")
                    }
                    AccessFields(role: $role, categories: $categories)
                    Section {
                        Picker("Válido durante", selection: $validity) {
                            ForEach(AccessLinkValidity.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                    } footer: {
                        Text("Depois disto o link deixa de funcionar, mesmo que ninguém o tenha usado. Também deixa de funcionar assim que alguém cria a conta com ele.")
                    }
                }
            }
            .navigationTitle(created == nil ? "Novo Link de Acesso" : "Link Criado")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onChange(of: role) { categories = role.defaultCategories }
            .toolbar {
                if created == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isCreating {
                            ProgressView()
                        } else {
                            Button("Criar Link") { Task { await create() } }
                        }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Concluído") { dismiss() }
                    }
                }
            }
            .alert("Erro", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(isCreating)
    }

    @ViewBuilder
    private func createdSections(_ created: (url: URL, expiresAt: Date)) -> some View {
        Section {
            Text(created.url.absoluteString)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
            ShareLink(item: created.url, message: Text("Acesso ao meu dashboard IronMan Project 2027")) {
                SettingsRowLabel(title: "Partilhar Link", systemImage: "square.and.arrow.up", color: .blue)
            }
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.url = created.url
                #endif
                copied = true
            } label: {
                SettingsRowLabel(title: copied ? "Link Copiado" : "Copiar Link",
                                 systemImage: copied ? "checkmark" : "doc.on.doc", color: .gray)
            }
        } footer: {
            Text("Válido até \(created.expiresAt.formatted(date: .abbreviated, time: .shortened)) e só para uma conta. Por segurança o link só é mostrado agora — se o perderes, revoga-o e cria outro.")
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        do {
            created = try await service.createLink(
                role: role, categories: categories, validity: validity,
                label: label.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            AppAnalytics.log(.dashboardAccessChanged(action: "create_link"))
            await onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
