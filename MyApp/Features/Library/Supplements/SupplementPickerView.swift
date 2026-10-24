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
    /// Adds a "+" to create a supplement here (by hand or read from the label by an AI) when it isn't
    /// on the list yet — the new one is selected.
    let allowsCreating: Bool
    /// Set when it's taken for an activity: the log is linked to it (com suplementação).
    let workout: HealthKitManager.WorkoutSummary?
    /// How it was taken, in the athlete's words.
    @State private var notes = ""
    @State private var showingNewSupplement = false
    @State private var showingJSONImport = false

    @State private var selectedSupplementID: UUID?
    @State private var wholeDoses = 1
    @State private var percentage = 0

    /// The stock the intake comes out of (nil = none), suggested when a supplement is chosen and
    /// always changeable here.
    @State private var stockSelection: UUID?

    @State private var showingLowStockAlert = false
    @State private var lowStockSupplementName = ""

    private let percentageOptions = [0, 25, 50, 75]

    init(date: Date, supplement: Supplement? = nil, allowsCreating: Bool = false, workout: HealthKitManager.WorkoutSummary? = nil) {
        self.allowsCreating = allowsCreating
        self.workout = workout
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

                // Always there, not only once a supplement is chosen: how it was taken.
                Section {
                    TextField("Como foi tomado (opcional)", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Descrição")
                } footer: {
                    Text(workout == nil ? "Explica a abordagem: quando, com quê, porquê." : "Explica a abordagem neste treino: quando tomaste, com quê, porquê.")
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
                    }

                    if !selectedSupplement.stocks.isEmpty {
                        SupplementStockSection(supplement: selectedSupplement, quantity: quantity, selection: $stockSelection)
                    }
                }
            }
            .navigationTitle("Suplemento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                if allowsCreating {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { showingNewSupplement = true } label: {
                                Label("Novo Suplemento", systemImage: "square.and.pencil")
                            }
                            Button { showingJSONImport = true } label: {
                                Label("Novo com IA (foto ou texto)", systemImage: "sparkles")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registar") { register() }
                        .disabled(selectedSupplement == nil)
                }
            }
            .sheet(isPresented: $showingNewSupplement) { SupplementEditorView() }
            .sheet(isPresented: $showingJSONImport) {
                JSONImportSheet(
                    title: "Novo Suplemento com IA",
                    prompt: AIJSONImport.supplementPrompt(categories: store.supplementCategories.map(\.name)),
                    instructions: "Envia uma foto do rótulo (ou descreve o suplemento): a IA devolve a embalagem, a dose e os macros. Um suplemento com o mesmo nome de um já existente é mantido como está; o novo fica escolhido aqui."
                ) { json in
                    let payloads = try AIJSONImport.decodeSupplements(from: json)
                    guard !payloads.isEmpty else { throw AIImportError.empty }
                    for payload in payloads { store.catalogSupplement(for: payload) }
                }
            }
            // A supplement created here is the one to log.
            .onChange(of: store.supplements.count) { old, new in
                if allowsCreating, new > old, let created = store.supplements.last { selectedSupplementID = created.id }
            }
            // The stock suggested for the supplement: the last one used, else the fullest.
            .onChange(of: selectedSupplementID, initial: true) { _, _ in
                stockSelection = selectedSupplement.flatMap { store.preferredStockID(for: $0) }
            }
            .alert("Stock Baixo", isPresented: $showingLowStockAlert) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text("O stock de \(lowStockSupplementName) está a acabar — talvez seja altura de comprar mais.")
            }
        }
    }

    /// Logs the intake from the stock chosen above (or none).
    private func register() {
        log(stockID: stockSelection)
    }

    private func log(stockID: UUID?) {
        guard let selectedSupplement else { return }
        let isLowStock = store.logSupplement(
            selectedSupplement,
            stockID: stockID,
            quantity: quantity,
            date: date,
            notes: notes,
            workout: workout
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

/// The stocks of a supplement, to pick the one an intake comes out of (the suggested one is already
/// selected) or none: each with what is left and what will be left. `returning`: what the intake
/// being edited had already taken from `returningStock`, which counts as available again.
struct SupplementStockSection: View {
    @Environment(DataStore.self) private var store

    let supplement: Supplement
    /// Doses of this intake.
    let quantity: Double
    @Binding var selection: UUID?
    var returningStock: UUID?
    var returning: Double = 0

    private var amount: Double { quantity * supplement.doseSize }

    var body: some View {
        Section {
            ForEach(supplement.stocks) { stock in
                let locationName = store.stockLocation(withID: stock.locationID)?.name ?? "Local"
                let available = stock.remaining + (stock.id == returningStock ? returning * supplement.doseSize : 0)
                Button {
                    selection = stock.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(locationName).foregroundStyle(.primary)
                            Text("\(formatted(available)) \(supplement.unit.shortLabel) → fica \(formatted(max(available - amount, 0))) \(supplement.unit.shortLabel)")
                                .font(.caption)
                                .foregroundStyle(available >= amount ? Color.secondary : Color.red)
                        }
                        Spacer()
                        Image(systemName: selection == stock.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection == stock.id ? Color.accentColor : .secondary)
                    }
                }
                .tint(.primary)
            }
            Button {
                selection = nil
            } label: {
                HStack {
                    Text("Não descontar de nenhum stock").foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: selection == nil ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection == nil ? Color.accentColor : .secondary)
                }
            }
        } header: {
            Text("De que stock sai?")
        } footer: {
            Text("Esta toma retira \(formatted(amount)) \(supplement.unit.shortLabel). Se a mudares depois, o stock é reposto e descontado outra vez.")
        }
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
