import SwiftUI

/// Free reminders (take a supplement, drink a shake…): not tied to any food or supplement.
struct RemindersListView: View {
    @Environment(DataStore.self) private var store
    @State private var editing: Reminder?
    @State private var creating = false

    var body: some View {
        List {
            if store.reminders.isEmpty {
                ContentUnavailableView("Sem Lembretes", systemImage: "bell.badge",
                                       description: Text("Cria um lembrete com uma ou mais janelas horárias e os dias da semana em que se repete."))
            } else {
                Section {
                    ForEach(store.reminders) { reminder in
                        HStack {
                            Button { editing = reminder } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(reminder.title).foregroundStyle(.primary)
                                    Text(reminder.weekdaySummary).font(.caption).foregroundStyle(.secondary)
                                    ForEach(reminder.windows) { window in
                                        Text(window.summary).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Toggle("Ativo", isOn: Binding(
                                get: { reminder.isEnabled },
                                set: { store.setReminderEnabled(id: reminder.id, $0) }))
                                .labelsHidden()
                        }
                        .swipeActions {
                            Button("Eliminar", role: .destructive) { store.deleteReminder(id: reminder.id) }
                        }
                    }
                } footer: {
                    Text("Cada notificação pergunta se já consumiste. Se responderes «Já consumi», esse lembrete não volta a tocar nessa janela nesse dia. Os próximos 7 dias ficam agendados no telemóvel e são atualizados sempre que abres a app.")
                }
            }
        }
        .navigationTitle("Lembretes")
        .toolbar {
            Button { creating = true } label: { Label("Novo Lembrete", systemImage: "plus") }
        }
        .sheet(isPresented: $creating) {
            NavigationStack { ReminderEditorView(reminder: nil) }
        }
        .sheet(item: $editing) { reminder in
            NavigationStack { ReminderEditorView(reminder: reminder) }
        }
        .trackScreen("Lembretes")
    }
}

struct ReminderEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let original: Reminder?
    @State private var title: String
    @State private var note: String
    @State private var weekdays: Set<Int>
    @State private var windows: [ReminderWindow]

    init(reminder: Reminder?) {
        original = reminder
        _title = State(initialValue: reminder?.title ?? "")
        _note = State(initialValue: reminder?.note ?? "")
        _weekdays = State(initialValue: Set(reminder?.weekdays ?? Array(1...7)))
        _windows = State(initialValue: reminder?.windows ?? [ReminderWindow(startMinute: 9 * 60, endMinute: 10 * 60, repeatMinutes: 15)])
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !weekdays.isEmpty && !windows.isEmpty
    }

    var body: some View {
        Form {
            Section("Lembrete") {
                TextField("O que lembrar (ex.: Creatina)", text: $title)
                TextField("Nota (opcional)", text: $note)
            }

            Section("Dias da Semana") {
                HStack {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                        Button {
                            if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                        } label: {
                            Text(Reminder.weekdayLetters[day - 1])
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(weekdays.contains(day) ? Color.accentColor : Color.secondary.opacity(0.2), in: Circle())
                                .foregroundStyle(weekdays.contains(day) ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Reminder.weekdayNames[day - 1])
                    }
                }
            }

            ForEach($windows) { $window in
                Section {
                    DatePicker("Início", selection: minuteBinding($window.startMinute), displayedComponents: .hourAndMinute)
                    Picker("Repetir", selection: $window.repeatMinutes) {
                        Text("Só uma vez").tag(Int?.none)
                        ForEach([5, 10, 15, 30, 60], id: \.self) { Text("De \($0) em \($0) min").tag(Int?.some($0)) }
                    }
                    if window.repeatMinutes != nil {
                        DatePicker("Até", selection: minuteBinding($window.endMinute), displayedComponents: .hourAndMinute)
                    }
                    if windows.count > 1 {
                        Button("Remover Janela", role: .destructive) { windows.removeAll { $0.id == window.id } }
                    }
                } header: {
                    Text("Janela \((windows.firstIndex { $0.id == window.id } ?? 0) + 1)")
                }
            }
            Section {
                Button("Adicionar Janela Horária", systemImage: "plus") {
                    windows.append(ReminderWindow(startMinute: 18 * 60, endMinute: 19 * 60, repeatMinutes: 15))
                }
            } footer: {
                Text("Dentro da janela o alerta repete-se até responderes «Já consumi» na notificação.")
            }
        }
        .navigationTitle(original == nil ? "Novo Lembrete" : "Editar Lembrete")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { save() }.disabled(!canSave)
            }
        }
    }

    private func save() {
        var reminder = original ?? Reminder(title: "")
        reminder.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.note = trimmedNote.isEmpty ? nil : trimmedNote
        reminder.weekdays = weekdays.sorted()
        reminder.windows = windows.map { window in
            var window = window
            if window.endMinute < window.startMinute { window.endMinute = window.startMinute }
            return window
        }
        store.saveReminder(reminder)
        dismiss()
    }

    /// A minute-of-day as the time picker's date.
    private func minuteBinding(_ minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(byAdding: .minute, value: minute.wrappedValue, to: Calendar.current.startOfDay(for: .now)) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minute.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
    }
}
