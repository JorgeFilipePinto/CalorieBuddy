import SwiftUI

struct HistoryView: View {
    @Environment(DataStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit

    /// How many days back of Apple Health data have been requested so far. Starts small and
    /// grows as the user scrolls, instead of eagerly fetching a huge range up front.
    @State private var daysLoaded = 30
    @State private var isLoadingMore = false

    private let pageSize = 60
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

            ForEach(allDays, id: \.self) { day in
                NavigationLink(value: day) {
                    dayRow(day)
                }
                .onAppear {
                    if day == allDays.last {
                        loadMoreIfNeeded()
                    }
                }
            }

            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .navigationTitle("Histórico")
        .navigationDestination(for: Date.self) { day in
            DayView(date: day)
        }
        .task {
            await healthKit.requestAuthorization()
            await healthKit.refresh(days: daysLoaded)
        }
        .refreshable {
            await healthKit.refresh(days: daysLoaded)
        }
    }

    /// Fetches another page of older Apple Health data once the last visible row appears,
    /// i.e. the user has scrolled to the bottom of what's currently loaded.
    private func loadMoreIfNeeded() {
        guard !isLoadingMore, daysLoaded < maxDaysLoaded, healthKit.isSupported else { return }
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
                Text(day.formatted(date: .abbreviated, time: .omitted))
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

    /// "Corrida · 32 min" for a single workout, or "3 atividades · 96 min" for several.
    private func workoutsSummary(_ workouts: [HealthKitManager.WorkoutSummary]) -> String {
        if workouts.count == 1, let workout = workouts.first {
            let minutes = Int((workout.duration / 60).rounded())
            return "\(workout.kind.displayName) · \(minutes) min"
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
