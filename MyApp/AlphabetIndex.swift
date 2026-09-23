import SwiftUI

extension String {
    /// The letter this string should be grouped/indexed under: the first character, uppercased
    /// and stripped of accents (so "Água" and "Aveia" both land under "A"), or "#" for anything
    /// that doesn't start with a letter.
    var alphabetIndexKey: String {
        guard let first = folding(options: .diacriticInsensitive, locale: .current).uppercased().first else {
            return "#"
        }
        return first.isLetter ? String(first) : "#"
    }
}

extension Array where Element: Favoritable {
    /// Splits an already name-sorted array into consecutive groups keyed by `alphabetIndexKey`,
    /// in alphabetical order ("#" last), ready to render as one `Section` per letter.
    var groupedAlphabetically: [(letter: String, items: [Element])] {
        let grouped = Dictionary(grouping: self) { $0.name.alphabetIndexKey }
        return grouped.keys
            .sorted { lhs, rhs in
                if lhs == "#" { return false }
                if rhs == "#" { return true }
                return lhs < rhs
            }
            .map { ($0, grouped[$0] ?? []) }
    }
}

/// A vertical A-Z (+ "#") strip, like the one in Contacts, that scrubs to the matching section
/// of a list as you drag along it. Letters with no matching section are dimmed but still
/// draggable — landing on one jumps to the nearest available letter instead of doing nothing.
struct AlphabetIndexScrollBar: View {
    let availableLetters: Set<String>
    let onSelect: (String) -> Void

    private static let letters: [String] = ["#"] + (UnicodeScalar("A").value...UnicodeScalar("Z").value)
        .map { String(Character(UnicodeScalar($0)!)) }

    @State private var lastSelectedLetter: String?

    var body: some View {
        GeometryReader { geometry in
            let rowHeight = geometry.size.height / CGFloat(Self.letters.count)
            VStack(spacing: 0) {
                ForEach(Self.letters, id: \.self) { letter in
                    Text(letter)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(availableLetters.contains(letter) ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let index = min(max(Int(value.location.y / rowHeight), 0), Self.letters.count - 1)
                        select(Self.letters[index])
                    }
            )
        }
        .frame(width: 20)
        .sensoryFeedback(.selection, trigger: lastSelectedLetter)
    }

    private func select(_ letter: String) {
        let target = availableLetters.contains(letter) ? letter : nearestAvailable(to: letter)
        guard let target, target != lastSelectedLetter else { return }
        lastSelectedLetter = target
        onSelect(target)
    }

    private func nearestAvailable(to letter: String) -> String? {
        guard let index = Self.letters.firstIndex(of: letter) else { return nil }
        for candidate in Self.letters[index...] where availableLetters.contains(candidate) { return candidate }
        for candidate in Self.letters[..<index].reversed() where availableLetters.contains(candidate) { return candidate }
        return nil
    }
}
