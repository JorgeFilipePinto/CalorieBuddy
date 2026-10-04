import SwiftUI

/// Quick-log sheet for a supplement: pick it (only supplements already in the library) and how
/// much via two dropdowns — a whole number of doses (1–10) plus an extra percentage of a dose.
/// "Registar" then asks which stock it came from (when it has any), and that stock — and so the
/// supplement's total — drops by what was taken.
///
/// `supplement` fixes the choice, e.g. after scanning its barcode.
struct SupplementPickerView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let date: Date
    /// Set when the supplement is already known (scanned): no picker, just the amount.
    let fixedSupplementID: UUID?

    @State private var selectedSupplementID: UUID?
    @State private var wholeDoses = 1
    @State private var percentage = 0

    @State private var showingStockChoice = false
    /// What the stock sheet chose; logged once the sheet is gone (an alert can't show over it).
    @State private var pendingStock: StockChoice?

    @State private var showingLowStockAlert = false
    @State private var lowStockSupplementName = ""

    private let percentageOptions = [0, 25, 50, 75]

    enum StockChoice: Equatable {
        case stock(UUID)
        case none
    }

    init(date: Date, supplement: Supplement? = nil) {
        self.date = date
        self.fixedSupplementID = supplement?.id
        _selectedSupplementID = State(initialValue: supplement?.id)
    }

    private var selectedSupplement: Supplement? {
        selectedSupplementID.flatMap { store.supplement(withID: $0) }
    }

    private var quantity: Double {
        Double(wholeDoses) + Double(percentage) / 100
    }

    var body: some View {
        NavigationStack {
            Form {
                if let fixedSupplement = fixedSupplementID.flatMap({ store.supplement(withID: $0) }) {
                    Section("Suplemento") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fixedSupplement.name)
                                .font(.headline)
                            Text(summary(of: fixedSupplement))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    UsageSuggestionsSection(
                        suggestions: { store.suggestedSupplements($0) },
                        title: { $0.name },
                        subtitle: { "dose \($0.doseLabel)" },
                        isSelected: { $0.id == selectedSupplementID },
                        select: { selectedSupplementID = $0.id }
                    )
                    Section("Suplemento") {
                        if store.supplements.isEmpty {
                            ContentUnavailableView(
                                "Sem Suplementos",
                                systemImage: "pills.fill",
                                description: Text("Adiciona suplementos no separador Alimentos.")
                            )
                        } else {
                            NavigationLink {
                                SupplementSearchList(selection: $selectedSupplementID)
                            } label: {
                                LabeledContent("Suplemento", value: selectedSupplement?.name ?? "Escolhe…")
                            }
                        }
                    }
                }

                if let selectedSupplement {
                    Section {
                        HStack {
                            Text("Doses")
                            Spacer()
                            Picker("Doses", selection: $wholeDoses) {
                                ForEach(1...10, id: \.self) { count in
                                    Text("\(count)").tag(count)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()

                            Text("+")
                                .foregroundStyle(.secondary)

                            Picker("Percentagem", selection: $percentage) {
                                ForEach(percentageOptions, id: \.self) { percent in
                                    Text("\(percent)%").tag(percent)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        Text(totalText(for: selectedSupplement))
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Quantidade")
                    } footer: {
                        if !selectedSupplement.stocks.isEmpty {
                            Text("A seguir escolhes de que stock saiu.")
                        }
                    }
                }
            }
            .navigationTitle("Suplemento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registar") { register() }
                        .disabled(selectedSupplement == nil)
                }
            }
            .sheet(isPresented: $showingStockChoice, onDismiss: logPendingChoice) {
                if let selectedSupplement {
                    StockChoiceView(supplement: selectedSupplement, quantity: quantity) { choice in
                        pendingStock = choice
                        showingStockChoice = false
                    }
                }
            }
            .alert("Stock Baixo", isPresented: $showingLowStockAlert) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text("O stock de \(lowStockSupplementName) está a acabar — talvez seja altura de comprar mais.")
            }
        }
    }

    /// With stock to draw from, asks which one first; without, logs straight away.
    private func register() {
        guard let selectedSupplement else { return }
        if selectedSupplement.stocks.isEmpty {
            log(stockID: nil)
        } else {
            pendingStock = nil
            showingStockChoice = true
        }
    }

    private func logPendingChoice() {
        guard let choice = pendingStock else { return }  // sheet closed without choosing
        pendingStock = nil
        switch choice {
        case .stock(let id): log(stockID: id)
        case .none: log(stockID: nil)
        }
    }

    private func log(stockID: UUID?) {
        guard let selectedSupplement else { return }
        let isLowStock = store.logSupplement(
            selectedSupplement,
            stockID: stockID,
            quantity: quantity,
            date: date
        )
        AppAnalytics.log(.entryLogged(source: .supplement, mealType: nil))
        if isLowStock {
            lowStockSupplementName = selectedSupplement.name
            showingLowStockAlert = true
        } else {
            dismiss()
        }
    }

    private func summary(of supplement: Supplement) -> String {
        var parts = ["dose \(supplement.doseLabel)"]
        if supplement.calories != nil { parts.append("\(supplement.scaledCalories(quantity: 1)) kcal") }
        if !supplement.stocks.isEmpty {
            parts.append("\(formatted(supplement.doses(in: supplement.totalRemaining))) doses em stock")
        }
        return parts.joined(separator: " · ")
    }

    private func totalText(for supplement: Supplement) -> String {
        var text = "Total: \(formatted(quantity)) \(quantity == 1 ? "dose" : "doses")"
        if supplement.calories != nil {
            text += " · \(supplement.scaledCalories(quantity: quantity)) kcal"
        }
        let macros = [
            supplement.scaledProtein(quantity: quantity).map { "P \(formatted($0))" },
            supplement.scaledCarbs(quantity: quantity).map { "H \(formatted($0))" },
            supplement.scaledFat(quantity: quantity).map { "G \(formatted($0))" },
        ].compactMap { $0 }
        if !macros.isEmpty { text += " · " + macros.joined(separator: " / ") + " g" }
        return text
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Which stock a dose came from: each location with what's left (and what will be left), or
/// none — the dose is logged without touching any stock.
private struct StockChoiceView: View {
    @Environment(DataStore.self) private var store

    let supplement: Supplement
    /// Doses being logged.
    let quantity: Double
    let choose: (SupplementPickerView.StockChoice) -> Void

    private var amount: Double { quantity * supplement.doseSize }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(supplement.stocks) { stock in
                        let locationName = store.stockLocation(withID: stock.locationID)?.name ?? "Local"
                        let enough = stock.remaining >= amount
                        Button {
                            choose(.stock(stock.id))
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(locationName)
                                        .foregroundStyle(.primary)
                                    Text("\(formatted(stock.remaining)) \(supplement.unit.shortLabel) → fica \(formatted(max(stock.remaining - amount, 0))) \(supplement.unit.shortLabel)")
                                        .font(.caption)
                                        .foregroundStyle(enough ? Color.secondary : Color.red)
                                }
                                Spacer()
                                Image(systemName: "shippingbox")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // Rows read as a list to pick from, not as red action buttons.
                        .tint(.primary)
                    }
                } header: {
                    Text("De que stock saiu?")
                } footer: {
                    Text("Total em stock: \(formatted(supplement.totalRemaining)) \(supplement.unit.shortLabel) (\(formatted(supplement.doses(in: supplement.totalRemaining))) doses). Esta toma retira \(formatted(amount)) \(supplement.unit.shortLabel).")
                }

                Section {
                    Button("Não descontar de nenhum stock") {
                        choose(.none)
                    }
                }
            }
            .navigationTitle(supplement.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .presentationDetents([.medium, .large])
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

#Preview {
    SupplementPickerView(date: .now)
        .environment(DataStore())
}

/// Searchable list of the supplements, grouped by their category (favourites first), with what's
/// left in stock — tapping one picks it and goes back.
struct SupplementSearchList: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: UUID?

    @State private var searchText = ""

    private var groups: [(id: String, title: String, items: [Supplement])] {
        let visible = store.supplements.filter { supplement in
            SearchMatch.matches(searchText, in: [supplement.name, store.supplementCategory(withID: supplement.categoryID)?.name ?? ""])
        }
        .filteredAndSorted(searchText: "", order: .name)
        var groups: [(id: String, title: String, items: [Supplement])] = []
        let favorites = visible.filter(\.isFavorite)
        if !favorites.isEmpty { groups.append(("favorites", "Favoritos", favorites)) }
        let others = visible.filter { !$0.isFavorite }
        for category in store.supplementCategories {
            let items = others.filter { $0.categoryID == category.id }
            if !items.isEmpty { groups.append((category.id.uuidString, category.name, items)) }
        }
        let known = Set(store.supplementCategories.map(\.id))
        let rest = others.filter { !known.contains($0.categoryID) }
        if !rest.isEmpty { groups.append(("none", "Outros", rest)) }
        return groups
    }

    var body: some View {
        List {
            if groups.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
            ForEach(groups, id: \.id) { group in
                Section("\(group.title) (\(group.items.count))") {
                    ForEach(group.items) { supplement in
                        Button {
                            selection = supplement.id
                            dismiss()
                        } label: {
                            HStack {
                                PhotoThumbnail(photoID: supplement.photoID, placeholder: "pills.fill")
                                VStack(alignment: .leading) {
                                    Text(supplement.name)
                                    Text("dose \(supplement.doseLabel) · \(RecipeIngredientEditorView.number(supplement.doses(in: supplement.totalRemaining))) doses em stock")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selection == supplement.id {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Suplemento")
        .searchable(text: $searchText, prompt: "Procurar suplemento ou categoria")
    }
}
