import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if canImport(QuickLook)
import QuickLook
#endif

/// The documents of an exam (PDFs and photos) inside an editor: add a PDF from Files or photos from
/// the library, open one to read it, remove one. Added files go to `ExamFileStore` at once; what the
/// editor drops when cancelled is the editor's to clean up (`addedPaths`).
struct ExamFilesSection: View {
    @Environment(PlatformSyncManager.self) private var platform

    let kind: String
    let recordID: UUID
    @Binding var files: [ExamFile]
    /// Paths added during this edit, so cancelling can delete them again.
    @Binding var addedPaths: [String]

    @State private var showingPDFImporter = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var previewURL: URL?
    @State private var openingPath: String?
    @State private var errorMessage: String?

    var body: some View {
        Section {
            ForEach(files) { file in
                Button {
                    open(file)
                } label: {
                    HStack {
                        Image(systemName: file.isPDF ? "doc.richtext" : "photo")
                            .foregroundStyle(.tint)
                        Text(file.name)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        if openingPath == file.path { ProgressView() }
                    }
                }
            }
            .onDelete { offsets in files.remove(atOffsets: offsets) }

            Button {
                showingPDFImporter = true
            } label: {
                Label("Adicionar PDF", systemImage: "doc.badge.plus")
            }
            PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 12, matching: .images) {
                Label("Adicionar Fotos", systemImage: "photo.badge.plus")
            }
        } header: {
            Text("Documentos")
        } footer: {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else {
                Text("PDF ou fotos do relatório. Ficam guardados na app e na plataforma (só tu os vês).")
            }
        }
        .fileImporter(isPresented: $showingPDFImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            importPDFs(result)
        }
        .onChange(of: pickedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        #if canImport(QuickLook) && os(iOS)
        .quickLookPreview($previewURL)
        #endif
    }

    private func add(_ data: Data, name: String, type: String) {
        let path = ExamFileStore.newPath(kind: kind, recordID: recordID, fileName: name)
        guard ExamFileStore.write(data, path: path) else {
            errorMessage = "Não foi possível guardar \(name)."
            return
        }
        files.append(ExamFile(path: path, name: name, type: type))
        addedPaths.append(path)
    }

    private func importPDFs(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        errorMessage = nil
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                errorMessage = "Não foi possível ler \(url.lastPathComponent)."
                continue
            }
            if data.count > 20 * 1024 * 1024 {
                errorMessage = "\(url.lastPathComponent) tem mais de 20 MB."
                continue
            }
            add(data, name: url.lastPathComponent, type: "pdf")
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        errorMessage = nil
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self), let jpeg = Self.jpeg(from: data) else {
                errorMessage = "Não foi possível ler uma das fotos."
                continue
            }
            add(jpeg, name: "Foto \(files.count + 1)-\(index + 1).jpg", type: "image")
        }
        pickedPhotos = []
    }

    /// The photo scaled down to 2200 px on its longer side (readable small print, light to keep) as JPEG.
    static func jpeg(from data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 2200 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.jpegData(withCompressionQuality: 0.8) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        #else
        return data
        #endif
    }

    private func open(_ file: ExamFile) {
        errorMessage = nil
        openingPath = file.path
        Task {
            defer { openingPath = nil }
            do {
                previewURL = try await platform.localURL(forExamFile: file)
            } catch {
                errorMessage = "Não foi possível abrir \(file.name): \(error.localizedDescription)"
            }
        }
    }
}

extension IncomingExamFile {
    /// The file stored for an exam of `kind` ("lab" / "other") with id `recordID`, as an `ExamFile` — or nil when it can't be stored.
    /// Photos go in as JPEG, scaled down like the ones picked in the editor.
    func stored(kind: String, recordID: UUID) -> ExamFile? {
        let isImage = type == "image"
        guard let bytes = isImage ? ExamFilesSection.jpeg(from: data) : data else { return nil }
        let fileName = isImage ? (name as NSString).deletingPathExtension + ".jpg" : name
        let path = ExamFileStore.newPath(kind: kind, recordID: recordID, fileName: fileName)
        guard ExamFileStore.write(bytes, path: path) else { return nil }
        return ExamFile(path: path, name: fileName, type: type)
    }
}
