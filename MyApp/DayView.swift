import SwiftUI

/// Shows all entries for a single day, with a totals header and a way to add/edit/delete entries.
/// Used both for "Hoje" (today) and for drilling into a past day from the history list.
struct DayView: View {
    @Environment(DataStore.self) private var store
    let date: Date

    @State private var showingAddEntry = false
    @State private var showingScannerEntry = false
    @State private var showingCatalogPicker = false
    @State private var showingRecipePicker = false
    @State private var entryToEdit: FoodEntry?

    private var dayEntries: [FoodEntry] {
        store.entries(on: date).sorted { $0.date < $1.date }
    }

    private var totalCalories: Int {
        dayEntries.reduce(0) { $0 + $1.calories }
    }

    private var goal: Int { store.settings.dailyCalorieGoal }

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(totalCalories) / Double(goal), 1)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(totalCalories) kcal")
                            .font(.title2.bold())
                        Spacer()
                        Text("Objetivo: \(goal) kcal")
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: progress)
                        .tint(totalCalories > goal ? .red : .accentColor)
                }
                .padding(.vertical, 4)
            }

            ForEach(MealType.allCases) { meal in
                let mealEntries = dayEntries.filter { $0.mealType == meal }
                if !mealEntries.isEmpty {
                    Section {
                        ForEach(mealEntries) { entry in
                            Button {
                                entryToEdit = entry
                            } label: {
                                entryRow(entry)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                store.deleteEntry(mealEntries[index])
                            }
                        }
                    } header: {
                        HStack {
                            Label(meal.displayName, systemImage: meal.symbolName)
                            Spacer()
                            Text("\(mealEntries.reduce(0) { $0 + $1.calories }) kcal")
                        }
                    }
                }
            }

            if dayEntries.isEmpty {
                ContentUnavailableView(
                    "Sem registos",
                    systemImage: "fork.knife",
                    description: Text("Adiciona o que comeste neste dia.")
                )
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddEntry = true
                    } label: {
                        Label("Registo Manual", systemImage: "square.and.pencil")
                    }
                    Button {
                        showingScannerEntry = true
                    } label: {
                        Label("Digitalizar Código de Barras", systemImage: "barcode.viewfinder")
                    }
                    Button {
                        showingCatalogPicker = true
                    } label: {
                        Label("Do Catálogo", systemImage: "tray.full")
                    }
                    Button {
                        showingRecipePicker = true
                    } label: {
                        Label("Registar Receita", systemImage: "list.bullet.rectangle")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            AddEntryView(defaultDate: date)
        }
        .sheet(isPresented: $showingScannerEntry) {
            AddEntryView(defaultDate: date, startWithScanner: true)
        }
        .sheet(isPresented: $showingCatalogPicker) {
            CatalogPickerView(date: date)
        }
        .sheet(isPresented: $showingRecipePicker) {
            RecipePickerView(date: date)
        }
        .sheet(item: $entryToEdit) { entry in
            AddEntryView(entryToEdit: entry)
        }
    }

    private var title: String {
        Calendar.current.isDateInToday(date) ? "Hoje" : date.formatted(date: .abbreviated, time: .omitted)
    }

    private func entryRow(_ entry: FoodEntry) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.name)
                HStack(spacing: 4) {
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                    if let groupName = entry.groupName {
                        Text("· \(groupName)")
                    }
                    if entry.barcode != nil {
                        Image(systemName: "barcode")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(entry.calories) kcal")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        DayView(date: .now)
    }
    .environment(DataStore())
}
