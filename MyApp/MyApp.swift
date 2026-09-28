import SwiftUI

@main
struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = DataStore()
    @State private var healthKit = HealthKitManager()
    @State private var cloudBackup = CloudBackupManager()

    init() {
        FirebaseSetup.configureIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(healthKit)
                .environment(cloudBackup)
                .onAppear { cloudBackup.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await cloudBackup.autoBackUpIfEnabled(store) }
            }
        }
    }
}
