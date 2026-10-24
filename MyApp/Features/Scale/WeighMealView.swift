import SwiftUI

/// "Pesar Comida": builds a meal on the kitchen scale. The plate and each food are added in turn;
/// the pile shows on the right, the gauge and the nutrition table follow the food being weighed.
struct WeighMealView: View {
    @Environment(DataStore.self) private var store
    @Environment(KitchenScaleManager.self) private var scale
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @State private var session = WeighSession()
    @State private var showingPicker = false
    @State private var showingLog = false
    @State private var resets = 0
    /// A liquid chosen without a density: the alert asks whether to edit it or use the default.
    @State private var foodMissingDensity: FoodItem?
    @State private var foodToEdit: FoodItem?

    private var gross: Int { scale.grossGrams }
    private var pending: Int { session.pending(gross: gross) }
    private var currentFood: FoodItem? {
        session.currentFoodID.flatMap { id in store.foodItems.first { $0.id == id } }
    }
    /// Weight added and no food chosen for it.
    private var needsFood: Bool { currentFood == nil && pending > 2 }
    private var hasFoods: Bool { !session.items(foods: store.foodItems, gross: gross).isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            KitchenScaleStatusRow()
                                .padding(.horizontal)
                            WeightGauge(net: scale.grams ?? 0, tare: scale.tareGrams,
                                        isLive: scale.isConnected && scale.reading != nil, needsFood: needsFood)
                                .padding(.horizontal, 8)
                            foodChip
                            nutritionTable
                        }
                        .padding(.vertical)
                    }
                    Divider()
                    pileColumn
                        .frame(width: 96)
                }
                Divider()
                buttonBar
            }
            .navigationTitle("Pesar Comida")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .onAppear { if scale.state == .idle { scale.connect() } }
            .onChange(of: gross) { _, value in session.follow(gross: value) }
            .sheet(isPresented: $showingPicker) {
                WeighFoodPickerSheet { id in choose(id) }
            }
            .sheet(item: $foodToEdit) { food in
                // Saving rewrites the food in the store, so the table and the amounts follow at once.
                FoodItemEditorView(itemToEdit: food)
            }
            .alert("Densidade em falta", isPresented: Binding(
                get: { foodMissingDensity != nil },
                set: { if !$0 { foodMissingDensity = nil } }
            ), presenting: foodMissingDensity) { food in
                Button("Editar alimento") { foodToEdit = food }
                // Nothing is remembered: the next time this food is chosen it asks again.
                Button("Usar valor padrão", role: .cancel) {}
            } message: { food in
                Text("«\(food.name)» está em ml e não tem a densidade (g por ml). Queres editar o alimento agora ou usar o valor padrão (\(RecipeIngredientEditorView.number(FoodItem.defaultDensity)) g/ml)?")
            }
            .sheet(isPresented: $showingLog) {
                WeighLogSheet(items: session.items(foods: store.foodItems, gross: gross), date: date) { dismiss() }
            }
        }
    }

    /// The food chosen for the weight on the scale; a liquid without a density asks every time.
    private func choose(_ id: UUID) {
        session.chooseFood(id)
        if let food = store.foodItems.first(where: { $0.id == id }), food.lacksDensity {
            foodMissingDensity = food
        }
    }

    /// "120 g" for a solid, "120 g · 117 ml" for a liquid (through its density).
    private func weightText(_ grams: Int, of food: FoodItem) -> String {
        guard food.isLiquid else { return "\(grams) g" }
        return "\(grams) g · \(Int(food.baseAmount(forGrams: Double(grams)).rounded())) ml"
    }

    // MARK: - Pieces

    /// The food being weighed (tap to change it), or the reminder to choose one.
    private var foodChip: some View {
        Button {
            showingPicker = true
        } label: {
            HStack {
                if let food = currentFood {
                    Image(systemName: food.icon)
                    Text(food.name).lineLimit(1)
                    Spacer()
                    Text(weightText(pending, of: food)).monospacedDigit().bold()
                } else {
                    Image(systemName: needsFood ? "exclamationmark.triangle.fill" : "plus.circle")
                    Text(needsFood ? "Escolhe o alimento para este peso" : "Escolher alimento")
                    Spacer()
                }
            }
            .padding(12)
            .foregroundStyle(needsFood ? Color.orange : Color.primary)
            .background((needsFood ? Color.orange : Color.secondary).opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    /// Nutrition of the food being weighed only, from 0 g up to what is on the scale for it.
    @ViewBuilder
    private var nutritionTable: some View {
        if let food = currentFood, food.baseDoseAmount > 0 {
            let amounts = food.nutrition(quantity: food.quantity(forGrams: Double(pending)))
            VStack(alignment: .leading, spacing: 8) {
                Text("\(food.name) · \(weightText(pending, of: food))")
                    .font(.headline)
                NutritionFactsRows(amounts: amounts)
                    .font(.subheadline)
            }
            .padding()
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal)
        }
    }

    /// The pile on the right: plate, then each food with a "+" between them. Swipe left to remove one.
    private var pileColumn: some View {
        List {
            ForEach(Array(session.components.enumerated()), id: \.element.id) { index, component in
                if index > 0 { plusRow }
                pileItem(icon: icon(for: component), title: title(for: component), grams: component.grams, live: false)
                    .pileRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { session.remove(component) } label: {
                            Label("Remover", systemImage: "trash")
                        }
                    }
            }
            if let food = currentFood {
                if !session.components.isEmpty { plusRow }
                pileItem(icon: food.icon, title: food.name, grams: pending, live: true)
                    .pileRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { session.clearCurrentFood() } label: {
                            Label("Remover", systemImage: "trash")
                        }
                    }
            }
            if session.components.isEmpty && currentFood == nil {
                Text("A refeição aparece aqui.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .pileRow()
                    .padding(.top, 20)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
    }

    private var plusRow: some View {
        plus.frame(maxWidth: .infinity).pileRow()
    }

    private var plus: some View {
        Image(systemName: "plus")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
    }

    private func pileItem(icon: String, title: String, grams: Int, live: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(live ? 0.12 : 0.2), in: Circle())
                .overlay { if live { Circle().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4])) } }
            Text(title)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("\(grams) g")
                .font(.caption2.monospacedDigit().bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func icon(for component: WeighComponent) -> String {
        switch component.kind {
        case .plate: return FoodIcon.plateName
        case .food(let id): return store.foodItems.first { $0.id == id }?.icon ?? FoodIcon.defaultName
        }
    }

    private func title(for component: WeighComponent) -> String {
        switch component.kind {
        case .plate: return "Prato"
        case .food(let id): return store.foodItems.first { $0.id == id }?.name ?? "Alimento"
        }
    }

    /// Tara · Adicionar prato · Adicionar alimento · Registar alimento.
    private var buttonBar: some View {
        HStack(spacing: 8) {
            // Tap = tare; long press = forget every tare and say the scale is at zero (as in Balança).
            WeighActionButton(title: "Tara", systemImage: "scalemass", tint: .red,
                              enabled: scale.isConnected, action: { scale.tare() },
                              longPress: { scale.resetToZero(); resets += 1 })
            WeighActionButton(title: "Adicionar prato", systemImage: FoodIcon.plateName, tint: .blue,
                              enabled: scale.isConnected) {
                scale.tare()
                session.addPlate(gross: gross)
            }
            WeighActionButton(title: "Adicionar alimento", systemImage: "plus.circle.fill", tint: .green,
                              enabled: true) {
                session.commitCurrentFood(gross: gross)
                showingPicker = true
            }
            WeighActionButton(title: "Registar alimento", systemImage: "checkmark.circle.fill", tint: .accentColor,
                              enabled: hasFoods) {
                session.commitCurrentFood(gross: gross)
                showingLog = true
            }
        }
        .padding(10)
        .sensoryFeedback(.success, trigger: resets)
    }
}

/// A bottom-bar button: icon over a short label; optional long press.
private struct WeighActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let enabled: Bool
    let action: () -> Void
    var longPress: (() -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .foregroundStyle(.white)
        .background(tint.opacity(enabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { if enabled { action() } }
        .onLongPressGesture(minimumDuration: 0.6) { if enabled { longPress?() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

/// Picks the food for the weight on the scale: from the catalog, a new one by hand, or one imported with AI.
struct WeighFoodPickerSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let onPick: (UUID) -> Void

    @State private var selection: [UUID] = []
    @State private var showingNewFood = false
    @State private var showingJSONImport = false
    /// A food made in a sheet above this one, chosen once that sheet is gone.
    @State private var created: UUID?

    var body: some View {
        NavigationStack {
            FoodSelectionList(selection: $selection,
                              excluded: Set(store.foodItems.filter { $0.unit == .unit }.map(\.id)))
                .navigationTitle("Alimento")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { showingNewFood = true } label: {
                                Label("Novo Alimento", systemImage: "square.and.pencil")
                            }
                            Button { showingJSONImport = true } label: {
                                Label("Importar com IA", systemImage: "sparkles")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .onChange(of: selection) { _, value in
                    guard let id = value.last else { return }
                    onPick(id)
                    dismiss()
                }
                .sheet(isPresented: $showingNewFood, onDismiss: pickCreated) {
                    FoodItemEditorView(onSave: { created = $0.id })
                }
                .sheet(isPresented: $showingJSONImport, onDismiss: pickCreated) {
                    JSONImportSheet(
                        title: "Importar Alimento",
                        prompt: AIJSONImport.foodPrompt(categories: store.foodCategories.map(\.name)),
                        instructions: "Fotografa o alimento e o rótulo, ou descreve-o. O alimento é adicionado ao catálogo e escolhido para esta pesagem.",
                        onImportKeepingPhotos: { json, photos in
                            let payloads = try AIJSONImport.decodeFoodItems(from: json)
                            guard !payloads.isEmpty else { throw AIImportError.empty }
                            created = store.catalogFoods(for: payloads, photos: photos).first?.id
                        }
                    )
                }
        }
    }

    private func pickCreated() {
        guard let id = created else { return }
        onPick(id)
        dismiss()
    }
}

/// Last step: the meal and the time, then the foods of the pile are logged (the plate is not food).
private struct WeighLogSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let items: [RecipeItem]
    let date: Date
    let onLogged: () -> Void

    @State private var mealType: MealType
    @State private var logDate: Date

    init(items: [RecipeItem], date: Date, onLogged: @escaping () -> Void) {
        self.items = items
        self.date = date
        self.onLogged = onLogged
        _mealType = State(initialValue: MealType.suggested(for: date))
        _logDate = State(initialValue: Calendar.current.isDateInToday(date) ? .now : date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Registo") {
                    Picker("Refeição", selection: $mealType) {
                        ForEach(MealType.allCases) { meal in
                            Label(meal.displayName, systemImage: meal.symbolName).tag(meal)
                        }
                    }
                    DatePicker("Data", selection: $logDate)
                }
                Section {
                    NutritionFactsRows(amounts: store.fullNutrition(of: items))
                } header: {
                    Text("Total · \(store.amountSummary(of: items))")
                }
            }
            .navigationTitle("Registar Refeição")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registar") {
                        store.logFoodItems(items, mealType: mealType, date: logDate)
                        for _ in items { AppAnalytics.log(.entryLogged(source: .catalog, mealType: mealType)) }
                        dismiss()
                        onLogged()
                    }
                    .disabled(items.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}

private extension View {
    /// A row of the pile: no separator, no background, tight insets (the column is narrow).
    func pileRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 4))
    }
}
