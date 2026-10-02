import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    /// The day shown on "Hoje" (`nil` = today), stepped with the arrows in its title.
    @State private var selectedDay: Date?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DayView(selectedDay: $selectedDay)
            }
            .tabItem { Label("Hoje", systemImage: "sun.max") }
            .tag(0)

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("Histórico", systemImage: "calendar") }
            .tag(1)

            NavigationStack {
                FoodLibraryView()
            }
            .tabItem { Label("Alimentos", systemImage: "carrot") }
            .tag(2)

            NavigationStack {
                HealthSectionView()
            }
            .tabItem { Label("Saúde", systemImage: "heart.text.square") }
            .tag(3)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Definições", systemImage: "gearshape") }
            .tag(4)
        }
        // A light tick on every tab switch, matching the rest of the app's tactile feedback.
        .onChange(of: selectedTab) { _, _ in Haptics.selection() }
    }
}

#Preview {
    ContentView()
        .environment(DataStore())
        .environment(HealthKitManager())
        .environment(PlatformSyncManager())
}
