import SwiftUI
import Charts

/// Saúde → Peso e Composição: charts of the last 30 days (swipe between weight, fat vs muscle and
/// BMI), the goal weight and every weigh-in by week; a weigh-in opens its full composition report.
struct WeightView: View {
    @Environment(DataStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit

    @State private var showingLogWeight = false
    @State private var showingGoal = false

    private var weighIns: [WeighIn] { store.weighIns(healthKit: healthKit) }
    private var goal: Double? { store.settings.goalWeightKG }

    private struct Week: Identifiable {
        let start: Date
        let end: Date
        let items: [WeighIn]
        var id: Date { start }
    }

    var body: some View {
        let all = weighIns
        List {
            Section {
                WeightChartsPager(weighIns: all, goal: goal)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                if let latest = all.first {
                    WeightGoalBar(weight: latest.weight, goal: goal)
                        .padding(.vertical, 4)
                } else {
                    Text("Sem registos de peso.").foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Peso Objetivo")
                    Spacer()
                    Button(goal == nil ? "Definir" : "Editar") { showingGoal = true }
                        .font(.subheadline)
                        .textCase(nil)
                }
            }

            ForEach(weeks(of: all)) { week in
                Section(title(of: week)) {
                    ForEach(week.items) { weighIn in
                        NavigationLink {
                            WeightDetailView(weighIns: all, selected: weighIn.id, goal: goal)
                        } label: {
                            row(weighIn)
                        }
                    }
                }
            }
        }
        .navigationTitle("Peso")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLogWeight = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingLogWeight) { LogWeightView() }
        .sheet(isPresented: $showingGoal) { GoalWeightSheet() }
    }

    private func row(_ weighIn: WeighIn) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "scalemass")
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(weighIn.date.formatted(.dateTime.weekday(.wide).hour().minute()).capitalized)
                if weighIn.bodyFatPercent != nil || weighIn.muscleKg != nil {
                    Text("com composição corporal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(WeightGoalBar.kg(weighIn.weight))
                .font(.headline)
                .monospacedDigit()
        }
    }

    /// Weigh-ins grouped by calendar week, most recent first.
    private func weeks(of all: [WeighIn]) -> [Week] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: all) {
            calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? calendar.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted(by: >).map { start in
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return Week(start: start, end: end, items: (grouped[start] ?? []).sorted { $0.date > $1.date })
        }
    }

    private func title(of week: Week) -> String {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start
        if week.start == thisWeek { return "Esta semana" }
        if let thisWeek, let last = calendar.date(byAdding: .day, value: -7, to: thisWeek), week.start == last {
            return "Semana passada"
        }
        return "\(week.start.formatted(.dateTime.day())) – \(week.end.formatted(.dateTime.day().month(.wide)))"
    }
}

/// The three charts of the screen, swiped like pages.
struct WeightChartsPager: View {
    let weighIns: [WeighIn]
    let goal: Double?

    @State private var page = 0

    private var recent: [WeighIn] {
        let from = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        return weighIns.filter { $0.date >= from }.sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(spacing: 8) {
            #if os(iOS)
            TabView(selection: $page) {
                weightChart.tag(0)
                compositionChart.tag(1)
                bmiChart.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 300)
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(index == page ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            #else
            weightChart.frame(height: 300)
            #endif
        }
        .padding(.vertical, 8)
    }

    private func card<Content: View>(_ title: String, legend: AnyView? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            if let legend { legend }
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var emptyChart: some View {
        Text("Sem registos nos últimos 30 dias.")
            .foregroundStyle(.secondary)
            .frame(maxHeight: .infinity)
    }

    private var weightChart: some View {
        card("O teu peso, 30 dias (kg)", legend: goal.map { AnyView(legendItem(.green, "Objetivo: \(Int($0.rounded()))")) }) {
            if recent.isEmpty {
                emptyChart
            } else {
                let values = recent.map(\.weight) + (goal.map { [$0] } ?? [])
                Chart {
                    ForEach(recent) { item in
                        LineMark(x: .value("Dia", item.date), y: .value("kg", item.weight))
                            .foregroundStyle(.blue)
                        PointMark(x: .value("Dia", item.date), y: .value("kg", item.weight))
                            .foregroundStyle(.blue)
                    }
                    if let goal {
                        RuleMark(y: .value("Objetivo", goal)).foregroundStyle(.green)
                    }
                }
                .chartYScale(domain: (floor((values.min() ?? 0) - 2))...(ceil((values.max() ?? 0) + 2)))
            }
        }
    }

    private var compositionChart: some View {
        let withComposition = recent.filter { $0.bodyFatKg != nil || $0.muscleKg != nil }
        return card("Gordura vs Músculo (kg)", legend: AnyView(HStack(spacing: 12) {
            legendItem(.yellow, "Gordura")
            legendItem(.indigo, "Músculo")
        })) {
            if withComposition.isEmpty {
                emptyChart
            } else {
                Chart {
                    ForEach(withComposition) { item in
                        if let fat = item.bodyFatKg {
                            BarMark(x: .value("Dia", item.date, unit: .day), y: .value("kg", fat))
                                .foregroundStyle(Color.yellow)
                        }
                        if let muscle = item.muscleKg {
                            BarMark(x: .value("Dia", item.date, unit: .day), y: .value("kg", muscle))
                                .foregroundStyle(Color.indigo)
                        }
                    }
                }
            }
        }
    }

    private var bmiChart: some View {
        let points = recent.compactMap { item in item.bmi.map { (item.date, $0) } }
        return card("O teu IMC, 30 dias") {
            if points.isEmpty {
                Text("Precisa do peso e da altura (app Saúde).")
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                let values = points.map(\.1)
                Chart {
                    RectangleMark(yStart: .value("de", 25), yEnd: .value("até", 30))
                        .foregroundStyle(RangeTone.healthy.color.opacity(0.3))
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Dia", point.0), y: .value("IMC", point.1)).foregroundStyle(.blue)
                        PointMark(x: .value("Dia", point.0), y: .value("IMC", point.1)).foregroundStyle(.blue)
                    }
                }
                .chartYScale(domain: (floor((values.min() ?? 0) - 1))...(ceil((values.max() ?? 0) + 1)))
            }
        }
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Sets (or clears) the goal weight.
struct GoalWeightSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""

    private var value: Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("Peso objetivo (kg)")
                    Spacer()
                    TextField("76", text: $text)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                if store.settings.goalWeightKG != nil {
                    Button("Remover objetivo", role: .destructive) {
                        save(nil)
                    }
                }
            }
            .navigationTitle("Peso Objetivo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save(value) }
                        .disabled(value.map { $0 < 20 || $0 > 400 } ?? true)
                }
            }
            .onAppear {
                text = store.settings.goalWeightKG.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
            }
        }
    }

    private func save(_ goal: Double?) {
        var settings = store.settings
        settings.goalWeightKG = goal
        store.updateSettings(settings)
        dismiss()
    }
}
