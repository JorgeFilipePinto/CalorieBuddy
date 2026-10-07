import Foundation

/// The app's search: every word typed must appear somewhere in the item's fields, ignoring case
/// and accents — "acucar mascavado" finds "Açúcar Mascavado", "frango peito" finds "Peito de Frango".
nonisolated enum SearchMatch {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    static func matches(_ query: String, in fields: [String]) -> Bool {
        let terms = normalized(query).split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }
        let haystack = normalized(fields.joined(separator: " "))
        return terms.allSatisfy { haystack.contains($0) }
    }
}
