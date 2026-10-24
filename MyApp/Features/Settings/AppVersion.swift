import Foundation

/// What build is running, for Settings → Versão: the release version (the tag's number), the build
/// number, which environment it was built for and the platform host it talks to.
enum AppVersion {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// "1.2.0 (1)".
    static var versionAndBuild: String { "\(version) (\(build))" }

    static var environment: String {
        #if STAGING
        return "Testes (staging)"
        #elseif DEBUG
        return "Desenvolvimento"
        #else
        return "Produção"
        #endif
    }

    static var platformHost: String? { SupabaseConfig.current?.url.host() }
}
