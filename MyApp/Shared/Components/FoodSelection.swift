import SwiftUI

/// The catalog as a searchable list to pick foods from, organised like the catalog — favourites,
/// then each food category — with a check mark per row, so several foods can be chosen at once
/// (nothing moves when one is ticked, so the next tap lands where expected). `selection` keeps the order they were picked in.
/// `header` goes above the foods (e.g. scan / new food buttons).
struct FoodSelectionList<Header: View>: View {
    @Environment(DataStore.self) private var store

    @Binding var selection: [UUID]
    /// Foods that can't be picked (e.g. already in the recipe).
    var excluded: Set<UUID> = []
    @ViewBuilder var header: () -> Header

    @State private var searchText = ""

    private var available: [FoodItem] {
        store.foodItems.filter { !excluded.contains($0.id) }.filteredAndSorted(searchText: searchText, order: .name)
    }

    /// Favourites, then one group per category (in the categories' order), then the rest.
    private var groups: [(id: String, title: String, items: [FoodItem])] {
        let foods = available
        var groups: [(id: String, title: String, items: [FoodItem])] = []
        let favorites = foods.filter(\.isFavorite)
        if !favorites.isEmpty { groups.append(("favorites", "Favoritos", favorites)) }
        let others = foods.filter { !$0.isFavorite }
        for category in store.foodCategories {
            let items = others.filter { $0.categoryID == category.id }
            if !items.isEmpty { groups.append((category.id.uuidString, category.name, items)) }
        }
        let known = Set(store.foodCategories.map(\.id))
        let rest = others.filter { $0.categoryID.map { !known.contains($0) } ?? true }
        if !rest.isEmpty { groups.append(("none", store.foodCategories.isEmpty ? "Alimentos" : "Sem categoria", rest)) }
        return groups
    }

    var body: some View {
        List {
            header()

            if store.foodItems.isEmpty {
                ContentUnavailableView(
                    "Catálogo vazio",
                    systemImage: "tray",
                    description: Text("Adiciona alimentos no separador Alimentos.")
                )
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                if searchText.isEmpty {
                    UsageSuggestionsSection(
                        suggestions: { order in store.suggestedFoodItems(order).filter { !excluded.contains($0.id) } },
                        title: { item in item.brand.map { "\(item.name) (\($0))" } ?? item.name },
                        subtitle: { "dose \($0.doseLabel) · \($0.scaledCalories(quantity: 1)) kcal" },
                        isSelected: { selection.contains($0.id) },
                        select: { toggle($0.id) }
                    )
                }
                ForEach(groups, id: \.id) { group in
                    Section("\(group.title) (\(group.items.count))") {
                        ForEach(group.items) { item in
                            row(item)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Procurar nome, marca ou código")
    }

    private func row(_ item: FoodItem) -> some View {
        let isSelected = selection.contains(item.id)
        return Button {
            toggle(item.id)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)
                PhotoThumbnail(photoID: item.photoID, placeholder: "carrot")
                VStack(alignment: .leading) {
                    Text(item.brand.map { "\(item.name) (\($0))" } ?? item.name)
                    Text("dose \(item.doseLabel) · \(item.scaledCalories(quantity: 1)) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: UUID) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }
        Haptics.light()
    }

}

extension FoodSelectionList where Header == EmptyView {
    init(selection: Binding<[UUID]>, excluded: Set<UUID> = []) {
        self.init(selection: selection, excluded: excluded) { EmptyView() }
    }
}

/// Second step after picking several foods: how much of each (in the food's own unit, one dose to
/// start with), the totals, and — when logging — the meal. Swipe a food to drop it.
struct FoodAmountsView: View {
    @Environment(DataStore.self) private var store

    let confirmTitle: String
    /// Shows the meal picker (logging to the diary); `nil` = no meal (adding to a recipe).
    let initialMeal: MealType?
    let onConfirm: (_ items: [RecipeItem], _ meal: MealType, _ date: Date) -> Void

    @State private var foodIDs: [UUID]
    @State private var amounts: [UUID: String] = [:]
    @State private var mealType: MealType
    /// When it was eaten (shown with the meal, when logging).
    @State private var logDate: Date
    @State private var didLoad = false

    /// `date`: the day logged on (for today, the current time is used instead of midnight).
    init(foodIDs: [UUID], confirmTitle: String, initialMeal: MealType? = nil, date: Date = .now,
         onConfirm: @escaping (_ items: [RecipeItem], _ meal: MealType, _ date: Date) -> Void) {
        _foodIDs = State(initialValue: foodIDs)
        self.confirmTitle = confirmTitle
        self.initialMeal = initialMeal
        self.onConfirm = onConfirm
        _mealType = State(initialValue: initialMeal ?? .snack)
        _logDate = State(initialValue: Calendar.current.isDateInToday(date) ? .now : date)
    }

    /// The typed amounts as doses; foods at 0 (or unreadable) are left out.
    private var items: [RecipeItem] {
        foodIDs.compactMap { id in
            guard let food = food(id), food.doseSize > 0,
                  let amount = Double((amounts[id] ?? "").trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: ",", with: ".")), amount > 0 else { return nil }
            return RecipeItem(foodItemID: id, quantity: amount / food.doseSize)
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(foodIDs, id: \.self) { id in
                    if let food = food(id) {
                        amountRow(food)
                    }
                }
                .onDelete { offsets in foodIDs.remove(atOffsets: offsets) }
            } header: {
                Text("Quantidades")
            } footer: {
                Text("Começa numa dose de cada. Desliza para tirar um alimento.")
            }

            if initialMeal != nil {
                Section("Registo") {
                    Picker("Refeição", selection: $mealType) {
                        ForEach(MealType.allCases) { meal in
                            Label(meal.displayName, systemImage: meal.symbolName).tag(meal)
                        }
                    }
                    DatePicker("Data", selection: $logDate)
                }
            }

            if !items.isEmpty {
                Section {
                    NutritionFactsRows(amounts: store.fullNutrition(of: items))
                } header: {
                    Text("Total · \(store.amountSummary(of: items))")
                }
            }
        }
        .navigationTitle("\(foodIDs.count) \(foodIDs.count == 1 ? "Alimento" : "Alimentos")")
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            for id in foodIDs {
                if let food = food(id) { amounts[id] = RecipeIngredientEditorView.number(food.doseSize) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle) { onConfirm(items, mealType, logDate) }
                    .disabled(items.isEmpty)
            }
        }
    }

    private func amountRow(_ food: FoodItem) -> some View {
        let quantity = items.first { $0.foodItemID == food.id }?.quantity ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                Text(quantity > 0 ? "\(food.scaledCalories(quantity: quantity)) kcal" : "Não incluído")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("0", text: Binding(
                get: { amounts[food.id] ?? "" },
                set: { amounts[food.id] = $0 }
            ))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(food.unit.shortLabel)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
        }
    }

    private func food(_ id: UUID) -> FoodItem? {
        store.foodItems.first { $0.id == id }
    }
}

/// The check circle of a row in a list's multi-select mode.
struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .font(.title3)
    }
}

/// The bar under a list in multi-select mode: "Eliminar N …", disabled with nothing selected.
struct SelectionDeleteBar: View {
    let count: Int
    /// Singular and plural ("alimento", "alimentos").
    let noun: (String, String)
    let onDelete: () -> Void

    var body: some View {
        Button(role: .destructive, action: onDelete) {
            Label(count == 0 ? "Escolhe o que eliminar" : "Eliminar \(count) \(count == 1 ? noun.0 : noun.1)",
                  systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
        .disabled(count == 0)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
