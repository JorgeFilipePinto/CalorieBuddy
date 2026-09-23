import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DayView(date: .now)
            }
            .tabItem { Label("Hoje", systemImage: "sun.max") }

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("Histórico", systemImage: "calendar") }

            NavigationStack {
                FoodLibraryView()
            }
            .tabItem { Label("Alimentos", systemImage: "carrot") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Definições", systemImage: "gearshape") }
        }
    }
}

#Preview {
    ContentView()
        .environment(DataStore())
}
