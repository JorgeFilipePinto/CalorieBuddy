import SwiftUI

@main
struct MyApp: App {
    @State private var store = DataStore()
    @State private var healthKit = HealthKitManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(healthKit)
        }
    }
}
