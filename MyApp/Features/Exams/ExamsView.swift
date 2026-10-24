import SwiftUI

/// Exams: clinical analyses (with their results) and other exams, each with its documents.
/// Health records — they stay with the athlete (nothing here is shared through the dashboard's access).
struct ExamsView: View {
    @Environment(DataStore.self) private var store

    private enum Tab: String, CaseIterable, Identifiable {
        case labs = "Análises", other = "Outros Exames"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .labs
    @State private var newLabReport = false
    @State private var newOtherExam = false

    var body: some View {
        List {
            Section {
                Picker("Tipo", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            switch tab {
            case .labs: labsSection
            case .other: otherSection
            }
        }
        .navigationTitle("Exames")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if tab == .labs { newLabReport = true } else { newOtherExam = true }
                } label: {
                    Label(tab == .labs ? "Nova Análise" : "Novo Exame", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $newLabReport) { LabReportEditorView() }
        .sheet(isPresented: $newOtherExam) { OtherExamEditorView() }
        .trackScreen("Exames")
    }

    @ViewBuilder private var labsSection: some View {
        let reports = store.sortedLabReports
        if reports.isEmpty {
            Section {
                ContentUnavailableView("Sem Análises", systemImage: "testtube.2",
                                       description: Text("Adiciona a primeira: podes preenchê-la a partir de fotos ou de um PDF com a ajuda de uma IA."))
            }
        } else {
            Section {
                ForEach(reports) { report in
                    NavigationLink {
                        LabReportDetailView(reportID: report.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(report.title).font(.headline)
                                Spacer()
                                Text(ExamDates.short(report.performedOn)).font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                if let lab = report.lab, !lab.isEmpty { Text(lab) }
                                Text("\(report.results.count) resultados")
                                if report.outOfRangeCount > 0 {
                                    Label("\(report.outOfRangeCount) fora do intervalo", systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                }
                                if !report.files.isEmpty { Label("\(report.files.count)", systemImage: "paperclip") }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { store.deleteLabReport(reports[index]) }
                }
            }
        }
    }

    @ViewBuilder private var otherSection: some View {
        let exams = store.sortedOtherExams
        if exams.isEmpty {
            Section {
                ContentUnavailableView("Sem Exames", systemImage: "stethoscope",
                                       description: Text("Ecografias, eletrocardiogramas, radiografias… com o título, as datas das consultas e o PDF ou as fotos."))
            }
        } else {
            Section {
                ForEach(exams) { exam in
                    NavigationLink {
                        OtherExamEditorView(examToEdit: exam)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(exam.title).font(.headline)
                            HStack(spacing: 10) {
                                Text("Pedido: \(ExamDates.short(exam.requestedOn))")
                                Text("Visto: \(ExamDates.short(exam.viewedOn))")
                                if !exam.files.isEmpty { Label("\(exam.files.count)", systemImage: "paperclip") }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { store.deleteOtherExam(exams[index]) }
                }
            }
        }
    }
}

/// Exam dates are Lisbon days, "yyyy-MM-dd".
enum ExamDates {
    static func short(_ day: String?) -> String {
        guard let day, let date = WeekBoard.date(of: day) else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
