import SwiftUI

/// Every day with something recorded, grouped into collapsible months. Each month's header
/// already says what was trained — kilometres per sport, time for the gym — before expanding it.
struct HistoryView: View {
    @Environment(DataStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit

    /// How many days back of Apple Health data have been requested so far: a year to start with,
    /// another year on demand.
    @State private var daysLoaded = 365
    @State private var isLoadingMore = false
    /// Months open in the list (first day of each). The current month starts open.
    @State private var expandedMonths: Set<Date> = [Self.monthStart(of: .now)]

    private let pageSize = 365
    private let maxDaysLoaded = 730

    /// Three equal-width columns, so a day's metric badges always line up in a tidy grid instead
    /// of running off the row's edge or bunching up unpredictably.
    private static let metricColumns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3)

    /// Days with food entries, plus any day Apple Health has water, weight, sleep or other
    /// tracked data for (within `daysLoaded`), so days tracked only through Health still show up.
    private var allDays: [Date] {
        var days = Set(store.allDays)
        if healthKit.isSupported {
            days.formUnion(healthKit.waterLitersByDay.keys)
            days.formUnion(healthKit.caloriesBurnedByDay.keys)
            days.formUnion(healthKit.caffeineMgByDay.keys)
            days.formUnion(healthKit.sleepHoursByDay.keys)
            days.formUnion(healthKit.workoutsByDay.keys)
            days.formUnion(healthKit.weightHistory.map { Calendar.current.startOfDay(for: $0.date) })
            days.formUnion(healthKit.bodyFatHistory.map { Calendar.current.startOfDay(for: $0.date) })
            days.formUnion(healthKit.bmiHistory.map { Calendar.current.startOfDay(for: $0.date) })
        }
        return days.sorted(by: >)
    }

    /// One calendar month of history, with its training totals per sport.
    private struct HistoryMonth: Identifiable {
        let start: Date
        /// Most recent first.
        let days: [Date]
        let activities: [ActivityTotal]
        /// Daily averages over the days that have any (`nil` when none does).
        let averageWaterML: Int?
        let averageCaloriesBurned: Int?
        var id: Date { start }
    }

    /// A sport's total for a month: kilometres, or time for sports with no distance (the gym).
    private struct ActivityTotal: Identifiable {
        let kind: HealthKitManager.WorkoutKind
        let sessions: Int
        let duration: TimeInterval
        let distanceMeters: Double
        var id: String { kind.displayName }

        var showsDistance: Bool { kind.isMeasuredByDistance && distanceMeters > 0 }
        var value: String { showsDistance ? formattedKilometres(distanceMeters) : formattedWorkoutDuration(duration) }
    }

    private var months: [HistoryMonth] {
        let byMonth = Dictionary(grouping: allDays, by: Self.monthStart(of:))
        return byMonth.keys.sorted(by: >).map { start in
            let days = (byMonth[start] ?? []).sorted(by: >)
            let workouts = days.flatMap { healthKit.workouts(on: $0) }
            let activities = Dictionary(grouping: workouts, by: \.kind.displayName).values.compactMap { group -> ActivityTotal? in
                guard let kind = group.first?.kind else { return nil }
                return ActivityTotal(
                    kind: kind,
                    sessions: group.count,
                    duration: group.reduce(0) { $0 + $1.duration },
                    distanceMeters: group.reduce(0) { $0 + ($1.distanceMeters ?? 0) }
                )
            }
            // Distance sports first (longest first), then time-based ones (longest first).
            .sorted { lhs, rhs in
                if lhs.showsDistance != rhs.showsDistance { return lhs.showsDistance }
                return lhs.showsDistance ? lhs.distanceMeters > rhs.distanceMeters : lhs.duration > rhs.duration
            }
            let water = days.map { healthKit.waterLiters(on: $0) * 1000 }.filter { $0 > 0 }
            let burned = days.map { Double(healthKit.caloriesBurned(on: $0)) }.filter { $0 > 0 }
            return HistoryMonth(
                start: start,
                days: days,
                activities: activities,
                averageWaterML: Self.roundedAverage(water),
                averageCaloriesBurned: Self.roundedAverage(burned)
            )
        }
    }

    private static func roundedAverage(_ values: [Double]) -> Int? {
        values.isEmpty ? nil : Int((values.reduce(0, +) / Double(values.count)).rounded())
    }

    private static func monthStart(of date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? Calendar.current.startOfDay(for: date)
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    PersonalRecordsView()
                } label: {
                    Label("Recordes Pessoais", systemImage: "trophy.fill")
                }
            } footer: {
                Text("Os teus melhores tempos, distâncias e treinos, a partir da app Saúde.")
            }

            if allDays.isEmpty {
                ContentUnavailableView(
                    "Sem histórico",
                    systemImage: "calendar",
                    description: Text("Os dias com registos vão aparecer aqui.")
                )
            }

            ForEach(months) { month in
                Section {
                    DisclosureGroup(isExpanded: expansionBinding(for: month.start)) {
                        ForEach(month.days, id: \.self) { day in
                            NavigationLink(value: day) {
                                dayRow(day)
                            }
                        }
                    } label: {
                        monthLabel(month)
                    }
                }
            }

            if healthKit.isSupported, !allDays.isEmpty, daysLoaded < maxDaysLoaded {
                Section {
                    Button {
                        loadMore()
                    } label: {
                        HStack {
                            Label("Carregar meses anteriores", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            if isLoadingMore { ProgressView() }
                        }
                    }
                    .disabled(isLoadingMore)
                } footer: {
                    Text("Mostra mais um ano de dados da app Saúde.")
                }
            }
        }
        .navigationTitle("Histórico")
        .trackScreen("Histórico")
        .navigationDestination(for: Date.self) { day in
            DayView(date: day)
        }
        .task {
            await healthKit.requestAuthorization()
            await healthKit.refresh(days: daysLoaded)
        }
        .refreshable {
            Haptics.light()
            await healthKit.refresh(days: daysLoaded)
        }
    }

    private func expansionBinding(for month: Date) -> Binding<Bool> {
        Binding(
            get: { expandedMonths.contains(month) },
            set: { isOpen in
                if isOpen { expandedMonths.insert(month) } else { expandedMonths.remove(month) }
            }
        )
    }

    /// The month's name and day count, then one coloured chip per sport with its monthly total.
    private func monthLabel(_ month: HistoryMonth) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(month.start.formatted(.dateTime.month(.wide).year()).capitalized)
                    .font(.headline)
                Spacer()
                Text("\(month.days.count) \(month.days.count == 1 ? "dia" : "dias")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if month.averageWaterML != nil || month.averageCaloriesBurned != nil {
                HStack(spacing: 16) {
                    if let water = month.averageWaterML {
                        Label("\(water) ml/dia", systemImage: "drop.fill")
                            .foregroundStyle(.blue)
                    }
                    if let burned = month.averageCaloriesBurned {
                        Label("\(burned) kcal/dia", systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .accessibilityLabel("Médias diárias do mês")
            }
            if month.activities.isEmpty {
                Text("Sem treinos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(month.activities) { activity in
                        activityChip(activity)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func activityChip(_ activity: ActivityTotal) -> some View {
        HStack(spacing: 6) {
            Image(systemName: activity.kind.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(activity.kind.color, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(activity.value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(activity.kind.color)
                Text("\(activity.kind.displayName) · \(activity.sessions)×")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                // Distance sports show km above, so their total time goes here; for time-based
                // ones (the gym) the time already is the main value.
                if activity.showsDistance {
                    Text(formattedWorkoutDuration(activity.duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Asks Apple Health for another year of data (up to `maxDaysLoaded`).
    private func loadMore() {
        guard !isLoadingMore, daysLoaded < maxDaysLoaded else { return }
        isLoadingMore = true
        daysLoaded = min(daysLoaded + pageSize, maxDaysLoaded)
        Task {
            await healthKit.refresh(days: daysLoaded)
            isLoadingMore = false
        }
    }

    private func dayRow(_ day: Date) -> some View {
        let hasFood = !store.entries(on: day).isEmpty
        let waterML = Int((healthKit.waterLiters(on: day) * 1000).rounded())
        let burned = healthKit.caloriesBurned(on: day)
        let coffees = healthKit.coffeeCount(on: day)
        let weight = healthKit.weightKG(on: day)
        let sleepHours = healthKit.sleepHours(on: day)
        let bodyFat = healthKit.bodyFatPercent(on: day)
        let bmi = healthKit.bmi(on: day)
        let workouts = healthKit.workouts(on: day)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                Spacer()
                if hasFood {
                    Text("\(store.totalCalories(on: day)) kcal")
                        .foregroundStyle(.secondary)
                }
            }

            if healthKit.isSupported, waterML > 0 || burned > 0 || coffees > 0 || sleepHours > 0 || !workouts.isEmpty {
                LazyVGrid(columns: Self.metricColumns, alignment: .leading, spacing: 6) {
                    if waterML > 0 {
                        Label("\(waterML) ml", systemImage: "drop.fill")
                    }
                    if burned > 0 {
                        Label("\(burned) kcal", systemImage: "flame.fill")
                    }
                    if coffees > 0 {
                        Label("\(coffees)", systemImage: "cup.and.saucer.fill")
                    }
                    if sleepHours > 0 {
                        Label(sleepHours.formatted(.number.precision(.fractionLength(1))) + " h", systemImage: "bed.double.fill")
                    }
                    if !workouts.isEmpty {
                        Label(workoutsSummary(workouts), systemImage: workouts.count == 1 ? workouts[0].kind.symbolName : "figure.run")
                            .foregroundStyle(workouts.count == 1 ? workouts[0].kind.color : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // Body measurements go on their own grid, below the daily-consumption metrics
            // above, so the two groups don't visually run into each other.
            if healthKit.isSupported, weight != nil || bodyFat != nil || bmi != nil {
                LazyVGrid(columns: Self.metricColumns, alignment: .leading, spacing: 6) {
                    if let weight {
                        Label(weight.formatted(.number.precision(.fractionLength(1))) + " kg", systemImage: "scalemass")
                    }
                    if let bodyFat {
                        Label((bodyFat * 100).formatted(.number.precision(.fractionLength(1))) + " %", systemImage: "percent")
                    }
                    if let bmi {
                        Label("IMC " + bmi.formatted(.number.precision(.fractionLength(1))), systemImage: "figure")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// "Corrida · 10,2 km", "Musculação · 1h 05m", or "3 atividades · 96 min" for several.
    private func workoutsSummary(_ workouts: [HealthKitManager.WorkoutSummary]) -> String {
        if workouts.count == 1, let workout = workouts.first {
            if workout.kind.isMeasuredByDistance, let meters = workout.distanceMeters {
                return "\(workout.kind.displayName) · \(formattedKilometres(meters))"
            }
            return "\(workout.kind.displayName) · \(formattedWorkoutDuration(workout.duration))"
        }
        let totalMinutes = Int((workouts.reduce(0) { $0 + $1.duration } / 60).rounded())
        return "\(workouts.count) atividades · \(totalMinutes) min"
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .environment(DataStore())
    .environment(HealthKitManager())
}
