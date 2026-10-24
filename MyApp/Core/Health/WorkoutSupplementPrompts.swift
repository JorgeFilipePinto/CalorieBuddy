import Foundation
import CryptoKit

/// How a workout is told apart across the app and the dashboard, and which ones still have to be asked
/// about ("Consumiste algum suplemento?"). The answer itself — com / sem suplementação — is a
/// `WorkoutSupplementAnswer` in the database (synced), found by the workout's key.
enum WorkoutSupplementPrompts {
    /// The workout's start in whole seconds since 1970: Apple Health and the platform keep the same
    /// instant, so both sides compute the same key ("w1767182400").
    static func key(for workout: HealthKitManager.WorkoutSummary) -> String {
        "w\(Int(workout.startDate.timeIntervalSince1970))"
    }

    /// A UUID made from the key (MD5 bytes), so the record for a workout has the same id wherever it is
    /// created — the app and the dashboard never end up with two answers for one workout.
    static func answerID(forKey key: String) -> UUID {
        let digest = Insecure.MD5.hash(data: Data("workout-supplement-\(key)".utf8))
        let b = Array(digest)
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// The earliest workout among `workouts` with no answer yet, or nil.
    @MainActor
    static func next(in workouts: [HealthKitManager.WorkoutSummary], store: DataStore) -> HealthKitManager.WorkoutSummary? {
        workouts.sorted { $0.startDate < $1.startDate }.first { store.supplementAnswer(for: $0) == nil }
    }
}
