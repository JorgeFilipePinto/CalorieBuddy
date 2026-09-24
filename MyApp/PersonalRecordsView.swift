import SwiftUI

/// Personal records computed from Apple Health workouts. Kept free of HealthKit so the maths can
/// be reasoned about (and tested) on its own.
enum PersonalRecords {
    /// Standard distances (m) whose fastest time is tracked per sport — the usual race
    /// distances, including the Ironman 70.3 and full legs.
    static func bestEffortDistances(for kind: HealthKitManager.WorkoutKind) -> [Double] {
        switch kind {
        case .running: return [1000, 5000, 10000, 21097.5, 42195]
        case .cycling: return [10000, 20000, 40000, 90000, 180000]
        case .swimming: return [100, 400, 750, 1000, 1500, 1900, 3800]
        default: return []
        }
    }

    static func bestEffortName(_ distance: Double, kind: HealthKitManager.WorkoutKind) -> String {
        switch (kind, distance) {
        case (.running, 21097.5): return "Meia Maratona"
        case (.running, 42195): return "Maratona"
        case (.cycling, 90000), (.swimming, 1900): return formattedDistance(distance) + " (70.3)"
        case (.cycling, 180000), (.swimming, 3800): return formattedDistance(distance) + " (Ironman)"
        default: return formattedDistance(distance)
        }
    }

    /// "750 m", "1,9 km", "40 km".
    static func formattedDistance(_ meters: Double) -> String {
        guard meters >= 1000 else { return "\(Int(meters)) m" }
        return (meters / 1000).formatted(.number.precision(.fractionLength(0...1))) + " km"
    }

    /// Fastest time to cover each of `targets` metres within one workout. `times[i]` is when the
    /// athlete had covered `cumulativeDistances[i]` metres (both ascending, starting at 0 m).
    /// Uses the shortest window of consecutive samples that reaches the target, scaled down to
    /// exactly the target distance.
    static func bestEfforts(times: [Double], cumulativeDistances: [Double], targets: [Double]) -> [Double: TimeInterval] {
        guard times.count == cumulativeDistances.count, times.count > 1 else { return [:] }
        var result: [Double: TimeInterval] = [:]
        for target in targets {
            var best: TimeInterval?
            var start = 0
            for end in 1..<cumulativeDistances.count {
                // Move the window's start forward as long as it still covers the target.
                while start + 1 < end, cumulativeDistances[end] - cumulativeDistances[start + 1] >= target {
                    start += 1
                }
                let covered = cumulativeDistances[end] - cumulativeDistances[start]
                guard covered >= target, covered > 0 else { continue }
                let time = (times[end] - times[start]) * target / covered
                if time > 0, best.map({ time < $0 }) ?? true {
                    best = time
                }
            }
            if let best { result[target] = best }
        }
        return result
    }

    /// A record value and the day it was set on.
    struct Mark {
        let value: Double
        let date: Date
    }

    /// Every record for one kind of workout.
    struct KindRecords: Identifiable {
        let kind: HealthKitManager.WorkoutKind
        let workoutCount: Int
        let totalDistance: Double
        let totalDuration: TimeInterval
        /// Fastest time (s) per standard distance (m) — runs, rides and swims.
        let bestEfforts: [(distance: Double, mark: Mark)]
        let longestDistance: Mark?
        let longestDuration: Mark?
        /// Highest average speed (m/s), among workouts long enough for it to be meaningful.
        let fastestAverageSpeed: Mark?
        let mostCalories: Mark?

        var id: HealthKitManager.WorkoutKind { kind }
    }

    /// Minimum distance (m) for a workout's average speed to count as a record, so a 200 m
    /// accidental start doesn't become the "fastest run".
    static func minimumDistanceForSpeed(_ kind: HealthKitManager.WorkoutKind) -> Double {
        switch kind {
        case .cycling: return 5000
        case .swimming: return 100
        case .rowing: return 500
        default: return 1000
        }
    }

    /// Records per workout kind, for workouts that started on or after `since` (all, if `nil`),
    /// ordered as `WorkoutKind.allCases`.
    static func records(from workouts: [HealthKitManager.RecordWorkout], since: Date?) -> [KindRecords] {
        let filtered = workouts.filter { since == nil || $0.startDate >= since! }
        let byKind = Dictionary(grouping: filtered, by: \.kind)
        return HealthKitManager.WorkoutKind.allCases.compactMap { kind in
            guard let group = byKind[kind], !group.isEmpty else { return nil }

            func best(_ value: (HealthKitManager.RecordWorkout) -> Double?, lowest: Bool = false) -> Mark? {
                group.compactMap { workout in value(workout).map { Mark(value: $0, date: workout.startDate) } }
                    .min { lowest ? $0.value < $1.value : $0.value > $1.value }
            }

            let efforts = bestEffortDistances(for: kind).compactMap { distance in
                best({ $0.bestEfforts[distance] }, lowest: true).map { (distance: distance, mark: $0) }
            }
            let minimumDistance = minimumDistanceForSpeed(kind)
            return KindRecords(
                kind: kind,
                workoutCount: group.count,
                totalDistance: group.reduce(0) { $0 + ($1.distanceMeters ?? 0) },
                totalDuration: group.reduce(0) { $0 + $1.duration },
                bestEfforts: efforts,
                longestDistance: best { $0.distanceMeters },
                longestDuration: best { $0.duration > 0 ? $0.duration : nil },
                fastestAverageSpeed: best { workout in
                    guard let distance = workout.distanceMeters, distance >= minimumDistance, workout.duration > 0 else { return nil }
                    return distance / workout.duration
                },
                mostCalories: best { $0.caloriesBurned.flatMap { $0 > 0 ? $0 : nil } }
            )
        }
    }
}

// MARK: - Triathlon prediction

extension PersonalRecords {
    enum TriathlonRace: CaseIterable, Identifiable {
        case half, full

        var id: Self { self }

        var name: String {
            switch self {
            case .half: return "Ironman 70.3"
            case .full: return "Ironman"
            }
        }

        /// Swim, bike and run distances (m).
        var legs: [(kind: HealthKitManager.WorkoutKind, distance: Double)] {
            switch self {
            case .half: return [(.swimming, 1900), (.cycling, 90000), (.running, 21097.5)]
            case .full: return [(.swimming, 3800), (.cycling, 180000), (.running, 42195)]
            }
        }

        /// How much slower the run is off the bike than a standalone run of the same distance.
        var runFatigueFactor: Double {
            switch self {
            case .half: return 1.08
            case .full: return 1.18
            }
        }

        /// Typical T1 + T2 for an age-grouper.
        var transitions: TimeInterval {
            switch self {
            case .half: return 6 * 60
            case .full: return 10 * 60
            }
        }
    }

    struct PredictedLeg: Identifiable {
        let kind: HealthKitManager.WorkoutKind
        let distance: Double
        /// `nil` when there's no best effort for this sport to base it on.
        let time: TimeInterval?
        /// The best effort the prediction was extrapolated from.
        let basedOn: Basis?

        var id: HealthKitManager.WorkoutKind { kind }
    }

    /// A best effort a prediction is based on.
    struct Basis {
        let distance: Double
        let time: TimeInterval
        let date: Date
        /// Whether it was set within `recentEffortDays` — if not, no recent effort existed at
        /// the target distance or below.
        let isRecent: Bool
    }

    struct TriathlonPrediction: Identifiable {
        let race: TriathlonRace
        let legs: [PredictedLeg]

        var id: TriathlonRace { race }

        /// Total including transitions, or `nil` if any leg couldn't be predicted.
        var total: TimeInterval? {
            let times = legs.compactMap(\.time)
            guard times.count == legs.count else { return nil }
            return times.reduce(race.transitions, +)
        }
    }

    /// Riegel's endurance formula: time over `distance` given `time` over `baseDistance`.
    static func riegel(time: TimeInterval, baseDistance: Double, distance: Double, exponent: Double = 1.06) -> TimeInterval {
        time * pow(distance / baseDistance, exponent)
    }

    /// Standalone running races predicted on their own (fresh, not off the bike).
    static let runningRaceDistances: [Double] = [21097.5, 42195]

    /// How recent (days) a best effort must be to reflect current fitness.
    static let recentEffortDays = 30

    /// Predicts `distance` metres of `kind`, via Riegel's formula, multiplied by `fatigueFactor`.
    ///
    /// Only efforts at the target distance or below are used, from the longest down: the first
    /// one set within the last `recentEffortDays` days wins — so an effort at the target
    /// distance itself is used only while it's recent, otherwise the next distance below is
    /// tried, and so on. If none is recent, the longest effort at or below the target is used
    /// regardless of age (flagged as not recent).
    static func predictLeg(
        _ kind: HealthKitManager.WorkoutKind,
        distance: Double,
        from workouts: [HealthKitManager.RecordWorkout],
        now: Date = .now,
        fatigueFactor: Double = 1
    ) -> PredictedLeg {
        let cutoff = Calendar.current.date(byAdding: .day, value: -recentEffortDays, to: now) ?? now
        let ladder = bestEffortDistances(for: kind).filter { $0 <= distance }.sorted(by: >)

        /// Fastest effort at `effortDistance` among workouts that started on or after `since`.
        func fastest(at effortDistance: Double, since: Date?) -> (time: TimeInterval, date: Date)? {
            workouts
                .filter { $0.kind == kind && (since == nil || $0.startDate >= since!) }
                .compactMap { workout in workout.bestEfforts[effortDistance].map { ($0, workout.startDate) } }
                .min { $0.0 < $1.0 }
        }

        let basis: Basis? = ladder.lazy.compactMap { effortDistance in
            fastest(at: effortDistance, since: cutoff).map { Basis(distance: effortDistance, time: $0.time, date: $0.date, isRecent: true) }
        }.first ?? ladder.lazy.compactMap { effortDistance in
            fastest(at: effortDistance, since: nil).map { Basis(distance: effortDistance, time: $0.time, date: $0.date, isRecent: false) }
        }.first

        guard let basis else {
            return PredictedLeg(kind: kind, distance: distance, time: nil, basedOn: nil)
        }
        let time = riegel(time: basis.time, baseDistance: basis.distance, distance: distance) * fatigueFactor
        return PredictedLeg(kind: kind, distance: distance, time: time, basedOn: basis)
    }

    /// Predicts each leg of `race`, with the run slowed down by the race's fatigue factor.
    static func predict(_ race: TriathlonRace, from workouts: [HealthKitManager.RecordWorkout], now: Date = .now) -> TriathlonPrediction {
        let legs = race.legs.map { leg in
            predictLeg(leg.kind, distance: leg.distance, from: workouts, now: now, fatigueFactor: leg.kind == .running ? race.runFatigueFactor : 1)
        }
        return TriathlonPrediction(race: race, legs: legs)
    }
}

/// Personal records from every workout in Apple Health — best running efforts, longest and
/// fastest sessions and most calories — per sport, for a chosen period. Each record opens the
/// day it was set on.
struct PersonalRecordsView: View {
    @Environment(HealthKitManager.self) private var healthKit

    private enum Period: String, CaseIterable, Identifiable {
        case allTime, last12Months, thisYear

        var id: String { rawValue }

        var label: String {
            switch self {
            case .allTime: return "Sempre"
            case .last12Months: return "12 Meses"
            case .thisYear: return "Este Ano"
            }
        }

        var since: Date? {
            let calendar = Calendar.current
            switch self {
            case .allTime: return nil
            case .last12Months: return calendar.date(byAdding: .year, value: -1, to: .now)
            case .thisYear: return calendar.dateInterval(of: .year, for: .now)?.start
            }
        }
    }

    @State private var period: Period = .allTime

    private var records: [PersonalRecords.KindRecords] {
        PersonalRecords.records(from: healthKit.recordWorkouts, since: period.since)
    }

    var body: some View {
        List {
            if !healthKit.recordWorkouts.isEmpty {
                runningPredictionSection

                ForEach(PersonalRecords.TriathlonRace.allCases) { race in
                    predictionSection(PersonalRecords.predict(race, from: healthKit.recordWorkouts))
                }
            }

            Section {
                Picker("Período", selection: $period) {
                    ForEach(Period.allCases) { period in
                        Text(period.label).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Recordes")
            }

            ForEach(records) { kindRecords in
                kindSection(kindRecords)
            }
        }
        .navigationTitle("Recordes Pessoais")
        .overlay {
            if healthKit.isLoadingRecords && healthKit.recordWorkouts.isEmpty {
                ProgressView("A calcular recordes…")
            } else if !healthKit.isSupported {
                ContentUnavailableView(
                    "Saúde indisponível",
                    systemImage: "heart.slash",
                    description: Text("Os recordes são calculados a partir dos treinos da app Saúde.")
                )
            } else if records.isEmpty && !healthKit.isLoadingRecords {
                ContentUnavailableView(
                    "Sem treinos",
                    systemImage: "trophy",
                    description: Text("Ainda não há treinos na app Saúde neste período.")
                )
            }
        }
        .task {
            await healthKit.requestAuthorization()
            await healthKit.loadRecordWorkouts()
        }
        .refreshable {
            await healthKit.loadRecordWorkouts()
        }
    }

    @ViewBuilder
    private func kindSection(_ records: PersonalRecords.KindRecords) -> some View {
        let kind = records.kind
        if !records.bestEfforts.isEmpty {
            Section {
                ForEach(records.bestEfforts, id: \.distance) { effort in
                    recordRow(
                        PersonalRecords.bestEffortName(effort.distance, kind: kind),
                        value: Self.duration(effort.mark.value),
                        detail: Self.pace(metersPerSecond: effort.distance / effort.mark.value, kind: kind),
                        date: effort.mark.date,
                        systemImage: "stopwatch"
                    )
                }
            } header: {
                Label("\(kind.displayName) · Melhores Marcas", systemImage: "trophy.fill")
            } footer: {
                Text("Tempo mais rápido em cada distância dentro de qualquer treino, calculado a partir dos dados de distância registados durante o treino.")
            }
        }

        Section {
            if let mark = records.longestDistance {
                recordRow("Maior distância", value: Self.distance(mark.value, kind: kind), date: mark.date, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            if let mark = records.longestDuration {
                recordRow("Treino mais longo", value: Self.duration(mark.value), date: mark.date, systemImage: "clock")
            }
            if let mark = records.fastestAverageSpeed {
                recordRow(
                    kind == .cycling ? "Velocidade média mais alta" : "Ritmo médio mais rápido",
                    value: Self.pace(metersPerSecond: mark.value, kind: kind),
                    date: mark.date,
                    systemImage: "speedometer"
                )
            }
            if let mark = records.mostCalories {
                recordRow("Mais calorias", value: "\(Int(mark.value.rounded())) kcal", date: mark.date, systemImage: "flame.fill")
            }
        } header: {
            HStack {
                Label(kind.displayName, systemImage: kind.symbolName)
                Spacer()
                Text(sectionSummary(records))
            }
        }
    }

    private var runningPredictionSection: some View {
        Section {
            ForEach(PersonalRecords.runningRaceDistances, id: \.self) { distance in
                let leg = PersonalRecords.predictLeg(.running, distance: distance, from: healthKit.recordWorkouts)
                predictedLegRow(leg, title: PersonalRecords.bestEffortName(distance, kind: .running))
            }
        } header: {
            Label("Previsão Corrida", systemImage: "figure.run")
        } footer: {
            Text(Self.predictionBasisNote + " Pressupõe condições de prova e preparação adequada para a distância.")
        }
    }

    /// One predicted distance: its time and pace, and which best effort it was based on.
    private func predictedLegRow(_ leg: PersonalRecords.PredictedLeg, title: String) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let basedOn = leg.basedOn {
                        Text("Com base nos teus \(PersonalRecords.formattedDistance(basedOn.distance)) em \(Self.duration(basedOn.time)) · \(basedOn.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !basedOn.isRecent {
                            Label("Sem marcas nos últimos \(PersonalRecords.recentEffortDays) dias", systemImage: "clock.badge.exclamationmark")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Text("Sem treinos de \(leg.kind.displayName.lowercased()) com distância")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } icon: {
                Image(systemName: leg.kind.symbolName)
            }
            Spacer()
            if let time = leg.time {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Self.duration(time))
                        .monospacedDigit()
                    Text(Self.pace(metersPerSecond: leg.distance / time, kind: leg.kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    private func predictionSection(_ prediction: PersonalRecords.TriathlonPrediction) -> some View {
        let race = prediction.race
        return Section {
            HStack {
                Text("Tempo previsto")
                Spacer()
                if let total = prediction.total {
                    Text(Self.duration(total))
                        .font(.title3.bold())
                        .monospacedDigit()
                } else {
                    Text("Faltam dados")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(prediction.legs) { leg in
                predictedLegRow(leg, title: "\(leg.kind.displayName) · \(PersonalRecords.formattedDistance(leg.distance))")
            }
            LabeledContent("Transições (T1 + T2)", value: "~\(Int(race.transitions / 60)) min")
        } header: {
            Label("Previsão \(race.name)", systemImage: "medal.fill")
        } footer: {
            Text(Self.predictionBasisNote + " A corrida fica \(Int(((race.runFatigueFactor - 1) * 100).rounded()))% mais lenta pelo cansaço da bicicleta. Não considera percurso, calor, vento nem nutrição em prova.")
        }
    }

    static let predictionBasisNote = "Usa a marca da própria distância só se tiver no máximo \(PersonalRecords.recentEffortDays) dias; caso contrário, a da distância abaixo mais recente, extrapolada com a fórmula de Riegel. Não depende do período escolhido."

    private func sectionSummary(_ records: PersonalRecords.KindRecords) -> String {
        var parts = ["\(records.workoutCount) \(records.workoutCount == 1 ? "treino" : "treinos")"]
        if records.totalDistance > 0 {
            parts.append(Self.distance(records.totalDistance, kind: records.kind))
        } else {
            parts.append("\(Int((records.totalDuration / 3600).rounded())) h")
        }
        return parts.joined(separator: " · ")
    }

    private func recordRow(_ title: String, value: String, detail: String? = nil, date: Date, systemImage: String) -> some View {
        NavigationLink(value: Calendar.current.startOfDay(for: date)) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(.orange)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.body.bold())
                        .monospacedDigit()
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Formatting

    /// "42:07" or "1:38:45".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// Swimming in metres, everything else in km.
    static func distance(_ meters: Double, kind: HealthKitManager.WorkoutKind) -> String {
        if kind == .swimming {
            return "\(Int(meters.rounded())) m"
        }
        return (meters / 1000).formatted(.number.precision(.fractionLength(meters >= 100_000 ? 0 : 2))) + " km"
    }

    /// km/h for cycling, min/100 m for swimming and rowing (per 500 m), min/km otherwise.
    static func pace(metersPerSecond speed: Double, kind: HealthKitManager.WorkoutKind) -> String {
        guard speed > 0 else { return "—" }
        switch kind {
        case .cycling:
            return (speed * 3.6).formatted(.number.precision(.fractionLength(1))) + " km/h"
        case .swimming:
            return duration(100 / speed) + " /100 m"
        case .rowing:
            return duration(500 / speed) + " /500 m"
        default:
            return duration(1000 / speed) + " /km"
        }
    }
}

#Preview {
    NavigationStack {
        PersonalRecordsView()
    }
    .environment(HealthKitManager())
}
