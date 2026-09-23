import Foundation
import Observation
#if canImport(HealthKit) && os(iOS)
import HealthKit
#endif

/// Bridges to Apple Health so weight, body composition, sleep, water, workouts and active
/// calories burned use data that other apps (a smart scale, a sleep tracker, the Watch, the
/// Health app itself) already write, instead of a second local diary.
///
/// HealthKit only exists on iOS/iPadOS, so every real implementation below is compiled out
/// on other platforms (e.g. this project's macOS target), falling back to inert no-ops.
@Observable
final class HealthKitManager {
    /// One occasional measurement (weight, body fat %, BMI, ...) at a point in time.
    struct QuantitySample: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    /// A coarse workout category, independent of HealthKit's much larger `HKWorkoutActivityType`
    /// enum, with a Portuguese label and SF Symbol ready for display.
    enum WorkoutKind {
        case running, walking, hiking, cycling, swimming, strengthTraining, functionalTraining, yoga, elliptical, rowing, dance, other

        var displayName: String {
            switch self {
            case .running: return "Corrida"
            case .walking: return "Caminhada"
            case .hiking: return "Caminhada (Trilho)"
            case .cycling: return "Ciclismo"
            case .swimming: return "Natação"
            case .strengthTraining: return "Musculação"
            case .functionalTraining: return "Treino Funcional"
            case .yoga: return "Yoga"
            case .elliptical: return "Elíptica"
            case .rowing: return "Remo"
            case .dance: return "Dança"
            case .other: return "Atividade"
            }
        }

        var symbolName: String {
            switch self {
            case .running: return "figure.run"
            case .walking: return "figure.walk"
            case .hiking: return "figure.hiking"
            case .cycling: return "figure.outdoor.cycle"
            case .swimming: return "figure.pool.swim"
            case .strengthTraining: return "figure.strengthtraining.traditional"
            case .functionalTraining: return "figure.highintensity.intervaltraining"
            case .yoga: return "figure.yoga"
            case .elliptical: return "figure.elliptical"
            case .rowing: return "figure.rower"
            case .dance: return "figure.dance"
            case .other: return "figure.mixed.cardio"
            }
        }
    }

    /// One completed workout/activity session.
    struct WorkoutSummary: Identifiable {
        let id = UUID()
        let kind: WorkoutKind
        let startDate: Date
        let duration: TimeInterval
        let caloriesBurned: Double?
    }

    /// Litres of water logged per calendar day (key = start of day).
    private(set) var waterLitersByDay: [Date: Double] = [:]
    /// Active energy burned per calendar day, in kcal (key = start of day).
    private(set) var caloriesBurnedByDay: [Date: Double] = [:]
    /// Caffeine logged per calendar day, in mg (key = start of day).
    private(set) var caffeineMgByDay: [Date: Double] = [:]
    /// Hours asleep per calendar day (key = start of the day the sleep session started).
    private(set) var sleepHoursByDay: [Date: Double] = [:]
    /// Completed workouts per calendar day (key = start of the day the workout started).
    private(set) var workoutsByDay: [Date: [WorkoutSummary]] = [:]
    private(set) var weightHistory: [QuantitySample] = []
    private(set) var bodyFatHistory: [QuantitySample] = []
    private(set) var bmiHistory: [QuantitySample] = []
    private(set) var lastError: String?

    /// Caffeine in one "café" — a standard 50 ml Portuguese espresso — used to log and count
    /// coffees via the caffeine quantity type (HealthKit has no dedicated "cups of coffee" type).
    private let mgCaffeinePerCup: Double = 50

    var todayWaterLiters: Double { waterLiters(on: .now) }
    var latestWeightKG: Double? { weightHistory.first?.value }

    func waterLiters(on day: Date) -> Double {
        waterLitersByDay[Calendar.current.startOfDay(for: day)] ?? 0
    }

    func caloriesBurned(on day: Date) -> Int {
        Int((caloriesBurnedByDay[Calendar.current.startOfDay(for: day)] ?? 0).rounded())
    }

    func coffeeCount(on day: Date) -> Int {
        let mg = caffeineMgByDay[Calendar.current.startOfDay(for: day)] ?? 0
        return Int((mg / mgCaffeinePerCup).rounded())
    }

    func sleepHours(on day: Date) -> Double {
        sleepHoursByDay[Calendar.current.startOfDay(for: day)] ?? 0
    }

    func workouts(on day: Date) -> [WorkoutSummary] {
        workoutsByDay[Calendar.current.startOfDay(for: day)] ?? []
    }

    func totalWorkoutCalories(on day: Date) -> Int {
        Int(workouts(on: day).reduce(0) { $0 + ($1.caloriesBurned ?? 0) }.rounded())
    }

    func weightKG(on day: Date) -> Double? {
        Self.latestValue(in: weightHistory, on: day)
    }

    func bodyFatPercent(on day: Date) -> Double? {
        Self.latestValue(in: bodyFatHistory, on: day)
    }

    func bmi(on day: Date) -> Double? {
        Self.latestValue(in: bmiHistory, on: day)
    }

    private static func latestValue(in history: [QuantitySample], on day: Date) -> Double? {
        history.first { Calendar.current.isDate($0.date, inSameDayAs: day) }?.value
    }

    #if canImport(HealthKit) && os(iOS)
    private let store = HKHealthStore()
    private let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    private let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)!
    private let bmiType = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex)!
    private let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater)!
    private let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let caffeineType = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine)!
    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

    var isSupported: Bool { HKHealthStore.isHealthDataAvailable() }

    private static func workoutKind(for activityType: HKWorkoutActivityType) -> WorkoutKind {
        switch activityType {
        case .running: return .running
        case .walking: return .walking
        case .hiking: return .hiking
        case .cycling: return .cycling
        case .swimming: return .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining: return .strengthTraining
        case .highIntensityIntervalTraining, .coreTraining, .crossTraining, .mixedCardio: return .functionalTraining
        case .yoga: return .yoga
        case .elliptical: return .elliptical
        case .rowing: return .rowing
        case .cardioDance, .socialDance: return .dance
        default: return .other
        }
    }

    func requestAuthorization() async {
        guard isSupported else { return }
        do {
            try await store.requestAuthorization(
                toShare: [weightType, waterType, caffeineType],
                read: [weightType, bodyFatType, bmiType, waterType, activeEnergyType, caffeineType, sleepType, HKObjectType.workoutType()]
            )
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Refreshes weight/body-fat/BMI history plus the last `days` days of water, active-energy,
    /// caffeine, sleep and workout data. `days` can span years (the Evolução chart allows up to
    /// 2), so the daily totals use one bulk statistics-collection query per metric rather than
    /// one query per day.
    ///
    /// Callers that need a specific range (Histórico's pagination, a particular day in DayView,
    /// the Evolução chart's period picker) should always pass `days` explicitly — this default
    /// only covers simple "just refresh what I already had" calls like after logging water.
    func refresh(days: Int = 30) async {
        guard isSupported else { return }
        let historyLimit = max(30, days)
        weightHistory = await fetchQuantityHistory(for: weightType, unit: .gramUnit(with: .kilo), limit: historyLimit)
        bodyFatHistory = await fetchQuantityHistory(for: bodyFatType, unit: .percent(), limit: historyLimit)
        bmiHistory = await fetchQuantityHistory(for: bmiType, unit: .count(), limit: historyLimit)
        waterLitersByDay = await fetchDailyTotals(for: waterType, unit: .liter(), days: days)
        caloriesBurnedByDay = await fetchDailyTotals(for: activeEnergyType, unit: .kilocalorie(), days: days)
        caffeineMgByDay = await fetchDailyTotals(for: caffeineType, unit: .gramUnit(with: .milli), days: days)
        sleepHoursByDay = await fetchSleepHoursByDay(days: days)
        workoutsByDay = await fetchWorkoutsByDay(days: days)
    }

    func logWater(liters: Double) async {
        guard isSupported, liters > 0 else { return }
        let sample = HKQuantitySample(
            type: waterType,
            quantity: HKQuantity(unit: .liter(), doubleValue: liters),
            start: .now,
            end: .now
        )
        do {
            try await store.save(sample)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Logs one café (as 50mg of caffeine, HealthKit's closest equivalent quantity type).
    func logCoffee() async {
        guard isSupported else { return }
        let sample = HKQuantitySample(
            type: caffeineType,
            quantity: HKQuantity(unit: .gramUnit(with: .milli), doubleValue: mgCaffeinePerCup),
            start: .now,
            end: .now
        )
        do {
            try await store.save(sample)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Removes the most recently logged caffeine sample on `day`, i.e. undoes one café.
    /// HealthKit only allows deleting samples this app itself wrote, so this silently does
    /// nothing if the last sample on that day came from another app.
    func removeLastCoffee(on day: Date) async {
        guard isSupported else { return }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: caffeineType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .reverse)],
            limit: 1
        )
        guard let lastSample = try? await descriptor.result(for: store).first else { return }
        do {
            try await store.delete(lastSample)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func logWeight(kilograms: Double) async {
        guard isSupported, kilograms > 0 else { return }
        let sample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms),
            start: .now,
            end: .now
        )
        do {
            try await store.save(sample)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Sums `type` per calendar day, for each of the last `days` days, keyed by start of day.
    private func fetchDailyTotals(for type: HKQuantityType, unit: HKUnit, days: Int) async -> [Date: Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let anchorDate = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let rangeEnd = calendar.date(byAdding: .day, value: 1, to: today) else { return [:] }

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: nil,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                var totals: [Date: Double] = [:]
                results?.enumerateStatistics(from: anchorDate, to: rangeEnd) { statistics, _ in
                    if let sum = statistics.sumQuantity()?.doubleValue(for: unit), sum > 0 {
                        totals[calendar.startOfDay(for: statistics.startDate)] = sum
                    }
                }
                continuation.resume(returning: totals)
            }
            store.execute(query)
        }
    }

    /// The most recent occasional samples (weight, body fat %, BMI, ...) of `type`.
    private func fetchQuantityHistory(for type: HKQuantityType, unit: HKUnit, limit: Int = 30) async -> [QuantitySample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .reverse)],
            limit: limit
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { sample in
            QuantitySample(date: sample.startDate, value: sample.quantity.doubleValue(for: unit))
        }
    }

    /// Hours actually asleep (excluding "in bed"/"awake" segments) per calendar day, attributed
    /// to the day each sleep sample started on.
    private func fetchSleepHoursByDay(days: Int) async -> [Date: Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let rangeStart = calendar.date(byAdding: .day, value: -days, to: today),
              let rangeEnd = calendar.date(byAdding: .day, value: 1, to: today) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: rangeStart, end: rangeEnd)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\HKCategorySample.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [:] }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ]

        var totals: [Date: Double] = [:]
        for sample in samples where asleepValues.contains(sample.value) {
            let day = calendar.startOfDay(for: sample.startDate)
            totals[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 3600
        }
        return totals
    }

    /// Workouts (runs, gym sessions, walks, ...) over the last `days` days, grouped by the
    /// calendar day each one started on.
    private func fetchWorkoutsByDay(days: Int) async -> [Date: [WorkoutSummary]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let rangeStart = calendar.date(byAdding: .day, value: -days, to: today),
              let rangeEnd = calendar.date(byAdding: .day, value: 1, to: today) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: rangeStart, end: rangeEnd)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\HKWorkout.startDate, order: .forward)]
        )
        guard let workouts = try? await descriptor.result(for: store) else { return [:] }

        var byDay: [Date: [WorkoutSummary]] = [:]
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            let calories = workout.statistics(for: activeEnergyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let summary = WorkoutSummary(
                kind: Self.workoutKind(for: workout.workoutActivityType),
                startDate: workout.startDate,
                duration: workout.duration,
                caloriesBurned: calories
            )
            byDay[day, default: []].append(summary)
        }
        return byDay
    }
    #else
    var isSupported: Bool { false }
    func requestAuthorization() async {}
    func refresh(days: Int = 30) async {}
    func logWater(liters: Double) async {}
    func logWeight(kilograms: Double) async {}
    func logCoffee() async {}
    func removeLastCoffee(on day: Date) async {}
    #endif
}
