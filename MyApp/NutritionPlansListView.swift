import SwiftUI

/// Lists nutrition plans grouped by status (em vigor / agendados / anteriores), each with its
/// training and rest targets. Mirrors the platform's `/dashboard/plans` page, so a plan created
/// here has the exact same shape it would need to be written straight into `nutrition_plans` +
/// `nutrition_targets` once the app migrates to that backend.
struct NutritionPlansListView: View {
    @Environment(DataStore.self) private var store

    @State private var showingNewPlan = false
    @State private var planToEdit: NutritionPlan?
    @State private var planToDuplicate: NutritionPlan?

    private var classified: [ClassifiedNutritionPlan] {
        store.nutritionPlans.classified(today: .now)
    }
    private var current: [ClassifiedNutritionPlan] { classified.filter { $0.status == .current } }
    private var upcoming: [ClassifiedNutritionPlan] { classified.filter { $0.status == .upcoming } }
    private var past: [ClassifiedNutritionPlan] { Array(classified.filter { $0.status == .past }.reversed()) }

    var body: some View {
        List {
            if classified.isEmpty {
                ContentUnavailableView(
                    "Sem Planos",
                    systemImage: "target",
                    description: Text("Cria o primeiro para definires os objetivos diários de calorias, macros e água.")
                )
            } else {
                section(title: "Em Vigor", plans: current, emptyText: "Nenhum plano em vigor hoje.")
                section(title: "Agendados", plans: upcoming, emptyText: "Nada agendado.")
                if !past.isEmpty {
                    section(title: "Planos Anteriores", plans: past, emptyText: nil)
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
                    statusBadge(classified.status)
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

    private func statusBadge(_ status: PlanStatus) -> some View {
        Text(statusLabel(status))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor(status))
    }

    private func statusLabel(_ status: PlanStatus) -> String {
        switch status {
        case .current: return "Em Vigor"
        case .upcoming: return "Agendado"
        case .past: return "Terminado"
        }
    }

    private func statusColor(_ status: PlanStatus) -> Color {
        switch status {
        case .current: return .green
        case .upcoming: return .blue
        case .past: return .secondary
        }
    }

    private func dateRangeLabel(_ classified: ClassifiedNutritionPlan) -> String {
        let start = classified.plan.startsOn.formatted(date: .abbreviated, time: .omitted)
        if let endsOn = classified.endsOn {
            return "\(start) – \(endsOn.formatted(date: .abbreviated, time: .omitted))"
        }
        return classified.status == .upcoming ? "A partir de \(start)" : "Desde \(start)"
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
