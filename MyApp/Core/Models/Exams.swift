import Foundation

/// A PDF or a photo of an exam, kept in the athlete-exams bucket under `path`
/// (`lab/<report id>/<file>` or `other/<exam id>/<file>`) and, on this iPhone, in `ExamFileStore`.
struct ExamFile: Codable, Equatable, Identifiable, Hashable {
    /// `"pdf"` or `"image"`.
    var path: String
    var name: String
    var type: String

    var id: String { path }
    var isPDF: Bool { type == "pdf" }
}

/// Where a numeric result stands against its own reference range.
enum LabFlag {
    case low, high, normal

    var label: String {
        switch self {
        case .low: return "Baixo"
        case .high: return "Alto"
        case .normal: return "Dentro do intervalo"
        }
    }
}

/// One analyte of a clinical analysis: numeric (`value`) or a text result (`valueText`, "Negativo"),
/// with the reference range the report gives. Same JSON as the dashboard's `LabResult`.
struct LabResult: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var group: String?
    var value: Double?
    var valueText: String?
    var unit: String?
    var refMin: Double?
    var refMax: Double?
    /// A reference written as text when it isn't a plain range.
    var refText: String?

    var flag: LabFlag? {
        guard let value else { return nil }
        if let refMin, value < refMin { return .low }
        if let refMax, value > refMax { return .high }
        return refMin != nil || refMax != nil ? .normal : nil
    }

    var isOutOfRange: Bool { flag == .low || flag == .high }

    /// "215 mg/dL" or the text result.
    var valueLabel: String {
        let base = value.map { LabResult.number($0) } ?? valueText ?? "—"
        guard value != nil, let unit, !unit.isEmpty else { return base }
        return "\(base) \(unit)"
    }

    /// "70 – 99", "≤ 190", "≥ 30" or the report's own text.
    var rangeLabel: String? {
        switch (refMin, refMax) {
        case let (min?, max?): return "\(LabResult.number(min)) – \(LabResult.number(max))"
        case let (nil, max?): return "≤ \(LabResult.number(max))"
        case let (min?, nil): return "≥ \(LabResult.number(min))"
        default: return refText
        }
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}

/// A clinical analysis: the lab's report with its results and the documents (PDF or photos).
/// Dates are Lisbon days, "yyyy-MM-dd" (as the week board's).
struct LabReport: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var performedOn: String
    var lab: String?
    var notes: String?
    var results: [LabResult] = []
    var files: [ExamFile] = []

    var outOfRangeCount: Int { results.filter(\.isOutOfRange).count }
}

/// Another exam (ultrasound, ECG, X-ray…): a title, the appointment that requested it and the one
/// that looked at it, and its documents.
struct OtherExam: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var requestedOn: String?
    var viewedOn: String?
    var notes: String?
    var files: [ExamFile] = []

    /// The latest of the two dates, to order the list.
    var sortDay: String { viewedOn ?? requestedOn ?? "" }
}

/// The exams' documents on this iPhone: `Application Support/CalorieBuddy/ExamFiles/<bucket path>`.
/// The sync uploads what the bucket doesn't have and a file made on the dashboard is downloaded the
/// first time it's opened.
enum ExamFileStore {
    private static var root: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("CalorieBuddy/ExamFiles", isDirectory: true)
    }

    static func localURL(for path: String) -> URL { root.appendingPathComponent(path) }

    static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: localURL(for: path).path) }

    static func data(_ path: String) -> Data? { try? Data(contentsOf: localURL(for: path)) }

    @discardableResult
    static func write(_ data: Data, path: String) -> Bool {
        let url = localURL(for: path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func remove(_ path: String) {
        try? FileManager.default.removeItem(at: localURL(for: path))
    }

    /// `<lab|other>/<RECORD ID>/<8 chars>-<safe name>`: letters, digits, `.`, `_` and `-` only.
    static func newPath(kind: String, recordID: UUID, fileName: String) -> String {
        let folded = fileName.folding(options: .diacriticInsensitive, locale: .current)
        let safe = String(folded.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") ? $0 : "_" }.suffix(80))
        return "\(kind)/\(recordID.uuidString)/\(UUID().uuidString.prefix(8))-\(safe.isEmpty ? "file" : safe)"
    }
}
