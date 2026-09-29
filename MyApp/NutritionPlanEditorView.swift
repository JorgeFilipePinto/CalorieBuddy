import SwiftUI

/// Creates, edits or duplicates a nutrition plan. Fields and validation bounds match the
/// platform's own plan form (`Dashboard/src/lib/plans/plan.ts`), so a plan saved here already has
/// the exact shape `save_nutrition_plan` expects, once the app migrates to that backend.
struct NutritionPlanEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let planToEdit: NutritionPlan?
    let duplicateFrom: NutritionPlan?

    @State private var name = ""
    @State private var startsOn = Date()
    @State private var notes = ""
    @State private var training = NutritionPlanEditorView.defaultTargets
    @State private var rest = NutritionPlanEditorView.defaultTargets

    @State private var errorMessage: String?

    private static let defaultTargets = NutritionTargets(kcal: 2500, proteinG: 150, carbsG: 300, fatG: 80, waterML: 3000)

    init(planToEdit: NutritionPlan? = nil, duplicateFrom: NutritionPlan? = nil) {
        self.planToEdit = planToEdit
        self.duplicateFrom = duplicateFrom
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedNotes: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        (2...80).contains(trimmedName.count) && trimmedNotes.count <= 4000
            && isValid(training) && isValid(rest)
    }

    private func isValid(_ targets: NutritionTargets) -> Bool {
        (500...10000).contains(targets.kcal)
            && (0...1000).contains(targets.proteinG)
            && (0...2000).contains(targets.carbsG)
            && (0...1000).contains(targets.fatG)
            && (0...15000).contains(targets.waterML)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $name)
                    DatePicker("Data de Início", selection: $startsOn, displayedComponents: .date)
                } header: {
                    Text("Plano")
                } footer: {
                    Text("Os objetivos aplicam-se a partir desta data até começar o próximo plano.")
                }

                Section {
                    TextField("Notas (opcional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notas")
                } footer: {
                    Text("\(notes.count)/4000")
                }

                targetsSection(title: "Dias de Treino", symbolName: DayType.training.symbolName, targets: $training)
                targetsSection(title: "Dias de Descanso", symbolName: DayType.rest.symbolName, targets: $rest)
            }
            .navigationTitle(planToEdit == nil ? "Novo Plano" : "Editar Plano")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: populate)
            .alert(
                "Erro ao Guardar",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func targetsSection(title: String, symbolName: String, targets: Binding<NutritionTargets>) -> some View {
        Section {
            targetField("Calorias (kcal)", value: targets.kcal)
            targetField("Proteína (g)", value: targets.proteinG)
            targetField("Hidratos de Carbono (g)", value: targets.carbsG)
            targetField("Gordura (g)", value: targets.fatG)
            targetField("Água (ml)", value: targets.waterML)
        } header: {
            Label(title, systemImage: symbolName)
        } footer: {
            if targets.wrappedValue.hasMacroMismatch {
                Text("Os macros somam \(targets.wrappedValue.macroKcal) kcal, não \(targets.wrappedValue.kcal) kcal — confirma os valores.")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func targetField(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: Binding(
                get: { String(value.wrappedValue) },
                set: { value.wrappedValue = Int($0) ?? value.wrappedValue }
            ))
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            .multilineTextAlignment(.trailing)
            .frame(width: 90)
        }
    }

    private func populate() {
        if let planToEdit {
            name = planToEdit.name
            startsOn = planToEdit.startsOn
            notes = planToEdit.notes ?? ""
            training = planToEdit.training
            rest = planToEdit.rest
            return
        }

        if let duplicateFrom {
            name = "\(duplicateFrom.name) (cópia)"
            notes = duplicateFrom.notes ?? ""
            training = duplicateFrom.training
            rest = duplicateFrom.rest
        }
        startsOn = defaultStartDate()
    }

    /// A week after the last scheduled plan's start date, or tomorrow if none is scheduled —
    /// mirrors the platform's own default for a new plan's start date.
    private func defaultStartDate() -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let lastStart = store.nutritionPlans.live.last.map({ calendar.startOfDay(for: $0.startsOn) }) else {
            return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        }
        if lastStart >= today {
            return calendar.date(byAdding: .day, value: 7, to: lastStart) ?? today
        }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    private func save() {
        guard isValid else { return }
        let day = Calendar.current.startOfDay(for: startsOn)
        guard !store.isNutritionPlanStartDateTaken(day, excluding: planToEdit?.id) else {
            errorMessage = "Já existe um plano a começar neste dia."
            return
        }

        let plan = NutritionPlan(
            id: planToEdit?.id ?? UUID(),
            name: trimmedName,
            startsOn: day,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            training: training,
            rest: rest,
            createdAt: planToEdit?.createdAt ?? Date()
        )
        store.saveNutritionPlan(plan)
        dismiss()
    }
}

#Preview {
    NutritionPlanEditorView()
        .environment(DataStore())
}
