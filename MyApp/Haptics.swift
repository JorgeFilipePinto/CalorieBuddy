import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Centralised haptic feedback so the app has one consistent tactile vocabulary instead of ad hoc
/// generator instances scattered around — impact weight/intensity says how "big" the moment is
/// (e.g. a tab switch vs. the intro's full-screen flash), `success`/`warning` mark an outcome.
enum Haptics {
    static func light() { impact(.light) }
    static func medium() { impact(.medium) }
    static func heavy() { impact(.heavy, intensity: 1) }
    static func selection() {
        #if canImport(UIKit) && os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
    static func success() { notification(.success) }
    static func warning() { notification(.warning) }

    private static func impact(_ style: PlatformImpactStyle, intensity: CGFloat = 1) {
        #if canImport(UIKit) && os(iOS)
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
        #endif
    }

    private static func notification(_ type: PlatformNotificationType) {
        #if canImport(UIKit) && os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(type)
        #endif
    }

    #if canImport(UIKit) && os(iOS)
    private typealias PlatformImpactStyle = UIImpactFeedbackGenerator.FeedbackStyle
    private typealias PlatformNotificationType = UINotificationFeedbackGenerator.FeedbackType
    #else
    private enum PlatformImpactStyle { case light, medium, heavy }
    private enum PlatformNotificationType { case success, warning }
    #endif
}
