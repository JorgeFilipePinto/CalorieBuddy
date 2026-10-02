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
    @State private var isTemporary = false
    @State private var endsOn = Date()
    @State private var priority = 1
    @State private var notes = ""
    @State private var training = NutritionPlanEditorView.defaultTargets
    @State private var rest = NutritionPlanEditorView.defaultTargets

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
            // Same check as the platform's `nutrition_plans` (ends_on >= starts_on).
            && (!isTemporary || Calendar.current.startOfDay(for: endsOn) >= Calendar.current.startOfDay(for: startsOn))
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
                    Toggle("Plano Temporário", isOn: $isTemporary.animation())
                    if isTemporary {
                        DatePicker("Data de Fim", selection: $endsOn, in: startsOn..., displayedComponents: .date)
                    }
                    Picker("Prioridade", selection: $priority) {
                        ForEach(1...5, id: \.self) { level in
                            Text(level == 1 ? "1 — plano normal" : level == 5 ? "5 — máxima" : "\(level)").tag(level)
                        }
                    }
                } header: {
                    Text("Plano")
                } footer: {
                    Text("Em aberto por omissão. Quando mais do que um plano cobre o mesmo dia, aplica-se o de prioridade mais alta.")
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
            // Moving the start past the end would leave an invalid range; keep the end with it.
            .onChange(of: startsOn) {
                if endsOn < startsOn { endsOn = startsOn }
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
            isTemporary = planToEdit.endsOn != nil
            endsOn = planToEdit.endsOn ?? planToEdit.startsOn
            priority = planToEdit.priority
            notes = planToEdit.notes ?? ""
            training = planToEdit.training
            rest = planToEdit.rest
            return
        }

        if let duplicateFrom {
            name = "\(duplicateFrom.name) (cópia)"
            isTemporary = duplicateFrom.endsOn != nil
            priority = duplicateFrom.priority
            notes = duplicateFrom.notes ?? ""
            training = duplicateFrom.training
            rest = duplicateFrom.rest
        }
        startsOn = defaultStartDate()
        // A duplicated temporary plan keeps the original's length (e.g. the same 3-week block).
        let length = duplicateFrom.flatMap { source in
            source.endsOn.flatMap { Calendar.current.dateComponents([.day], from: source.startsOn, to: $0).day }
        } ?? 0
        endsOn = Calendar.current.date(byAdding: .day, value: length, to: startsOn) ?? startsOn
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

        let plan = NutritionPlan(
            id: planToEdit?.id ?? UUID(),
            name: trimmedName,
            startsOn: day,
            endsOn: isTemporary ? Calendar.current.startOfDay(for: endsOn) : nil,
            priority: priority,
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
