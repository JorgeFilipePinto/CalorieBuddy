import SwiftUI

/// A preparation of a raw food (grelhado, cozido, estufado…): how it's cooked and how much its
/// weight changes — the label per 100 g cooked is worked out from the raw food and follows it.
/// Starts from the reference for the food and the method (Despensa → Variação na Confeção).
struct FoodPreparationEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let base: FoodItem
    let existing: FoodItem?

    @State private var method: FoodPreparation = .grilled
    @State private var changeText = ""
    @State private var name = ""
    @State private var categoryID: UUID?
    /// The name is the automatic one until it's edited by hand.
    @State private var nameEdited = false
    @State private var didLoad = false
    @State private var confirmingDelete = false

    private var change: Double? {
        LabelNutritionText.number(changeText.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "−", with: "-"))
    }

    /// Methods already used by another preparation of this food.
    private var usedMethods: Set<FoodPreparation> {
        Set(store.preparations(of: base).filter { $0.id != existing?.id }.compactMap(\.preparation))
    }

    private var preview: FoodItem? {
        guard let change, change > -100 else { return nil }
        return base.prepared(method, change: change, updating: existing)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Alimento cru", value: base.name)
                Picker("Preparação", selection: $method) {
                    ForEach(FoodPreparation.cooked) { option in
                        Label(option.displayName, systemImage: option.symbolName).tag(option)
                    }
                }
                HStack {
                    Text("Variação do peso")
                    Spacer()
                    TextField("0", text: $changeText)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("%").foregroundStyle(.secondary)
                }
            } footer: {
                if let change {
                    Text("100 g cru → \(PantryFormat.number(max(100 + change, 0))) g \(method.nameSuffix). Começa no valor de referência; ajusta-o à tua forma de cozinhar (negativo = perde água, positivo = ganha).")
                }
            }

            Section("Alimento") {
                TextField("Nome", text: Binding(get: { name }, set: { name = $0; nameEdited = true }))
                Picker("Categoria", selection: $categoryID) {
                    Text("Sem categoria").tag(UUID?.none)
                    ForEach(store.orderedFoodCategories) { category in
                        Text(store.categoryTitle(category)).tag(UUID?.some(category.id))
                    }
                }
            }

            if let preview {
                Section {
                    NutritionFactsRows(amounts: preview.nutrition(quantity: 100 / max(preview.baseDoseAmount, 1)))
                } header: {
                    Text("Por 100 \(preview.unit.shortLabel) \(method.nameSuffix)")
                } footer: {
                    Text("Calculado do alimento cru: a confeção muda sobretudo a água, por isso os nutrientes de 100 g crus ficam no peso cozinhado. Gordura ou molho acrescentados na confeção não estão incluídos — junta-os na receita.")
                }
            }

            if usedMethods.contains(method) {
                Section {
                    Label("Este alimento já tem uma preparação \(method.nameSuffix).", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            if existing != nil {
                Section {
                    Button("Eliminar Preparação", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .navigationTitle(existing == nil ? "Nova Preparação" : "Preparação")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { save() }
                    .disabled(preview == nil || name.trimmingCharacters(in: .whitespaces).isEmpty || usedMethods.contains(method))
            }
        }
        .onAppear(perform: load)
        .onChange(of: method) { _, newMethod in
            if !nameEdited { name = base.preparationName(newMethod) }
            if existing == nil || existing?.preparation != newMethod {
                changeText = PantryFormat.plainNumber(store.suggestedWeightChange(for: base, method: newMethod).percent)
            }
        }
        .confirmationDialog("Eliminar esta preparação?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                if let existing { store.deleteFoodItem(existing) }
                dismiss()
            }
        } message: {
            Text("Sai do catálogo e das receitas que a usam. O que já está registado no diário mantém-se.")
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        store.seedCookingYieldsIfEmpty()
        if let existing {
            method = existing.preparation ?? .boiled
            changeText = PantryFormat.plainNumber(existing.cookingWeightChange ?? 0)
            name = existing.name
            nameEdited = true
            categoryID = existing.categoryID
        } else {
            let first = FoodPreparation.cooked.first { !usedMethods.contains($0) } ?? .grilled
            method = first
            changeText = PantryFormat.plainNumber(store.suggestedWeightChange(for: base, method: first).percent)
            name = base.preparationName(first)
            categoryID = base.categoryID
        }
    }

    private func save() {
        guard let change else { return }
        store.savePreparation(of: base, method: method, change: change,
                              name: name.trimmingCharacters(in: .whitespaces), categoryID: categoryID, existing: existing)
        Haptics.success()
        dismiss()
    }
}
