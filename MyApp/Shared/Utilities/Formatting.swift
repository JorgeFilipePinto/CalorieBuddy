import Foundation

/// "1h 05m" or "45 min".
func formattedWorkoutDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int((seconds / 60).rounded())
    guard minutes >= 60 else { return "\(minutes) min" }
    return "\(minutes / 60)h " + String(format: "%02dm", minutes % 60)
}

/// "42,5 km" (one decimal under 100 km, none above).
func formattedKilometres(_ meters: Double) -> String {
    let km = meters / 1000
    return km.formatted(.number.precision(.fractionLength(km < 100 ? 1 : 0))) + " km"
}

/// "1 café", "3 cafés".
func coffeesLabel(_ count: Int) -> String {
    count == 1 ? "1 café" : "\(count) cafés"
}
