import SwiftUI

/// "Recentes / Mais usados" shortlist at the top of a logging sheet: one tap picks the item.
/// Hidden while there's no history yet.
struct UsageSuggestionsSection<Item: Identifiable>: View {
    let suggestions: (UsageOrder) -> [Item]
    let title: (Item) -> String
    let subtitle: (Item) -> String
    let isSelected: (Item) -> Bool
    let select: (Item) -> Void

    @AppStorage("CalorieBuddy.usageOrder") private var order: UsageOrder = .recent

    var body: some View {
        let items = suggestions(order)
        if !suggestions(.recent).isEmpty {
            Section {
                Picker("Mostrar", selection: $order) {
                    ForEach(UsageOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                ForEach(items) { item in
                    Button {
                        select(item)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(item)).foregroundStyle(.primary)
                                Text(subtitle(item)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected(item) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Sugestões")
            }
        }
    }
}
