import SwiftUI

extension HealthKitManager.WorkoutKind {
    /// One distinct colour per activity, so the sports read apart at a glance in summaries.
    var color: Color {
        switch self {
        case .running: return .orange
        case .walking: return .yellow
        case .hiking: return .brown
        case .cycling: return .green
        case .swimming: return .cyan
        case .strengthTraining: return .purple
        case .functionalTraining: return .pink
        case .yoga: return .mint
        case .elliptical: return .indigo
        case .rowing: return .blue
        case .dance: return .red
        case .other: return .gray
        }
    }

    /// Whether this sport is summed up in kilometres (runs, rides, swims, …) rather than in time
    /// (gym and other sessions with no distance).
    var isMeasuredByDistance: Bool {
        switch self {
        case .running, .walking, .hiking, .cycling, .swimming, .rowing: return true
        case .strengthTraining, .functionalTraining, .yoga, .elliptical, .dance, .other: return false
        }
    }
}
