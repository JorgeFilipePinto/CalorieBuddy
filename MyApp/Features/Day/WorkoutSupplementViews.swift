import SwiftUI

/// An activity from Apple Health, opened from the day: its numbers, whether it was done com or sem
/// suplementação, and what was taken (each with the description of the approach).
struct WorkoutDetailView: View {
    @Environment(DataStore.self) private var store

    let workout: HealthKitManager.WorkoutSummary
    @State private var addingSupplement = false
    /// An intake of this activity opened to change (doses, stock, time, description).
    @State private var logToEdit: SupplementLogEntry?

    private var answer: WorkoutSupplementAnswer? { store.supplementAnswer(for: workout) }
    private var logs: [SupplementLogEntry] { store.supplementLogs(for: workout) }

    var body: some View {
        List {
            Section {
                LabeledContent("Hora", value: workout.startDate.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duração", value: "\(Int((workout.duration / 60).rounded())) min")
                if let calories = workout.caloriesBurned { LabeledContent("Energia", value: "\(Int(calories.rounded())) kcal") }
                if let distance = workout.distanceMeters, distance > 0 {
                    LabeledContent("Distância", value: String(format: "%.2f km", distance / 1000))
                }
            }

            Section {
                Picker("Suplementação", selection: Binding(
                    get: { answer.map { $0.consumed ? 1 : 0 } ?? -1 },
                    set: { if $0 >= 0 { store.setSupplementAnswer(for: workout, consumed: $0 == 1) } }
                )) {
                    if answer == nil { Text("Por responder").tag(-1) }
                    Text("Com suplementação").tag(1)
                    Text("Sem suplementação").tag(0)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Suplementação")
            } footer: {
                if answer?.consumed == false, !logs.isEmpty {
                    Text("Há suplementos registados neste treino; escolher “Com suplementação” mantém-nos associados.")
                }
            }

            if answer?.consumed == true || !logs.isEmpty {
                Section {
                    if logs.isEmpty {
                        Text("Ainda sem suplementos registados.").foregroundStyle(.secondary)
                    }
                    ForEach(logs) { log in
                        Button { logToEdit = log } label: { logRow(log) }
                            .buttonStyle(.plain)
                    }
                        .onDelete { offsets in
                            for index in offsets { store.deleteSupplementLog(logs[index]) }
                        }
                    Button {
                        addingSupplement = true
                    } label: {
                        Label("Adicionar Suplemento", systemImage: "plus")
                    }
                } header: {
                    Text("Consumido")
                }
            }
        }
        .navigationTitle(workout.kind.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $addingSupplement) {
            SupplementPickerView(date: workout.startDate, allowsCreating: true, workout: workout)
        }
        .sheet(item: $logToEdit) { log in
            SupplementLogDescriptionSheet(log: log)
        }
    }

    /// One supplement taken in the activity: its name, doses and time, and the description of the
    /// approach — tap to change it (and the doses, stock or time).
    private func logRow(_ log: SupplementLogEntry) -> some View {
        let supplement = store.supplement(withID: log.supplementID)
        let notes = log.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(supplement?.name ?? "Suplemento").font(.headline)
                    Spacer()
                    Text("\(log.quantity.formatted(.number.precision(.fractionLength(0...2)))) dose\(log.quantity == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
                Text(log.date.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Descrição").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    if notes.isEmpty {
                        Text("Sem descrição — toca para adicionar.").font(.callout).foregroundStyle(.tertiary)
                    } else {
                        Text(notes).font(.callout).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    }
                }
            }
            Image(systemName: "pencil.circle")
                .foregroundStyle(.tint)
                .accessibilityLabel("Editar")
        }
        .contentShape(Rectangle())
    }
}

/// "Com suplementação" / "Sem suplementação" / "Por responder", as a small label under an activity.
struct WorkoutSupplementBadge: View {
    @Environment(DataStore.self) private var store
    let workout: HealthKitManager.WorkoutSummary

    var body: some View {
        switch store.supplementAnswer(for: workout)?.consumed {
        case true?: Label("Com suplementação", systemImage: "pills.fill").foregroundStyle(.green)
        case false?: Label("Sem suplementação", systemImage: "pills").foregroundStyle(.secondary)
        case nil: Label("Por responder", systemImage: "questionmark.circle").foregroundStyle(.orange)
        }
    }
}

/// An intake already logged, to change: doses, stock, time and the description. Changing the doses or
/// the stock puts the stock right — what the intake had taken goes back, the new amount comes off.
struct SupplementLogDescriptionSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let log: SupplementLogEntry
    @State private var dosesText: String
    @State private var stock: UUID?
    @State private var date: Date
    @State private var notes: String

    init(log: SupplementLogEntry) {
        self.log = log
        _dosesText = State(initialValue: log.quantity.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)))
        _stock = State(initialValue: log.stockID)
        _date = State(initialValue: log.date)
        _notes = State(initialValue: log.notes ?? "")
    }

    private var supplement: Supplement? { store.supplement(withID: log.supplementID) }
    private var doses: Double? {
        let value = Double(dosesText.replacingOccurrences(of: ",", with: "."))
        return value.flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Suplemento", value: supplement?.name ?? "Suplemento")
                    DatePicker("Quando", selection: $date)
                    HStack {
                        Text("Doses")
                        Spacer()
                        TextField("1", text: $dosesText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                if let supplement, !supplement.stocks.isEmpty {
                    SupplementStockSection(supplement: supplement, quantity: doses ?? log.quantity, selection: $stock,
                                           returningStock: log.stockID, returning: log.quantity)
                }

                Section {
                    TextField("Como foi tomado", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Descrição")
                } footer: {
                    Text("A abordagem: quando, com quê, porquê.")
                }
            }
            .navigationTitle("Suplemento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if let doses {
                            store.updateSupplementLog(log.id, quantity: doses, stockID: stock, date: date, notes: notes)
                        }
                        dismiss()
                    }
                    .disabled(doses == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
