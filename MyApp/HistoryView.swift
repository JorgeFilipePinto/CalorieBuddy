import SwiftUI

struct HistoryView: View {
    @Environment(DataStore.self) private var store

    var body: some View {
        List(store.allDays, id: \.self) { day in
            NavigationLink(value: day) {
                HStack {
                    Text(day.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    Text("\(store.totalCalories(on: day)) kcal")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Histórico")
        .navigationDestination(for: Date.self) { day in
            DayView(date: day)
        }
        .overlay {
            if store.allDays.isEmpty {
                ContentUnavailableView(
                    "Sem histórico",
                    systemImage: "calendar",
                    description: Text("Os dias com registos vão aparecer aqui.")
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .environment(DataStore())
}
