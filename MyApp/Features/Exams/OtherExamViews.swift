import SwiftUI

/// Another exam, to view or edit: title, the appointment that requested it and the one that looked at it, notes and the documents.
struct OtherExamEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var examToEdit: OtherExam?
    /// A document that came in from another app (Share): attached to the new exam.
    var initialFile: IncomingExamFile?

    @State private var id = UUID()
    @State private var title = ""
    @State private var hasRequested = false
    @State private var requestedOn = Date()
    @State private var hasViewed = false
    @State private var viewedOn = Date()
    @State private var notes = ""
    @State private var files: [ExamFile] = []
    @State private var addedPaths: [String] = []
    @State private var loaded = false

    private var isValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        // Pushed from the list (it has a navigation bar already) or presented as a sheet for a new one.
        if examToEdit == nil {
            NavigationStack { form }
        } else {
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Título (ex.: Ecografia abdominal)", text: $title)
            }
            Section {
                Toggle("Consulta em que foi pedido", isOn: $hasRequested.animation())
                if hasRequested { DatePicker("Data", selection: $requestedOn, in: ...Date(), displayedComponents: .date) }
                Toggle("Consulta em que foi visto", isOn: $hasViewed.animation())
                if hasViewed { DatePicker("Data", selection: $viewedOn, in: ...Date(), displayedComponents: .date) }
            } header: {
                Text("Consultas")
            }
            Section {
                TextField("Notas (opcional)", text: $notes, axis: .vertical).lineLimit(1...6)
            }
            ExamFilesSection(kind: "other", recordID: id, files: $files, addedPaths: $addedPaths)
        }
        .navigationTitle(examToEdit == nil ? "Novo Exame" : "Exame")
        .toolbar {
            if examToEdit == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        addedPaths.forEach(ExamFileStore.remove)
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { save() }.disabled(!isValid)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let exam = examToEdit else {
            if let initialFile, let stored = initialFile.stored(kind: "other", recordID: id) {
                files = [stored]
                addedPaths = [stored.path]
            }
            return
        }
        id = exam.id
        title = exam.title
        if let day = exam.requestedOn, let date = WeekBoard.date(of: day) { hasRequested = true; requestedOn = date }
        if let day = exam.viewedOn, let date = WeekBoard.date(of: day) { hasViewed = true; viewedOn = date }
        notes = exam.notes ?? ""
        files = exam.files
    }

    private func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        store.saveOtherExam(OtherExam(
            id: id,
            title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)),
            requestedOn: hasRequested ? WeekBoard.dayKey(requestedOn) : nil,
            viewedOn: hasViewed ? WeekBoard.dayKey(viewedOn) : nil,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            files: files
        ))
        dismiss()
    }
}
