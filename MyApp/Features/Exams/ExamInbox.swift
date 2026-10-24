import SwiftUI

/// A PDF or photo that came into the app from another one (Share → "Copiar para…" / "Abrir em" on a
/// PDF in Files, Mail, Safari, a lab's app…). The app registers as a handler of PDFs and images — no
/// share extension, which would need an App Group (a paid capability); a free developer account is enough.
struct IncomingExamFile: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
    /// `"pdf"` or `"image"`.
    let type: String
}

/// Where such a file waits for the athlete to say what it is. `ContentView` shows the sheet.
@MainActor
@Observable
final class ExamInbox {
    static let shared = ExamInbox()

    /// The file waiting for its type (analysis or other exam), nil when there's none.
    var pending: IncomingExamFile?

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp"]

    /// Reads a file opened with the app; ignores anything that isn't a PDF or a photo, or is over 20 MB.
    func receive(_ url: URL) {
        guard url.isFileURL else { return }
        let ext = url.pathExtension.lowercased()
        let type: String
        if ext == "pdf" { type = "pdf" } else if Self.imageExtensions.contains(ext) { type = "image" } else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count <= 20 * 1024 * 1024 else { return }
        pending = IncomingExamFile(name: url.lastPathComponent, data: data, type: type)
        // The copy the system put in the app's Inbox isn't needed any more.
        try? FileManager.default.removeItem(at: url)
    }
}

/// "Guardar Exame": the file that came in, and which kind of exam it is. Each choice opens the
/// matching editor with the document already attached.
struct ShareExamSheet: View {
    @Environment(\.dismiss) private var dismiss

    let file: IncomingExamFile

    private enum Kind { case lab, other }
    @State private var kind: Kind?

    var body: some View {
        switch kind {
        case .lab:
            LabReportEditorView(initialFile: file)
        case .other:
            OtherExamEditorView(initialFile: file)
        case nil:
            NavigationStack {
                List {
                    Section {
                        Label(file.name, systemImage: file.type == "pdf" ? "doc.richtext" : "photo")
                    } header: {
                        Text("Documento Recebido")
                    }
                    Section {
                        Button { kind = .lab } label: {
                            Label("Análises Clínicas", systemImage: "testtube.2")
                        }
                        Button { kind = .other } label: {
                            Label("Outro Exame", systemImage: "stethoscope")
                        }
                    } header: {
                        Text("Que Tipo de Exame É?")
                    } footer: {
                        Text("O documento fica anexado; a seguir completas os dados. Nas análises podes pedir a uma IA que preencha os resultados.")
                    }
                }
                .navigationTitle("Guardar Exame")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
