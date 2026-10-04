import Foundation
import Observation
import Security

/// Where the platform's Supabase lives: the `Api` project, locally (`supabase start`) or on the
/// VPS. Read from `Supabase-Debug.plist` / `Supabase-Release.plist` in the app bundle (git-ignored;
/// template in `Config/Supabase.example.plist`), so the app still builds and runs without it —
/// sync then simply reports itself unavailable.
///
/// Both values are public by design (the publishable key only identifies the project; Row Level
/// Security decides what a session may do). The secret key must never be put here.
struct SupabaseConfig {
    let url: URL
    let publishableKey: String

    static let current: SupabaseConfig? = {
        #if DEBUG
        let name = "Supabase-Debug"
        #else
        let name = "Supabase-Release"
        #endif
        guard let fileURL = Bundle.main.url(forResource: name, withExtension: "plist"),
              let values = NSDictionary(contentsOf: fileURL) as? [String: Any],
              let urlString = values["URL"] as? String, let url = URL(string: urlString), url.host() != nil,
              let key = values["PublishableKey"] as? String, !key.isEmpty else { return nil }
        return SupabaseConfig(url: url, publishableKey: key)
    }()
}

enum SupabaseError: LocalizedError {
    case notConfigured
    case notSignedIn
    case notAthlete
    /// An error answered by Supabase: HTTP status, Postgres/Auth error code (if any) and message.
    case server(status: Int, code: String?, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "A ligação à plataforma ainda não está configurada nesta app (falta o Supabase-Debug.plist / Supabase-Release.plist)."
        case .notSignedIn:
            return "Inicia sessão com a tua conta da plataforma para sincronizar."
        case .notAthlete:
            return "Esta conta não tem o papel de atleta na plataforma, por isso não pode enviar dados. Atribui-lhe role = 'athlete' na tabela profiles."
        case .server(let status, _, let message):
            return status == 0 ? message : "Erro do servidor (\(status)): \(message)"
        case .invalidResponse:
            return "Resposta inesperada do servidor."
        }
    }

    var code: String? {
        if case .server(_, let code, _) = self { return code }
        return nil
    }
}

/// The signed-in platform user, kept in the Keychain across launches.
struct SupabaseSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?
}

/// A minimal Supabase client over plain `URLSession`: email/password sign-in (Auth), PostgREST
/// table requests and RPCs, with the access token refreshed automatically. Every request runs with
/// the athlete's own session, so the database's RLS applies exactly as it does on the dashboard.
@Observable
final class SupabaseClient {
    let config: SupabaseConfig?
    private(set) var session: SupabaseSession?

    private var refreshTask: Task<SupabaseSession, Error>?
    private let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.waitsForConnectivity = false
        // Every answer must be live data: without this, GETs whose response has no Cache-Control
        // (Edge Functions) are served from the heuristic HTTP cache and look stale.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    init(config: SupabaseConfig? = .current) {
        self.config = config
        session = Keychain.read(Self.keychainAccount).flatMap { try? Self.jsonDecoder.decode(SupabaseSession.self, from: $0) }
    }

    var isConfigured: Bool { config != nil }
    var isSignedIn: Bool { session != nil }

    // MARK: Auth

    /// Signs in with the platform account (the same email/password as on the dashboard) and
    /// checks it is the athlete's — the only role the database lets write metrics.
    func signIn(email: String, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let data = try await send("POST", "/auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")],
                                  body: body, authorized: false)
        let newSession = try Self.session(fromTokenResponse: data)
        store(newSession)

        let canWrite = try await rpc("can_write_metrics", params: [String: String]())
        if String(data: canWrite, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) != "true" {
            await signOut()
            throw SupabaseError.notAthlete
        }
    }

    /// Ends the session on the server (best effort) and forgets it locally.
    func signOut() async {
        if session != nil {
            _ = try? await send("POST", "/auth/v1/logout", query: [URLQueryItem(name: "scope", value: "local")])
        }
        store(nil)
    }

    /// A valid access token, refreshing the session when it's about to expire. Concurrent callers
    /// share the same refresh.
    private func accessToken() async throws -> String {
        guard let current = session else { throw SupabaseError.notSignedIn }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }

        if let refreshTask { return try await refreshTask.value.accessToken }
        let task = Task { () throws -> SupabaseSession in
            let body = try JSONSerialization.data(withJSONObject: ["refresh_token": current.refreshToken])
            let data = try await self.send("POST", "/auth/v1/token",
                                           query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                           body: body, authorized: false)
            return try Self.session(fromTokenResponse: data)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let refreshed = try await task.value
            store(refreshed)
            return refreshed.accessToken
        } catch SupabaseError.server(let status, let code, let message) where (400...401).contains(status) {
            // The refresh token was revoked or already used: the user has to sign in again.
            store(nil)
            throw SupabaseError.server(status: status, code: code, message: "A sessão expirou — inicia sessão outra vez. (\(message))")
        }
    }

    private func store(_ newSession: SupabaseSession?) {
        session = newSession
        if let newSession, let data = try? Self.jsonEncoder.encode(newSession) {
            Keychain.write(data, account: Self.keychainAccount)
        } else {
            Keychain.delete(account: Self.keychainAccount)
        }
    }

    private static func session(fromTokenResponse data: Data) throws -> SupabaseSession {
        struct TokenResponse: Decodable {
            struct User: Decodable { let id: String; let email: String? }
            let accessToken: String
            let refreshToken: String
            let expiresIn: Double
            let user: User
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(TokenResponse.self, from: data) else { throw SupabaseError.invalidResponse }
        return SupabaseSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(response.expiresIn),
            userID: response.user.id,
            email: response.user.email
        )
    }

    // MARK: Data API (PostgREST)

    /// Inserts `rows`, updating the ones whose `onConflict` columns already exist (upsert).
    func upsert(_ table: String, rows: [[String: Any]], onConflict: String, ignoreDuplicates: Bool = false) async throws {
        guard !rows.isEmpty else { return }
        let body = try JSONSerialization.data(withJSONObject: rows)
        let resolution = ignoreDuplicates ? "ignore-duplicates" : "merge-duplicates"
        _ = try await send("POST", "/rest/v1/\(table)", query: [URLQueryItem(name: "on_conflict", value: onConflict)],
                           body: body, headers: ["Prefer": "resolution=\(resolution),return=minimal"])
    }

    /// Updates the rows matching `filters` (PostgREST syntax, e.g. `["id": "in.(…)"]`) with `values`.
    func update(_ table: String, filters: [String: String], values: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: values)
        _ = try await send("PATCH", "/rest/v1/\(table)", query: filters.map { URLQueryItem(name: $0.key, value: $0.value) },
                           body: body, headers: ["Prefer": "return=minimal"])
    }

    /// Reads rows of `table` (`select` and filters in PostgREST syntax), following pages so tables
    /// larger than the server's row limit (1000) come back whole — or at most `limit` rows.
    func select<T: Decodable>(_ table: String, as type: T.Type, select: String, filters: [String: String] = [:],
                              order: String, limit: Int? = nil) async throws -> [T] {
        try await pages(table, select: select, filters: filters, order: order, limit: limit)
            .flatMap { try Self.jsonDecoder.decode([T].self, from: $0) }
    }

    /// Like `select`, as plain JSON objects (e.g. to decode a `jsonb` column into app models).
    func selectRows(_ table: String, select: String, filters: [String: String] = [:], order: String,
                    limit: Int? = nil) async throws -> [[String: Any]] {
        try await pages(table, select: select, filters: filters, order: order, limit: limit).flatMap { page in
            guard let rows = try JSONSerialization.jsonObject(with: page) as? [[String: Any]] else {
                throw SupabaseError.invalidResponse
            }
            return rows
        }
    }

    private func pages(_ table: String, select: String, filters: [String: String], order: String,
                       limit: Int?) async throws -> [Data] {
        let pageSize = min(limit ?? 1000, 1000)
        var pages: [Data] = []
        var offset = 0
        while true {
            var query = filters.map { URLQueryItem(name: $0.key, value: $0.value) }
            query += [
                URLQueryItem(name: "select", value: select),
                URLQueryItem(name: "order", value: order),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            let data = try await send("GET", "/rest/v1/\(table)", query: query)
            pages.append(data)
            let count = (try JSONSerialization.jsonObject(with: data) as? [Any])?.count ?? 0
            offset += count
            if count < pageSize || (limit.map { offset >= $0 } ?? false) { return pages }
        }
    }

    /// Calls a database function (`/rest/v1/rpc/<name>`) and returns its raw JSON result.
    @discardableResult
    func rpc(_ name: String, params: some Encodable) async throws -> Data {
        try await send("POST", "/rest/v1/rpc/\(name)", body: Self.jsonEncoder.encode(params))
    }

    /// Calls a database function whose parameters need `JSONSerialization` (nested arrays/objects).
    @discardableResult
    func rpc(_ name: String, object: [String: Any]) async throws -> Data {
        try await send("POST", "/rest/v1/rpc/\(name)", body: JSONSerialization.data(withJSONObject: object))
    }

    /// Calls an Edge Function as the signed-in user (e.g. `invite-user`, which holds the secret
    /// key server-side so the app never needs it). Functions answer errors as `{ message }`.
    func callFunction(_ name: String, method: String, object: [String: Any]? = nil) async throws -> Data {
        try await send(method, "/functions/v1/\(name)", body: object.map { try JSONSerialization.data(withJSONObject: $0) })
    }

    // MARK: Storage

    /// Uploads a file to a (private) bucket, replacing whatever was at `path`.
    func uploadObject(_ bucket: String, path: String, data: Data, contentType: String) async throws {
        _ = try await send("POST", "/storage/v1/object/\(bucket)/\(path)", body: data,
                           headers: ["Content-Type": contentType, "x-upsert": "true"])
    }

    /// Downloads a file the signed-in user may read.
    func downloadObject(_ bucket: String, path: String) async throws -> Data {
        try await send("GET", "/storage/v1/object/authenticated/\(bucket)/\(path)", headers: ["Accept": "*/*"])
    }

    /// Deletes files from a bucket (paths that don't exist are ignored).
    func deleteObjects(_ bucket: String, paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        _ = try await send("DELETE", "/storage/v1/object/\(bucket)",
                           body: JSONSerialization.data(withJSONObject: ["prefixes": paths]))
    }

    // MARK: Transport

    private func send(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        headers: [String: String] = [:],
        authorized: Bool = true
    ) async throws -> Data {
        guard let config else { throw SupabaseError.notConfigured }
        var components = URLComponents(url: config.url.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        // `+` is literal in a query item but means a space to PostgREST (timestamps with offsets).
        let encodedQuery = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = encodedQuery
        guard let url = components?.url else { throw SupabaseError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized {
            let token = try await accessToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw SupabaseError.server(status: 0, code: nil, message: "Sem ligação ao servidor da plataforma (\(error.localizedDescription)).")
        }
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(status: http.statusCode, data: data)
        }
        return data
    }

    /// PostgREST answers `{code, message, details, hint}`; Auth answers `{error_code, msg}` or
    /// `{error, error_description}`.
    private static func error(status: Int, data: Data) -> SupabaseError {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = (json["code"] as? String) ?? (json["error_code"] as? String) ?? (json["error"] as? String)
        let message = (json["message"] as? String) ?? (json["msg"] as? String)
            ?? (json["error_description"] as? String) ?? String(data: data, encoding: .utf8) ?? ""
        return .server(status: status, code: code, message: message)
    }

    // MARK: Helpers

    private static let keychainAccount = "session"

    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // Pure helpers, usable off the main actor (decoders, background parsing). The formatters are
    // only configured once, then just read — safe to share although not marked Sendable.
    nonisolated(unsafe) private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let timestampFormatterNoFraction = ISO8601DateFormatter()

    /// A timestamp as Postgres `timestamptz` expects it.
    nonisolated static func timestamp(_ date: Date) -> String { timestampFormatter.string(from: date) }

    /// Parses a Postgres `timestamptz` (with or without fractional seconds).
    nonisolated static func date(fromTimestamp string: String) -> Date? {
        timestampFormatter.date(from: string) ?? timestampFormatterNoFraction.date(from: string)
    }
}

/// The session lives in the Keychain (not UserDefaults): it grants access to health data.
/// Readable after the first unlock so a background sync can still refresh it.
enum Keychain {
    private static let service = "CalorieBuddy.Supabase"

    private static func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String) -> Data? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func write(_ data: Data, account: String) {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if SecItemUpdate(query(account: account) as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query(account: account).merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    static func delete(account: String) {
        SecItemDelete(query(account: account) as CFDictionary)
    }
}
