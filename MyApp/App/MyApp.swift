import SwiftUI

/// Shown once per cold launch, like the platform's own video landing page — not persisted, so
/// relaunching the app plays the whole sequence again instead of a one-time onboarding.
private enum AppEntryPhase {
    /// The looping video + "Continuar".
    case intro
    /// The video has closed; the IRON/MAN/PROJECT brand animation is playing. The app itself
    /// isn't mounted yet — e.g. HealthKit's permission prompt must not interrupt this.
    case brandTransition
    /// The animation finished; only the app is left on screen.
    case main
}

@main
struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = DataStore()
    @State private var healthKit = HealthKitManager()
    @State private var platformSync = PlatformSyncManager()
    @State private var entryPhase: AppEntryPhase = .intro

    var body: some Scene {
        WindowGroup {
            ZStack {
                if entryPhase == .main {
                    ContentView()
                        .environment(store)
                        .environment(healthKit)
                        .environment(platformSync)
                }

                switch entryPhase {
                case .intro:
                    IntroView {
                        entryPhase = .brandTransition
                    }
                    .transition(.identity)
                case .brandTransition:
                    LogoJoinTransitionView {
                        entryPhase = .main
                    }
                    .transition(.identity)
                case .main:
                    EmptyView()
                }
            }
            // Matches the dashboard, which is always dark (`<html class="dark">` in
            // globals.css) with the same IRONMAN red as its primary colour (AccentColor).
            .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                Task { await platformSync.autoSyncIfEnabled(store: store, healthKit: healthKit) }
            case .active:
                // Also on opening, to pick up plans the nutritionist changed on the dashboard.
                Task { await platformSync.autoSyncIfEnabled(store: store, healthKit: healthKit, minimumInterval: 15 * 60) }
            default:
                break
            }
        }
    }
}
