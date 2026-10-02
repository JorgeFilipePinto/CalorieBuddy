import SwiftUI

/// Lists nutrition plans grouped by status (ativos / agendados / terminados), each with its
/// training and rest targets. Active plans can overlap (date range + priority); the one actually
/// applied today is highlighted ("Em Vigor"), others shown as overridden. Mirrors the platform's
/// `/dashboard/plans` page.
struct NutritionPlansListView: View {
    @Environment(DataStore.self) private var store

    @State private var showingNewPlan = false
    @State private var planToEdit: NutritionPlan?
    @State private var planToDuplicate: NutritionPlan?

    private var classified: [ClassifiedNutritionPlan] {
        store.nutritionPlans.classified(today: .now)
    }
    // The plan in effect first, then other active plans by priority (highest first).
    private var active: [ClassifiedNutritionPlan] {
        classified.filter { $0.status == .active }
            .sorted { ($0.inEffect ? 1 : 0, $0.plan.priority) > ($1.inEffect ? 1 : 0, $1.plan.priority) }
    }
    private var scheduled: [ClassifiedNutritionPlan] { classified.filter { $0.status == .scheduled } }
    private var ended: [ClassifiedNutritionPlan] { Array(classified.filter { $0.status == .ended }.reversed()) }

    var body: some View {
        List {
            if classified.isEmpty {
                ContentUnavailableView(
                    "Sem Planos",
                    systemImage: "target",
                    description: Text("Cria o primeiro para definires os objetivos diários de calorias, macros e água.")
                )
            } else {
                section(title: "Ativos", plans: active, emptyText: "Nenhum plano ativo hoje.")
                section(title: "Agendados", plans: scheduled, emptyText: "Nada agendado.")
                if !ended.isEmpty {
                    section(title: "Terminados", plans: ended, emptyText: nil)
                }
            }
        }
        .navigationTitle("Planos Alimentares")
        .trackScreen("Planos Alimentares")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewPlan = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewPlan) {
            NutritionPlanEditorView()
        }
        .sheet(item: $planToEdit) { plan in
            NutritionPlanEditorView(planToEdit: plan)
        }
        .sheet(item: $planToDuplicate) { plan in
            NutritionPlanEditorView(duplicateFrom: plan)
        }
    }

    @ViewBuilder
    private func section(title: String, plans: [ClassifiedNutritionPlan], emptyText: String?) -> some View {
        Section(title) {
            if plans.isEmpty, let emptyText {
                Text(emptyText).foregroundStyle(.secondary)
            } else {
                ForEach(plans) { classified in
                    planRow(classified)
                }
            }
        }
    }

    private func planRow(_ classified: ClassifiedNutritionPlan) -> some View {
        let plan = classified.plan
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(plan.name).font(.headline)
                    PlanStatusBadge(status: classified.status, inEffect: classified.inEffect)
                    if plan.priority > 1 {
                        PlanPriorityBadge(priority: plan.priority)
                    }
                }
                Text(dateRangeLabel(classified))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let notes = plan.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                targetsColumn(dayType: .training, targets: plan.training)
                targetsColumn(dayType: .rest, targets: plan.rest)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { planToEdit = plan }
        .swipeActions(edge: .leading) {
            Button {
                planToDuplicate = plan
            } label: {
                Label("Duplicar", systemImage: "doc.on.doc")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteNutritionPlan(plan)
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }

    private func dateRangeLabel(_ classified: ClassifiedNutritionPlan) -> String {
        let start = classified.plan.startsOn.formatted(date: .abbreviated, time: .omitted)
        if let endsOn = classified.plan.endsOn {
            let end = endsOn.formatted(date: .abbreviated, time: .omitted)
            return classified.status == .scheduled ? "A partir de \(start) · até \(end)" : "\(start) – \(end)"
        }
        return classified.status == .scheduled ? "A partir de \(start)" : "Desde \(start) · em aberto"
    }

    private func targetsColumn(dayType: DayType, targets: NutritionTargets) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(dayType.displayName.uppercased(), systemImage: dayType.symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(targets.kcal) kcal")
                .font(.subheadline.weight(.medium))
            Text("P \(targets.proteinG)g · HC \(targets.carbsG)g · G \(targets.fatG)g")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(targets.waterML) ml água")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        NutritionPlansListView()
    }
    .environment(DataStore())
}
