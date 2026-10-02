import SwiftUI

/// Shows all entries for a single day, with a totals header and a way to add/edit/delete entries.
/// Used both for "Hoje" (today) and for drilling into a past day from the history list.
struct DayView: View {
    @Environment(DataStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    let date: Date
    /// Only on the "Hoje" tab: the day being shown, `nil` meaning today (so it keeps following
    /// the calendar past midnight). When set, the title gets ‹ › arrows to step between days.
    private let selectedDay: Binding<Date?>?

    /// A fixed day, e.g. opened from the history list.
    init(date: Date) {
        self.date = date
        self.selectedDay = nil
    }

    /// The "Hoje" tab: starts on today and can step back through previous days.
    init(selectedDay: Binding<Date?>) {
        self.date = selectedDay.wrappedValue ?? .now
        self.selectedDay = selectedDay
    }

    @State private var showingAddEntry = false
    @State private var showingScannerEntry = false
    @State private var showingCatalogPicker = false
    @State private var showingRecipePicker = false
    @State private var showingMealPlanPicker = false
    @State private var showingSupplementPicker = false
    @State private var showingJSONImport = false
    @State private var jsonImportGroupName = ""
    @State private var jsonImportMealType: MealType = .lunch
    @State private var entryToEdit: FoodEntry?

    private var dayEntries: [FoodEntry] {
        store.entries(on: date).sorted { $0.date < $1.date }
    }

    private var daySupplementLogs: [SupplementLogEntry] {
        store.supplementLogs(on: date).sorted { $0.date < $1.date }
    }

    private var dayWorkouts: [HealthKitManager.WorkoutSummary] {
        healthKit.workouts(on: date)
    }

    private var totalCalories: Int {
        dayEntries.reduce(0) { $0 + $1.calories } + store.totalSupplementCalories(on: date)
    }

    private var totalProtein: Double {
        dayEntries.reduce(0) { $0 + ($1.protein ?? 0) } + store.totalSupplementProtein(on: date)
    }

    private var totalCarbs: Double {
        dayEntries.reduce(0) { $0 + ($1.carbs ?? 0) } + store.totalSupplementCarbs(on: date)
    }

    private var totalFat: Double {
        dayEntries.reduce(0) { $0 + ($1.fat ?? 0) } + store.totalSupplementFat(on: date)
    }

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    /// A day counts as `training` when it has at least one logged workout — the same rule the
    /// dashboard uses to pick which of the active plan's target sets applies.
    private var dayType: DayType { dayWorkouts.isEmpty ? .rest : .training }

    private var activeTargets: NutritionTargets? {
        guard let plan = store.nutritionPlan(on: date) else { return nil }
        return dayType == .training ? plan.training : plan.rest
    }

    private var goal: Int { activeTargets?.kcal ?? store.settings.dailyCalorieGoal }

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
                        // Accent (IRONMAN red) while on track; a distinct warning colour once
                        // over — reusing .red here would read the same as the on-track colour.
                        .tint(totalCalories > goal ? .orange : .accentColor)

                    HStack(spacing: 16) {
                        macroTile(title: "Proteína", value: totalProtein, goal: activeTargets.map { Double($0.proteinG) } ?? store.settings.proteinGoal, color: .blue)
                        macroTile(title: "Hidratos", value: totalCarbs, goal: activeTargets.map { Double($0.carbsG) } ?? store.settings.carbsGoal, color: .orange)
                        macroTile(title: "Gordura", value: totalFat, goal: activeTargets.map { Double($0.fatG) } ?? store.settings.fatGoal, color: .pink)
                    }
                    .padding(.top, 4)

                    if healthKit.isSupported {
                        Divider()
                        waterRow
                        if healthKit.caloriesBurned(on: date) > 0 {
                            burnedRow
                        }
                        if isToday {
                            coffeeStepperRow
                        } else if healthKit.coffeeCount(on: date) > 0 {
                            coffeeRow
                        }
                        if healthKit.sleepHours(on: date) > 0 {
                            sleepRow
                        }
                        if healthKit.weightKG(on: date) != nil
                            || healthKit.bodyFatPercent(on: date) != nil
                            || healthKit.bmi(on: date) != nil {
                            Divider()
                            bodyMeasurementsRow
                        }
                    }
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

            if !daySupplementLogs.isEmpty {
                Section {
                    ForEach(daySupplementLogs) { log in
                        supplementLogRow(log)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            store.deleteSupplementLog(daySupplementLogs[index])
                        }
                    }
                } header: {
                    HStack {
                        Label("Suplementos", systemImage: "pills.fill")
                        Spacer()
                        Text("\(store.totalSupplementCalories(on: date)) kcal")
                    }
                }
            }

            if !dayWorkouts.isEmpty {
                Section {
                    ForEach(dayWorkouts) { workout in
                        workoutRow(workout)
                    }
                } header: {
                    HStack {
                        Label("Atividades", systemImage: "figure.run")
                        Spacer()
                        if healthKit.totalWorkoutCalories(on: date) > 0 {
                            Text("\(healthKit.totalWorkoutCalories(on: date)) kcal")
                        }
                    }
                }
            }

            if dayEntries.isEmpty && daySupplementLogs.isEmpty && dayWorkouts.isEmpty {
                ContentUnavailableView(
                    "Sem registos",
                    systemImage: "fork.knife",
                    description: Text("Adiciona o que comeste neste dia.")
                )
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(selectedDay == nil ? .automatic : .inline)
        #endif
        .trackScreen(isToday ? "Hoje" : "Dia")
        .onChange(of: selectedDay?.wrappedValue) {
            Task { await healthKit.refresh(days: daysNeededToCoverDate) }
        }
        .toolbar {
            if let selectedDay {
                ToolbarItem(placement: .principal) {
                    dayNavigator(selectedDay)
                }
            }
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
                        showingMealPlanPicker = true
                    } label: {
                        Label("Do Plano Alimentar", systemImage: "list.clipboard")
                    }
                    Button {
                        showingRecipePicker = true
                    } label: {
                        Label("Registar Receita", systemImage: "list.bullet.rectangle")
                    }
                    Button {
                        showingSupplementPicker = true
                    } label: {
                        Label("Suplemento", systemImage: "pills.fill")
                    }
                    Button {
                        jsonImportGroupName = ""
                        jsonImportMealType = MealType.suggested(for: date)
                        showingJSONImport = true
                    } label: {
                        Label("Importar JSON (IA)", systemImage: "sparkles")
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
            ScanAndLogEntryView(date: date)
        }
        .sheet(isPresented: $showingCatalogPicker) {
            CatalogPickerView(date: date)
        }
        .sheet(isPresented: $showingRecipePicker) {
            RecipePickerView(date: date)
        }
        .sheet(isPresented: $showingMealPlanPicker) {
            MealPlanPickerView(date: date)
        }
        .sheet(isPresented: $showingSupplementPicker) {
            SupplementPickerView(date: date)
        }
        .sheet(item: $entryToEdit) { entry in
            AddEntryView(entryToEdit: entry)
        }
        .sheet(isPresented: $showingJSONImport) {
            JSONImportSheet(
                title: "Importar Registo",
                prompt: AIJSONImport.diaryPrompt,
                instructions: "Útil para refeições sem rótulo (comida caseira, restaurante) — a IA também aceita uma foto do prato. Cada alimento ou prato da resposta é registado nesta refeição.",
                additionalFields: {
                    Section("Refeição") {
                        TextField("Nome (ex.: Almoço fora)", text: $jsonImportGroupName)
                        Picker("Tipo de Refeição", selection: $jsonImportMealType) {
                            ForEach(MealType.allCases) { meal in
                                Label(meal.displayName, systemImage: meal.symbolName).tag(meal)
                            }
                        }
                    }
                },
                isReadyToImport: {
                    !jsonImportGroupName.trimmingCharacters(in: .whitespaces).isEmpty
                }
            ) { json in
                try handleDiaryJSONImport(json)
            }
        }
        .onAppear {
            Task {
                await healthKit.requestAuthorization()
                await healthKit.refresh(days: daysNeededToCoverDate)
            }
        }
        .refreshable {
            Haptics.light()
            await healthKit.refresh(days: daysNeededToCoverDate)
        }
    }

    /// Enough days for a Health refresh to include `date`, even when it's further back than
    /// whatever range Histórico's pagination has loaded so far.
    private var daysNeededToCoverDate: Int {
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        return max(30, days + 1)
    }

    private var title: String {
        isToday ? "Hoje" : date.formatted(date: .abbreviated, time: .omitted)
    }

    /// "Hoje", "Ontem" or e.g. "segunda-feira, 28 set." — what the title arrows step through.
    private var navigatorTitle: String {
        if isToday { return "Hoje" }
        if Calendar.current.isDateInYesterday(date) { return "Ontem" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    /// ‹ day › in the navigation bar. There's no stepping into the future; tapping the day name
    /// jumps back to today.
    private func dayNavigator(_ selectedDay: Binding<Date?>) -> some View {
        HStack(spacing: 20) {
            Button {
                step(selectedDay, by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Dia anterior")

            Button {
                guard !isToday else { return }
                selectedDay.wrappedValue = nil
                Haptics.selection()
            } label: {
                VStack(spacing: 0) {
                    Text(navigatorTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if !isToday {
                        Text("Toca para voltar a hoje")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 150)
            }
            .buttonStyle(.plain)

            Button {
                step(selectedDay, by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(isToday)
            .accessibilityLabel("Dia seguinte")
        }
        .font(.headline)
    }

    private func step(_ selectedDay: Binding<Date?>, by days: Int) {
        let calendar = Calendar.current
        guard let target = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) else { return }
        selectedDay.wrappedValue = calendar.isDateInToday(target) || target > .now ? nil : target
        Haptics.selection()
    }

    private func macroTile(title: String, value: Double, goal: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let goal, goal > 0 {
                Text("\(Int(value.rounded()))/\(Int(goal.rounded())) g")
                    .font(.subheadline.bold())
                ProgressView(value: min(value / goal, 1))
                    .tint(color)
            } else {
                Text("\(Int(value.rounded())) g")
                    .font(.subheadline.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var waterRow: some View {
        let waterML = Int((healthKit.waterLiters(on: date) * 1000).rounded())
        let goal = activeTargets?.waterML ?? store.settings.dailyWaterGoalML
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("\(waterML) ml", systemImage: "drop.fill")
                    .foregroundStyle(.blue)
                Spacer()
                if let goal {
                    Text("Objetivo: \(goal) ml")
                        .foregroundStyle(waterML >= goal ? .green : .secondary)
                }
            }
            if let goal, goal > 0 {
                ProgressView(value: min(Double(waterML) / Double(goal), 1))
                    .tint(.blue)
            }
        }
    }

    private var burnedRow: some View {
        let burned = healthKit.caloriesBurned(on: date)
        let remaining = goal - totalCalories + burned
        return HStack {
            Label("\(burned) kcal queimadas", systemImage: "flame.fill")
                .foregroundStyle(.orange)
            Spacer()
            Text("Restam: \(remaining) kcal")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private var coffeeRow: some View {
        Label(coffeesLabel(healthKit.coffeeCount(on: date)), systemImage: "cup.and.saucer.fill")
            .foregroundStyle(.brown)
            .font(.subheadline)
    }

    private var sleepRow: some View {
        Label(
            healthKit.sleepHours(on: date).formatted(.number.precision(.fractionLength(1))) + " h de sono",
            systemImage: "bed.double.fill"
        )
        .foregroundStyle(.indigo)
        .font(.subheadline)
    }

    /// Weight, body fat and BMI, grouped on their own row — the same body-measurement grouping
    /// used in the History list, so opening a day from there shows the same metrics.
    private var bodyMeasurementsRow: some View {
        HStack(spacing: 16) {
            if let weight = healthKit.weightKG(on: date) {
                Label(weight.formatted(.number.precision(.fractionLength(1))) + " kg", systemImage: "scalemass")
            }
            if let bodyFat = healthKit.bodyFatPercent(on: date) {
                Label((bodyFat * 100).formatted(.number.precision(.fractionLength(1))) + " %", systemImage: "percent")
            }
            if let bmi = healthKit.bmi(on: date) {
                Label("IMC " + bmi.formatted(.number.precision(.fractionLength(1))), systemImage: "figure")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var coffeeStepperRow: some View {
        HStack {
            Button {
                Task { await healthKit.removeLastCoffee(on: date) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(healthKit.coffeeCount(on: date) <= 0)

            Spacer()

            Label(coffeesLabel(healthKit.coffeeCount(on: date)), systemImage: "cup.and.saucer.fill")
                .font(.subheadline)

            Spacer()

            Button {
                Task { await healthKit.logCoffee() }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.brown)
    }

    private func supplementLogRow(_ log: SupplementLogEntry) -> some View {
        let supplement = store.supplement(withID: log.supplementID)
        return HStack {
            VStack(alignment: .leading) {
                Text(supplement?.name ?? "Suplemento")
                HStack(spacing: 4) {
                    Text(log.date.formatted(date: .omitted, time: .shortened))
                    Text("· \(quantityLabel(log.quantity)) dose\(log.quantity == 1 ? "" : "s")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let supplement, supplement.calories != nil {
                Text("\(supplement.scaledCalories(quantity: log.quantity)) kcal")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func workoutRow(_ workout: HealthKitManager.WorkoutSummary) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Label(workout.kind.displayName, systemImage: workout.kind.symbolName)
                HStack(spacing: 4) {
                    Text(workout.startDate.formatted(date: .omitted, time: .shortened))
                    Text("· \(Int((workout.duration / 60).rounded())) min")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let calories = workout.caloriesBurned {
                Text("\(Int(calories.rounded())) kcal")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func quantityLabel(_ quantity: Double) -> String {
        quantity.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(quantity))
            : String(format: "%.2f", quantity)
    }

    private func handleDiaryJSONImport(_ json: String) throws {
        let payloads = try AIJSONImport.decodeDiaryEntries(from: json)
        guard !payloads.isEmpty else { throw AIImportError.empty }
        let newEntries = payloads.map { entryPayload in
            FoodEntry(
                name: entryPayload.name.trimmingCharacters(in: .whitespaces),
                calories: entryPayload.calories,
                protein: entryPayload.protein,
                carbs: entryPayload.carbs,
                fat: entryPayload.fat,
                mealType: jsonImportMealType,
                date: date
            )
        }
        store.addImportedEntries(newEntries, groupName: jsonImportGroupName)
        AppAnalytics.log(.entryLogged(source: .aiImport, mealType: jsonImportMealType))
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
    .environment(HealthKitManager())
}
