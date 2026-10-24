import SwiftUI
#if canImport(QuickLook)
import QuickLook
#endif

/// A clinical analysis, to read: the results by group with their flag against the reference range, and the documents.
struct LabReportDetailView: View {
    @Environment(DataStore.self) private var store
    @Environment(PlatformSyncManager.self) private var platform

    let reportID: UUID
    @State private var editing = false
    @State private var previewURL: URL?
    @State private var errorMessage: String?

    private var report: LabReport? { store.labReports.first { $0.id == reportID } }

    var body: some View {
        Group {
            if let report {
                List {
                    Section {
                        LabeledContent("Data", value: ExamDates.short(report.performedOn))
                        if let lab = report.lab, !lab.isEmpty { LabeledContent("Laboratório", value: lab) }
                        if let notes = report.notes, !notes.isEmpty { Text(notes).foregroundStyle(.secondary) }
                    } footer: {
                        if report.outOfRangeCount > 0 {
                            Text("\(report.outOfRangeCount) resultados fora do intervalo de referência.").foregroundStyle(.orange)
                        }
                    }

                    ForEach(groups(of: report), id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.results) { result in resultRow(result) }
                        }
                    }

                    if !report.files.isEmpty {
                        Section {
                            ForEach(report.files) { file in
                                Button {
                                    open(file)
                                } label: {
                                    Label(file.name, systemImage: file.isPDF ? "doc.richtext" : "photo")
                                }
                            }
                        } header: {
                            Text("Documentos")
                        } footer: {
                            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                        }
                    }
                }
                .navigationTitle(report.title)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Button("Editar") { editing = true } }
                }
                .sheet(isPresented: $editing) { LabReportEditorView(reportToEdit: report) }
                #if os(iOS)
                .quickLookPreview($previewURL)
                #endif
            } else {
                ContentUnavailableView("Análise Não Encontrada", systemImage: "testtube.2")
            }
        }
    }

    private func groups(of report: LabReport) -> [(title: String, results: [LabResult])] {
        var order: [String] = []
        var byGroup: [String: [LabResult]] = [:]
        for result in report.results {
            let key = result.group?.trimmingCharacters(in: .whitespaces) ?? ""
            if byGroup[key] == nil { order.append(key) }
            byGroup[key, default: []].append(result)
        }
        return order.sorted { ($0.isEmpty ? 0 : 1) < ($1.isEmpty ? 0 : 1) }.map { (title: $0.isEmpty ? "Resultados" : $0, results: byGroup[$0] ?? []) }
    }

    private func resultRow(_ result: LabResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                if let range = result.rangeLabel {
                    Text("Referência: \(range)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(result.valueLabel).monospacedDigit()
                if let flag = result.flag, flag != .normal {
                    Text(flag.label).font(.caption2).foregroundStyle(flag == .high ? Color.orange : Color.blue)
                }
            }
        }
    }

    private func open(_ file: ExamFile) {
        errorMessage = nil
        Task {
            do { previewURL = try await platform.localURL(forExamFile: file) } catch {
                errorMessage = "Não foi possível abrir \(file.name): \(error.localizedDescription)"
            }
        }
    }
}

/// New or edited clinical analysis: title, date, lab, notes, the results and the documents.
/// "Importar com IA" fills it from a report (photo, PDF or text) read by an assistant.
struct LabReportEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var reportToEdit: LabReport?
    /// A document that came in from another app (Share): attached to the new analysis.
    var initialFile: IncomingExamFile?

    @State private var id = UUID()
    @State private var title = ""
    @State private var performedOn = Date()
    @State private var lab = ""
    @State private var notes = ""
    @State private var results: [LabResult] = []
    @State private var files: [ExamFile] = []
    @State private var addedPaths: [String] = []
    @State private var showingImport = false
    @State private var editingResult: LabResult?
    @State private var loaded = false

    private var isValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !results.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Título", text: $title)
                    DatePicker("Data", selection: $performedOn, in: ...Date(), displayedComponents: .date)
                    TextField("Laboratório (opcional)", text: $lab)
                    TextField("Notas (opcional)", text: $notes, axis: .vertical).lineLimit(1...5)
                }

                Section {
                    ForEach(results) { result in
                        Button { editingResult = result } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name).foregroundStyle(.primary)
                                    if let group = result.group, !group.isEmpty { Text(group).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Text(result.valueLabel).foregroundStyle(result.isOutOfRange ? Color.orange : Color.secondary).monospacedDigit()
                            }
                        }
                    }
                    .onDelete { results.remove(atOffsets: $0) }
                    Button {
                        editingResult = LabResult(name: "")
                    } label: {
                        Label("Adicionar Resultado", systemImage: "plus")
                    }
                } header: {
                    Text("Resultados")
                } footer: {
                    Text("Usa “Importar com IA” para preencher a partir do relatório. Confere os valores com o documento antes de guardar.")
                }

                ExamFilesSection(kind: "lab", recordID: id, files: $files, addedPaths: $addedPaths)
            }
            .navigationTitle(reportToEdit == nil ? "Nova Análise" : "Editar Análise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        addedPaths.forEach(ExamFileStore.remove)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .barTrailing) {
                    Button { showingImport = true } label: { Label("Importar com IA", systemImage: "sparkles") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }.disabled(!isValid)
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showingImport) {
                JSONImportSheet(
                    title: "Importar Análises",
                    prompt: AIJSONImport.labReportPrompt,
                    instructions: "Cola o texto do relatório ou envia uma foto (para várias páginas, junta as restantes na conversa com a IA); a IA devolve o título, a data e cada análise com a unidade e o intervalo de referência. Preenche este formulário — confere os valores antes de guardar. Um JSON escrito à mão também serve."
                ) { json in
                    try applyImport(json)
                }
            }
            .sheet(item: $editingResult) { result in
                LabResultEditorView(result: result) { saved in
                    if let index = results.firstIndex(where: { $0.id == saved.id }) { results[index] = saved } else { results.append(saved) }
                }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let report = reportToEdit else {
            if let initialFile, let stored = initialFile.stored(kind: "lab", recordID: id) {
                files = [stored]
                addedPaths = [stored.path]
            }
            return
        }
        id = report.id
        title = report.title
        performedOn = WeekBoard.date(of: report.performedOn) ?? Date()
        lab = report.lab ?? ""
        notes = report.notes ?? ""
        results = report.results
        files = report.files
    }

    /// Fills the form from the AI's answer: what was already typed (title, date…) is kept; the results are replaced.
    private func applyImport(_ json: String) throws {
        let imported = try AIJSONImport.decodeLabReport(from: json).report
        if title.trimmingCharacters(in: .whitespaces).isEmpty { title = imported.title }
        if !imported.performedOn.isEmpty, reportToEdit == nil, let day = WeekBoard.date(of: imported.performedOn) { performedOn = day }
        if lab.isEmpty, let importedLab = imported.lab { lab = importedLab }
        if notes.isEmpty, let importedNotes = imported.notes { notes = importedNotes }
        results = imported.results
    }

    private func save() {
        let report = LabReport(
            id: id,
            title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)),
            performedOn: WeekBoard.dayKey(performedOn),
            lab: lab.trimmingCharacters(in: .whitespaces).isEmpty ? nil : lab.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines),
            results: results.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty },
            files: files
        )
        store.saveLabReport(report)
        dismiss()
    }
}

/// One analyte: name, group, the result (a number or text), unit and reference range.
private struct LabResultEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let result: LabResult
    let onSave: (LabResult) -> Void

    @State private var name: String
    @State private var group: String
    @State private var valueText: String
    @State private var unit: String
    @State private var refMin: String
    @State private var refMax: String
    @State private var refText: String

    init(result: LabResult, onSave: @escaping (LabResult) -> Void) {
        self.result = result
        self.onSave = onSave
        _name = State(initialValue: result.name)
        _group = State(initialValue: result.group ?? "")
        _valueText = State(initialValue: result.value.map(LabResult.number) ?? result.valueText ?? "")
        _unit = State(initialValue: result.unit ?? "")
        _refMin = State(initialValue: result.refMin.map(LabResult.number) ?? "")
        _refMax = State(initialValue: result.refMax.map(LabResult.number) ?? "")
        _refText = State(initialValue: result.refText ?? "")
    }

    private func number(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return t.isEmpty ? nil : Double(t)
    }

    private var draft: LabResult {
        var r = result
        r.name = name.trimmingCharacters(in: .whitespaces)
        r.group = group.trimmingCharacters(in: .whitespaces).isEmpty ? nil : group.trimmingCharacters(in: .whitespaces)
        if let value = number(valueText) {
            r.value = value
            r.valueText = nil
        } else {
            r.value = nil
            r.valueText = valueText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : valueText.trimmingCharacters(in: .whitespaces)
        }
        r.unit = unit.trimmingCharacters(in: .whitespaces).isEmpty ? nil : unit.trimmingCharacters(in: .whitespaces)
        r.refMin = number(refMin)
        r.refMax = number(refMax)
        r.refText = refText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : refText.trimmingCharacters(in: .whitespaces)
        return r
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Análise", text: $name)
                    TextField("Secção (opcional)", text: $group)
                }
                Section {
                    TextField("Resultado", text: $valueText)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                    TextField("Unidade (opcional)", text: $unit)
                } footer: {
                    Text("Um número ou, se o relatório der texto, o texto (ex.: Negativo).")
                }
                Section {
                    TextField("Mínimo", text: $refMin)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Máximo", text: $refMax)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Referência em texto (opcional)", text: $refText)
                } header: {
                    Text("Intervalo de Referência")
                } footer: {
                    if let flag = draft.flag { Text(flag.label) }
                }
            }
            .navigationTitle(result.name.isEmpty ? "Novo Resultado" : "Resultado")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || valueText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
