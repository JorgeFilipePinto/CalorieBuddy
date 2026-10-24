import SwiftUI

/// A meal planned on the week board, shown lighter in its meal on the day: "Comi" logs it with
/// the board's amounts, "Recusar" picks what was eaten instead. Not confirmed by the end of the
/// day = not eaten.
struct PlannedMealRow: View {
    @Environment(DataStore.self) private var store

    let placement: MealBoardPlacement
    let onRefuse: () -> Void

    var body: some View {
        let state = store.state(of: placement)
        let recipe = store.recipe(withID: placement.recipeID)
        let totals = store.nutrition(of: placement)
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe?.name ?? "Receita apagada")
                    .strikethrough(state == .refused)
                Text(caption(for: state))
                    .font(.caption)
                    .foregroundStyle(state == .missed ? .orange : .secondary)
            }
            Spacer()
            Text("\(Int(totals.calories.rounded())) kcal")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            if state == .refused {
                Button {
                    store.resetPlacement(placement)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Anular recusa")
            } else {
                Button {
                    if store.confirmPlacement(placement) { Haptics.success() }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.borderless)
                .disabled(recipe == nil)
                .accessibilityLabel("Comi")
                Button(action: onRefuse) {
                    Image(systemName: "xmark.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Recusar")
            }
        }
        .opacity(state == .refused ? 0.45 : 0.6)
        .listRowBackground(Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding(-6)
        }
    }

    private func caption(for state: PlacementState) -> String {
        switch state {
        case .refused:
            if let id = placement.replacementRecipeID, let recipe = store.recipe(withID: id) {
                return "Recusada · comeste \(recipe.name)"
            }
            return "Recusada"
        case .missed: return "Planeada · não confirmada, conta como não consumida"
        case .planned, .consumed:
            return placement.time.map { "Planeada para as \($0) · por confirmar" } ?? "Planeada no Quadro Semanal · por confirmar"
        }
    }
}

/// "Recusar": what was eaten instead — pick a recipe, adjust its amounts and it's logged; the
/// planned meal is marked refused. Or refuse without logging anything.
struct PlacementSubstituteView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let placement: MealBoardPlacement
    @State private var searchText = ""

    private var visible: [Recipe] {
        let sorted = store.recipes.filteredAndSorted(searchText: "", order: .name)
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { recipe in
            SearchMatch.matches(searchText, in: [recipe.name] + recipe.items.compactMap { item in
                store.foodItems.first { $0.id == item.foodItemID }?.name
            })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Só recusar, sem registar nada") {
                        store.refusePlacement(placement)
                        dismiss()
                    }
                } footer: {
                    Text("Ou escolhe abaixo o que comeste: ajustas as quantidades e fica registado em \(placement.meal.displayName).")
                }
                Section("O que comeste") {
                    ForEach(visible) { recipe in
                        NavigationLink {
                            RecipeLogView(
                                recipe: recipe,
                                date: WeekBoard.logDate(for: placement),
                                mealType: placement.meal,
                                onLogged: { group in
                                    store.refusePlacement(placement, replacedBy: recipe.id, group: group)
                                },
                                onDone: { dismiss() }
                            )
                        } label: {
                            Text(recipe.name)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Nome ou ingrediente")
            .navigationTitle("Em vez de \(store.recipe(withID: placement.recipeID)?.name ?? "planeada")")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}
