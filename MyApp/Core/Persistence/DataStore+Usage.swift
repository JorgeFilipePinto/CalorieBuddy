import Foundation

/// Which shortlist to show when logging: what was logged last, or what's logged most.
enum UsageOrder: String, CaseIterable, Identifiable {
    case recent, frequent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recent: return "Recentes"
        case .frequent: return "Mais usados"
        }
    }
}

/// Shortlists for the logging sheets — the same things get logged again and again. Derived from
/// the history, since entries don't keep a link to the catalog: a food counts when it was logged
/// on its own under its catalog name; a recipe once per logging (its foods share a group); a
/// supplement once per intake.
extension DataStore {
    /// "Most used" looks at this window; "recent" at the whole history.
    static let frequentUsageDays = 90

    func suggestedFoodItems(_ order: UsageOrder, limit: Int = 6) -> [FoodItem] {
        let byName = Dictionary(foodItems.map { (Self.usageKey($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        let uses = entries.filter { $0.groupID == nil }.map { (key: Self.usageKey($0.name), date: $0.date) }
        return Self.rank(uses, order: order, limit: limit).compactMap { byName[$0] }
    }

    func suggestedRecipes(_ order: UsageOrder, limit: Int = 6) -> [Recipe] {
        let byName = Dictionary(recipes.map { (Self.usageKey($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        var loggings: [UUID: (key: String, date: Date)] = [:]
        for entry in entries {
            guard let group = entry.groupID, let name = entry.groupName else { continue }
            loggings[group] = (Self.usageKey(name), entry.date)
        }
        return Self.rank(Array(loggings.values), order: order, limit: limit).compactMap { byName[$0] }
    }

    func suggestedSupplements(_ order: UsageOrder, limit: Int = 6) -> [Supplement] {
        let byID = Dictionary(supplements.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        let uses = supplementLogs.map { (key: $0.supplementID.uuidString, date: $0.date) }
        return Self.rank(uses, order: order, limit: limit).compactMap { byID[$0] }
    }

    /// Keys ordered by their latest use (`recent`), or by how many uses in the window, ties to the
    /// most recent (`frequent`).
    private static func rank(_ uses: [(key: String, date: Date)], order: UsageOrder, limit: Int) -> [String] {
        var latest: [String: Date] = [:]
        var counts: [String: Int] = [:]
        let since = Calendar.current.date(byAdding: .day, value: -frequentUsageDays, to: .now) ?? .distantPast
        for use in uses {
            latest[use.key] = max(latest[use.key] ?? .distantPast, use.date)
            if use.date >= since { counts[use.key, default: 0] += 1 }
        }
        let keys: [String]
        switch order {
        case .recent:
            keys = latest.keys.sorted { latest[$0]! > latest[$1]! }
        case .frequent:
            keys = counts.keys.sorted { (counts[$0]!, latest[$0]!) > (counts[$1]!, latest[$1]!) }
        }
        return Array(keys.prefix(limit))
    }

    private static func usageKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
