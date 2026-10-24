import SwiftUI

/// Shows all entries for a single day, with a totals header and a way to add/edit/delete entries.
/// Used both for "Hoje" (today) and for drilling into a past day from the history list.
struct DayView: View {
    @Environment(PlatformSyncManager.self) private var platform
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
    /// The workout the alert asks about ("Consumiste algum suplemento?"), and the one whose supplement is being logged.
    @State private var supplementQuestion: HealthKitManager.WorkoutSummary?
    @State private var supplementWorkout: HealthKitManager.WorkoutSummary?
    /// The activity whose picker is open (to know, once it closes, whether anything was logged).
    @State private var lastAskedWorkout: HealthKitManager.WorkoutSummary?
    /// Activities whose picker was cancelled this time: nothing was saved, and they aren't asked again until the next time.
    @State private var skippedSupplementQuestions: Set<String> = []
    /// An intake already logged, opened to read or change its description.
    @State private var supplementLogToDescribe: SupplementLogEntry?
    @State private var showingScannerEntry = false
    @State private var showingCatalogPicker = false
    @State private var showingRecipePicker = false
    @State private var showingMealPlanPicker = false
    @State private var showingSupplementPicker = false
    @State private var showingJSONImport = false
    @State private var jsonImportGroupName = ""
    @State private var jsonImportMealType: MealType = .lunch
    @State private var entryToEdit: FoodEntry?
    @State private var entryToDuplicate: FoodEntry?
    /// A logged recipe whose amounts are being changed (tapping one of its entries).
    @State private var recipeLogToEdit: FoodEntry?
    @State private var showingDayNutrients = false
    /// A planned meal being refused (picking what was eaten instead).
    @State private var refusing: MealBoardPlacement?

    /// Meals planned on the week board for this day, not yet eaten (eaten ones are diary entries).
    private func plannedMeals(_ meal: MealType) -> [MealBoardPlacement] {
        let key = WeekBoard.dayKey(date)
        return store.mealBoardPlacements.filter { $0.day == key && $0.meal == meal && store.state(of: $0) != .consumed }
    }

    /// The day's meals in the order they happened (each where its earliest food is), so the pre- and
    /// post-workout meals show when the training was.
    private var orderedMeals: [MealType] {
        let key = WeekBoard.dayKey(date)
        let planned = store.mealBoardPlacements.filter { $0.day == key && store.state(of: $0) != .consumed }
        return MealTiming.orderedMeals(entries: dayEntries, planned: planned)
    }

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

            let dayNutrition = store.fullNutrition(on: date)
            if dayNutrition.hasDetails {
                Section {
                    Button {
                        showingDayNutrients = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mais Nutrientes")
                                Text(nutrientPreview(dayNutrition))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                }
            }

            ForEach(orderedMeals) { meal in
                let mealEntries = dayEntries.filter { $0.mealType == meal }
                let planned = plannedMeals(meal)
                if !mealEntries.isEmpty || !planned.isEmpty {
                    Section {
                        ForEach(planned) { placement in
                            PlannedMealRow(placement: placement) { refusing = placement }
                        }
                        ForEach(mealEntries) { entry in
                            Button {
                                if loggedRecipe(of: entry) != nil {
                                    recipeLogToEdit = entry
                                } else {
                                    entryToEdit = entry
                                }
                            } label: {
                                entryRow(entry)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                Button {
                                    entryToDuplicate = entry
                                } label: {
                                    Label("Duplicar", systemImage: "plus.square.on.square")
                                }
                                .tint(.green)
                                if loggedRecipe(of: entry) != nil {
                                    Button("Editar Alimento") { entryToEdit = entry }
                                        .tint(.blue)
                                }
                            }
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
                        Button {
                            supplementLogToDescribe = log
                        } label: {
                            supplementLogRow(log)
                        }
                        .buttonStyle(.plain)
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
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            workoutRow(workout)
                        }
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

            if dayEntries.isEmpty && daySupplementLogs.isEmpty && dayWorkouts.isEmpty
                && MealType.allCases.allSatisfy({ plannedMeals($0).isEmpty }) {
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
        .sheet(item: $refusing) { placement in
            PlacementSubstituteView(placement: placement)
        }
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
        .sheet(isPresented: $showingDayNutrients) {
            NavigationStack {
                List {
                    Section {
                        NutritionFactsRows(amounts: store.fullNutrition(on: date))
                    } footer: {
                        Text("Soma dos registos e das tomas de suplementos do dia. A %VRN usa os valores de referência da UE para adultos.")
                    }
                }
                .navigationTitle("Nutrientes do Dia")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { showingDayNutrients = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
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
        .sheet(item: $entryToDuplicate) { entry in
            AddEntryView(duplicateOf: entry)
        }
        .sheet(item: $recipeLogToEdit) { entry in
            if let recipe = loggedRecipe(of: entry), let groupID = entry.groupID {
                NavigationStack {
                    RecipeLogView(recipe: recipe, date: entry.date, mealType: entry.mealType, groupID: groupID) {
                        recipeLogToEdit = nil
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancelar") { recipeLogToEdit = nil }
                        }
                    }
                }
            }
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
        // A workout not asked about yet — new when the app opens, or on a day browsed back to — asks
        // whether any supplement was taken.
        .onChange(of: supplementCandidate.map(WorkoutSupplementPrompts.key), initial: true) { _, _ in askAboutSupplement() }
        .alert("Suplementação?", isPresented: Binding(get: { supplementQuestion != nil }, set: { if !$0 { supplementQuestion = nil } }), presenting: supplementQuestion) { workout in
            // Sim saves nothing yet: the answer is recorded when a supplement is logged; cancelling leaves no trace.
            Button("Sim") {
                lastAskedWorkout = workout
                supplementWorkout = workout
            }
            Button("Não", role: .cancel) {
                store.setSupplementAnswer(for: workout, consumed: false)
                askAboutSupplement()
            }
        } message: { workout in
            Text("\(workout.kind.displayName) às \(workout.startDate.formatted(date: .omitted, time: .shortened)) (\(Int((workout.duration / 60).rounded())) min). Consumiste algum suplemento neste treino?")
        }
        // Several activities in a day: when one question is answered, the next one is asked (after the
        // alert has gone), until every activity has its answer.
        .onChange(of: supplementQuestion.map(WorkoutSupplementPrompts.key)) { _, key in
            guard key == nil else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                askAboutSupplement()
            }
        }
        .sheet(item: $supplementLogToDescribe) { log in
            SupplementLogDescriptionSheet(log: log)
        }
        .sheet(item: $supplementWorkout, onDismiss: {
            // Cancelled without logging anything: nothing is kept, and the question waits for next time.
            if let asked = lastAskedWorkout, store.supplementAnswer(for: asked) == nil {
                skippedSupplementQuestions.insert(WorkoutSupplementPrompts.key(for: asked))
            }
            lastAskedWorkout = nil
            askAboutSupplement()
        }) { workout in
            SupplementPickerView(date: workout.startDate, allowsCreating: true, workout: workout)
        }
        .refreshable {
            Haptics.light()
            await platform.refresh()
            await healthKit.refresh(days: daysNeededToCoverDate)
        }
    }

    /// The next workout to ask about: those of the day shown and, on today, the ones of the last 24 h
    /// (a workout that ended after midnight belongs to yesterday's list).
    private var supplementCandidate: HealthKitManager.WorkoutSummary? {
        var workouts = healthKit.workouts(on: date)
        if isToday, let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) {
            workouts += healthKit.workouts(on: yesterday).filter { $0.startDate > Date.now.addingTimeInterval(-24 * 3600) }
        }
        return WorkoutSupplementPrompts.next(in: workouts.filter { !skippedSupplementQuestions.contains(WorkoutSupplementPrompts.key(for: $0)) }, store: store)
    }

    /// Shows the question when there's a workout to ask about and nothing else is on screen over this one.
    private func askAboutSupplement() {
        guard supplementQuestion == nil, supplementWorkout == nil, let workout = supplementCandidate else { return }
        supplementQuestion = workout
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
                if let notes = log.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if let supplement, supplement.calories != nil {
                let nutrition = supplement.nutrition(quantity: log.quantity)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(supplement.scaledCalories(quantity: log.quantity)) kcal")
                        .foregroundStyle(.secondary)
                    Text(macroSummary(protein: nutrition.protein, carbs: nutrition.carbs, fat: nutrition.fat))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
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
                WorkoutSupplementBadge(workout: workout)
                    .font(.caption)
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
                nutrition: entryPayload.nutrition,
                mealType: jsonImportMealType,
                date: date
            )
        }
        store.addImportedEntries(newEntries, groupName: jsonImportGroupName)
        AppAnalytics.log(.entryLogged(source: .aiImport, mealType: jsonImportMealType))
    }

    /// "Açúcares 17 g · Saturados 2 g · Sal 1 g · 4 outros nutrientes".
    private func nutrientPreview(_ amounts: NutritionAmounts) -> String {
        var parts: [String] = []
        if let sugars = amounts.sugars { parts.append("Açúcares \(NutritionFactsRows.format(sugars)) g") }
        if let saturated = amounts.saturatedFat { parts.append("Saturados \(NutritionFactsRows.format(saturated)) g") }
        if let fiber = amounts.fiber { parts.append("Fibra \(NutritionFactsRows.format(fiber)) g") }
        if let salt = amounts.salt { parts.append("Sal \(NutritionFactsRows.format(salt)) g") }
        let micros = amounts.micronutrients.count
        if micros > 0 { parts.append(micros == 1 ? "1 outro nutriente" : "\(micros) outros nutrientes") }
        return parts.joined(separator: " · ")
    }

    /// The recipe `entry` was logged from, when it still exists (its group's amounts can be
    /// changed again).
    private func loggedRecipe(of entry: FoodEntry) -> Recipe? {
        guard entry.groupID != nil, let recipeID = entry.recipeID else { return nil }
        return store.recipe(withID: recipeID)
    }

    private func entryRow(_ entry: FoodEntry) -> some View {
        HStack {
            #if canImport(UIKit)
            if let photoID = entry.photoID, let image = PhotoStore.image(photoID) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            #endif
            VStack(alignment: .leading) {
                Text(entry.name)
                HStack(spacing: 4) {
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                    if let amount = amountEaten(entry) {
                        Text("· \(amount)")
                    }
                    if let groupName = entry.groupName {
                        Text("· \(groupName)")
                    }
                    if entry.barcode != nil {
                        Image(systemName: "barcode")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.calories) kcal")
                    .foregroundStyle(.secondary)
                Text(macroSummary(protein: entry.protein, carbs: entry.carbs, fat: entry.fat))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    /// "P 28 · HC 0 · G 3" — the brief summary under a row's calories ("—" for what isn't stated).
    private func macroSummary(protein: Double?, carbs: Double?, fat: Double?) -> String {
        let part = { (label: String, value: Double?) in "\(label) \(value.map(MacroFormat.grams) ?? "—")" }
        return [part("P", protein), part("HC", carbs), part("G", fat)].joined(separator: " · ")
    }

    /// "125 g", "2 unidades" — how much was eaten, when the entry is linked to its catalog food.
    private func amountEaten(_ entry: FoodEntry) -> String? {
        guard let quantity = entry.quantity, let id = entry.foodItemID,
              let food = store.foodItems.first(where: { $0.id == id }) else { return nil }
        return RecipeIngredientEditorView.amountLabel(food: food, quantity: quantity)
    }
}

#Preview {
    NavigationStack {
        DayView(date: .now)
    }
    .environment(DataStore())
    .environment(HealthKitManager())
}
