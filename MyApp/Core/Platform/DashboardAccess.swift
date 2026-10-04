import Foundation

/// What someone invited to the dashboard may read — the platform's `access_grants` categories.
/// Enforced by the database (RLS `can_read`), not by the dashboard, so it holds for any client.
enum AccessCategory: String, CaseIterable, Identifiable, Codable {
    case nutrition, supplements, body, recovery, training
    /// Physical-progress photos: personal, so no role gets them by default.
    case progressPhotos = "progress_photos"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nutrition: return "Nutrição"
        case .supplements: return "Suplementos"
        case .body: return "Corpo"
        case .recovery: return "Recuperação"
        case .training: return "Treino"
        case .progressPhotos: return "Fotos de Evolução"
        }
    }

    var detail: String {
        switch self {
        case .nutrition: return "Diário alimentar, catálogo, planos e fotos das refeições"
        case .supplements: return "Fotos dos suplementos (as tomas quando chegarem à plataforma)"
        case .body: return "Peso, massa gorda, massa magra, cintura e água"
        case .recovery: return "Sono, frequência cardíaca em repouso e HRV"
        case .training: return "Treinos e calorias gastas"
        case .progressPhotos: return "As tuas fotos de evolução física — dados sensíveis"
        }
    }

    var symbolName: String {
        switch self {
        case .nutrition: return "fork.knife"
        case .supplements: return "pills.fill"
        case .body: return "figure"
        case .recovery: return "bed.double.fill"
        case .training: return "figure.run"
        case .progressPhotos: return "camera.fill"
        }
    }
}

/// The role of someone invited to the dashboard.
enum AccessRole: String, CaseIterable, Identifiable, Codable {
    case nutritionist, coach, viewer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nutritionist: return "Nutricionista"
        case .coach: return "Treinador"
        case .viewer: return "Só leitura"
        }
    }

    var detail: String {
        switch self {
        case .nutritionist: return "Vê as categorias escolhidas e pode criar e editar planos nutricionais."
        case .coach: return "Vê as categorias escolhidas."
        case .viewer: return "Vê as categorias escolhidas, sem papel profissional."
        }
    }

    /// Suggested categories when inviting someone with this role.
    var defaultCategories: Set<AccessCategory> {
        switch self {
        case .nutritionist: return [.nutrition, .supplements, .body]
        case .coach: return [.training, .recovery, .body]
        case .viewer: return []
        }
    }
}

/// Someone with (or invited to) access to the dashboard.
struct DashboardPerson: Identifiable, Equatable, Decodable {
    let id: String
    let email: String
    let role: AccessRole
    let categories: Set<AccessCategory>
    /// `invited` until they open the email and finish registering.
    let status: String
    let invitedAt: String?
    let lastSignInAt: String?

    var isPending: Bool { status != "registered" }

    private enum CodingKeys: String, CodingKey {
        case id, email, role, categories, status
        case invitedAt = "invited_at"
        case lastSignInAt = "last_sign_in_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        role = AccessRole(rawValue: try container.decode(String.self, forKey: .role)) ?? .viewer
        let raw = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
        categories = Set(raw.compactMap(AccessCategory.init(rawValue:)))
        status = try container.decode(String.self, forKey: .status)
        invitedAt = try container.decodeIfPresent(String.self, forKey: .invitedAt)
        lastSignInAt = try container.decodeIfPresent(String.self, forKey: .lastSignInAt)
    }
}

/// A shareable link that lets one person create a dashboard account with the access it carries.
/// It works once — creating the account spends it — and only until `expiresAt`.
struct AccessLink: Identifiable, Equatable, Decodable {
    enum Status: String, Decodable {
        case active, used, expired, revoked
    }

    let id: String
    let label: String?
    let role: AccessRole
    let categories: Set<AccessCategory>
    let createdAt: Date
    let expiresAt: Date
    let status: Status
    let usedAt: Date?
    /// Who created their account with it (nil once that account is revoked).
    let usedByEmail: String?

    private enum CodingKeys: String, CodingKey {
        case id, label, role, categories, status
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case usedAt = "used_at"
        case usedByEmail = "used_by_email"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func date(_ key: CodingKeys) throws -> Date? {
            try container.decodeIfPresent(String.self, forKey: key).flatMap(Self.date(fromPostgres:))
        }
        id = try container.decode(String.self, forKey: .id)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        role = AccessRole(rawValue: try container.decode(String.self, forKey: .role)) ?? .viewer
        let raw = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
        categories = Set(raw.compactMap(AccessCategory.init(rawValue:)))
        createdAt = try date(.createdAt) ?? .now
        expiresAt = try date(.expiresAt) ?? .now
        status = (try? container.decode(Status.self, forKey: .status)) ?? .expired
        usedAt = try date(.usedAt)
        usedByEmail = try container.decodeIfPresent(String.self, forKey: .usedByEmail)
    }

    /// Postgres timestamps can carry microseconds ("…:21.576124+00:00"); keep milliseconds, which
    /// the ISO-8601 parser reads.
    nonisolated static func date(fromPostgres string: String) -> Date? {
        let trimmed = string.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        return SupabaseClient.date(fromTimestamp: trimmed)
    }
}

/// How long a new access link stays valid.
enum AccessLinkValidity: Int, CaseIterable, Identifiable {
    case oneHour = 1, oneDay = 24, threeDays = 72, oneWeek = 168, thirtyDays = 720

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .oneHour: return "1 hora"
        case .oneDay: return "24 horas"
        case .threeDays: return "3 dias"
        case .oneWeek: return "7 dias"
        case .thirtyDays: return "30 dias"
        }
    }
}

/// Invites people to the dashboard and manages their access, through the platform's Edge
/// Functions `invite-user` (email invitations, people) and `access-links` (shareable links) — the
/// secret key they need never reaches the app. Only the athlete account may call them.
struct DashboardAccessService {
    let client: SupabaseClient

    nonisolated private static let function = "invite-user"
    private static let linksFunction = "access-links"

    func people() async throws -> [DashboardPerson] {
        struct Response: Decodable { let people: [DashboardPerson] }
        let data = try await call("GET")
        return try JSONDecoder().decode(Response.self, from: data).people
    }

    /// Sends the invitation email (or re-sends it, if the invitation is still pending).
    func invite(email: String, role: AccessRole, categories: Set<AccessCategory>) async throws {
        _ = try await call("POST", [
            "email": email, "role": role.rawValue, "categories": categories.map(\.rawValue)
        ])
    }

    func update(_ personID: String, role: AccessRole, categories: Set<AccessCategory>) async throws {
        _ = try await call("PATCH", [
            "id": personID, "role": role.rawValue, "categories": categories.map(\.rawValue)
        ])
    }

    /// Deletes the person's account: they lose access immediately.
    func revoke(_ personID: String) async throws {
        _ = try await call("DELETE", ["id": personID])
    }

    // MARK: Shareable links

    func links() async throws -> [AccessLink] {
        struct Response: Decodable { let links: [AccessLink] }
        let data = try await call("GET", function: Self.linksFunction)
        return try JSONDecoder().decode(Response.self, from: data).links
    }

    /// Creates a link. Its URL only exists in this answer (the platform stores just a hash of it).
    func createLink(role: AccessRole, categories: Set<AccessCategory>, validity: AccessLinkValidity,
                    label: String) async throws -> (url: URL, expiresAt: Date) {
        struct Response: Decodable { let url: URL; let expires_at: String }
        let data = try await call("POST", [
            "role": role.rawValue, "categories": categories.map(\.rawValue),
            "expires_in_hours": validity.rawValue, "label": label
        ], function: Self.linksFunction)
        let response = try JSONDecoder().decode(Response.self, from: data)
        return (response.url, AccessLink.date(fromPostgres: response.expires_at) ?? .now)
    }

    /// Cancels a link that hasn't been used yet.
    func revokeLink(_ linkID: String) async throws {
        _ = try await call("DELETE", ["id": linkID], function: Self.linksFunction)
    }

    private func call(_ method: String, _ object: [String: Any]? = nil,
                      function: String = DashboardAccessService.function) async throws -> Data {
        do {
            return try await client.callFunction(function, method: method, object: object)
        } catch SupabaseError.server(let status, _, let message) where Self.isFunctionMissing(status: status, message: message) {
            throw DashboardAccessError.functionNotDeployed
        }
    }

    /// The server doesn't have the function yet: self-hosted Edge Runtime answers 500 "could not find an
    /// appropriate entrypoint" (no folder for it); hosted Supabase answers 404.
    private static func isFunctionMissing(status: Int, message: String) -> Bool {
        status == 404 || message.contains("InvalidWorkerCreation") || message.contains("appropriate entrypoint")
    }
}

enum DashboardAccessError: LocalizedError {
    case functionNotDeployed

    var errorDescription: String? {
        "A gestão de acessos ainda não está instalada neste servidor da plataforma. Falta publicar a nova versão da API (migrações e funções invite-user / access-links)."
    }
}
