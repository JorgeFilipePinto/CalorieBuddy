import SwiftUI

/// Manage the stores used to price catalog items — add, rename, or delete them. Reachable from
/// both Definições and Alimentos, since either is a reasonable place to look for it.
struct StoresListView: View {
    @Environment(DataStore.self) private var store

    @State private var showingAddStore = false
    @State private var storeToEdit: Store?

    private var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }

    var body: some View {
        List {
            if store.stores.isEmpty {
                ContentUnavailableView(
                    "Sem Lojas",
                    systemImage: "storefront",
                    description: Text("Adiciona uma loja para começares a registar preços dos alimentos.")
                )
            } else {
                ForEach(store.stores) { existingStore in
                    Button {
                        storeToEdit = existingStore
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(existingStore.name)
                                Text(subtitle(for: existingStore))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets { store.deleteStore(store.stores[index]) }
                }
            }
        }
        .navigationTitle("Lojas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddStore = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddStore) {
            StoreEditorView()
        }
        .sheet(item: $storeToEdit) { existingStore in
            StoreEditorView(storeToEdit: existingStore)
        }
    }

    private func subtitle(for existingStore: Store) -> String {
        let pricedItems = store.foodItems.filter { item in item.prices.contains { $0.storeID == existingStore.id } }
        guard !pricedItems.isEmpty else { return "Sem alimentos com preço." }
        let total = pricedItems.reduce(0.0) { partial, item in
            partial + (item.prices.first { $0.storeID == existingStore.id }?.price ?? 0)
        }
        return "\(pricedItems.count) alimentos · \(total.formatted(.currency(code: currencyCode)))"
    }
}

#Preview {
    NavigationStack {
        StoresListView()
    }
    .environment(DataStore())
}
