import SwiftUI

/// The food stock and meal prep: what's expiring, the stock by location, registering what came
/// in (e.g. after shopping), meal-prep plans, and their settings (locations, cooking yields,
/// how early to warn about expiry dates).
struct PantryHubView: View {
    @Environment(DataStore.self) private var store

    @State private var showingEntry = false
    @State private var lotToEdit: PantryLot?

    private var expiring: [ExpiringLot] { store.expiringPantryLots() }

    private var stockedFoodCount: Int { Set(store.pantryLots.map(\.foodItemID)).count }

    var body: some View {
        List {
            if !expiring.isEmpty {
                Section {
                    ForEach(expiring) { item in
                        Button {
                            lotToEdit = item.lot
                        } label: {
                            ExpiringLotRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Label("Validade a Terminar", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } footer: {
                    Text("O que expira nos próximos \(store.expiryWarningDays) dias ou já expirou. Toca para corrigir a quantidade ou retirar do stock.")
                }
            }

            Section {
                Button {
                    showingEntry = true
                } label: {
                    Label("Registar Entrada", systemImage: "plus.circle.fill")
                }
                NavigationLink {
                    PantryStockView()
                } label: {
                    LabeledContent {
                        Text("\(stockedFoodCount)")
                    } label: {
                        Label("Stock de Alimentos", systemImage: "refrigerator")
                    }
                }
            } header: {
                Text("Stock")
            } footer: {
                Text("Depois das compras, regista o que entrou: quanto, em que local e até quando é válido. Cada alimento fica ligado ao catálogo.")
            }

            Section {
                NavigationLink {
                    MealPrepListView()
                } label: {
                    LabeledContent {
                        Text("\(store.mealPreps.filter { $0.cookedAt == nil }.count)")
                    } label: {
                        Label("Planeamento de Marmitas", systemImage: "takeoutbag.and.cup.and.straw")
                    }
                }
                NavigationLink {
                    WeekBoardView()
                } label: {
                    Label("Quadro Semanal", systemImage: "calendar.day.timeline.left")
                }
            } header: {
                Text("Marmitas")
            } footer: {
                Text("Escolhe receitas, quantas marmitas e quanto pesa cada uma já cozinhada: a app calcula o que pesar em cru, confirma o stock e faz a lista de compras. No Quadro Semanal pões receitas em cada refeição da semana e vês cada dia contra o teu plano.")
            }

            Section("Definições") {
                NavigationLink {
                    PantryLocationsView()
                } label: {
                    LabeledContent {
                        Text("\(store.pantryLocations.count)")
                    } label: {
                        Label("Locais de Stock", systemImage: "square.grid.2x2")
                    }
                }
                NavigationLink {
                    CookingYieldsView()
                } label: {
                    Label("Variação na Confeção", systemImage: "flame")
                }
                Stepper(value: Binding(
                    get: { store.expiryWarningDays },
                    set: { days in
                        var settings = store.settings
                        settings.expiryWarningDays = days
                        store.updateSettings(settings)
                    }
                ), in: 0...14) {
                    LabeledContent("Avisar validade", value: store.expiryWarningDays == 0
                        ? "no próprio dia"
                        : "\(store.expiryWarningDays) \(store.expiryWarningDays == 1 ? "dia" : "dias") antes")
                }
            }
        }
        .navigationTitle("Despensa")
        .trackScreen("Despensa")
        .onAppear { store.seedCookingYieldsIfEmpty() }
        .sheet(isPresented: $showingEntry) {
            PantryEntryView()
        }
        .sheet(item: $lotToEdit) { lot in
            NavigationStack {
                PantryLotEditorView(lot: lot)
            }
        }
    }
}

/// A lot with its expiry: food, where, how much, and when.
struct ExpiringLotRow: View {
    @Environment(DataStore.self) private var store
    let item: ExpiringLot

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.food.name)
                Text("\(store.pantryLocation(withID: item.lot.locationID)?.name ?? "—") · \(PantryFormat.amount(item.lot.remaining, unit: item.food.unit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.daysLeft < 0 ? .red : .orange)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        PantryHubView()
    }
    .environment(DataStore())
}
