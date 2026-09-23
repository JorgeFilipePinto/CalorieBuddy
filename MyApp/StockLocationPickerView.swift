import SwiftUI

/// Picks a stock location (e.g. "Casa", "Trabalho") from the shared, user-extensible list, with
/// a final "+" row to create a new one on the spot.
struct StockLocationPickerView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedLocationID: UUID?

    @State private var showingNewLocationAlert = false
    @State private var newLocationName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.stockLocations) { location in
                    Button {
                        selectedLocationID = location.id
                        dismiss()
                    } label: {
                        HStack {
                            Text(location.name)
                            Spacer()
                            if selectedLocationID == location.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    newLocationName = ""
                    showingNewLocationAlert = true
                } label: {
                    Label("Novo Local", systemImage: "plus")
                }
            }
            .navigationTitle("Local de Stock")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .alert("Novo Local", isPresented: $showingNewLocationAlert) {
                TextField("Nome (ex: Casa, Trabalho)", text: $newLocationName)
                Button("Cancelar", role: .cancel) {}
                Button("Criar") {
                    let trimmed = newLocationName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    let location = StockLocation(name: trimmed)
                    store.addStockLocation(location)
                    selectedLocationID = location.id
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    StockLocationPickerView(selectedLocationID: .constant(nil))
        .environment(DataStore())
}
