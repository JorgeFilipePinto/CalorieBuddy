import Foundation

/// One weigh-in with everything known about the body at that moment: the weight (Apple Health) and
/// the composition values logged the same day (a smart scale writing to Health, or the app's own log).
/// The detail screen shows a card for every value that is there, so a scale that reports more only
/// needs to fill more of these in.
struct WeighIn: Identifiable, Equatable {
    var id: UUID
    var date: Date
    var weight: Double
    /// The weight of the weigh-in before this one.
    var previousWeight: Double?
    var heightMeters: Double?

    var bodyFatPercent: Double?
    var muscleKg: Double?
    var visceralFat: Double?
    var waterPercent: Double?
    var boneKg: Double?
    var basalMetabolicRate: Double?
    var metabolicAge: Double?

    /// Not collected by the app yet: they appear as soon as a scale provides them.
    var proteinPercent: Double?
    var skeletalMusclePercent: Double?
    var subcutaneousFatPercent: Double?

    var bmi: Double? {
        guard let heightMeters, heightMeters > 0 else { return nil }
        return weight / (heightMeters * heightMeters)
    }

    var bodyFatKg: Double? { bodyFatPercent.map { weight * $0 / 100 } }
    var change: Double? { previousWeight.map { weight - $0 } }
}

@MainActor
extension DataStore {
    /// Every weight in Apple Health as a `WeighIn`, most recent first, with the composition values
    /// of the same day attached.
    func weighIns(healthKit: HealthKitManager) -> [WeighIn] {
        let calendar = Calendar.current
        let weights = healthKit.weightHistory.sorted { $0.date > $1.date }
        var readings: [BodyMetric: [BodyMetricReading]] = [:]
        for metric in BodyMetric.composition { readings[metric] = self.readings(of: metric, healthKit: healthKit) }

        /// The reading of `metric` closest in time to `date`, on the same calendar day.
        func value(_ metric: BodyMetric, near date: Date) -> Double? {
            readings[metric]?
                .filter { calendar.isDate($0.date, inSameDayAs: date) }
                .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?
                .value
        }

        return weights.enumerated().map { index, sample in
            WeighIn(
                id: sample.id,
                date: sample.date,
                weight: sample.value,
                previousWeight: index + 1 < weights.count ? weights[index + 1].value : nil,
                heightMeters: healthKit.latestHeightMeters,
                bodyFatPercent: value(.bodyFat, near: sample.date),
                muscleKg: value(.muscleMass, near: sample.date),
                visceralFat: value(.visceralFat, near: sample.date),
                waterPercent: value(.bodyWater, near: sample.date),
                boneKg: value(.boneMass, near: sample.date),
                basalMetabolicRate: value(.basalMetabolicRate, near: sample.date),
                metabolicAge: value(.metabolicAge, near: sample.date)
            )
        }
    }
}
