import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Photos of foods, recipes, supplements and the physical-progress log. Kept as JPEG files next
/// to the database (`Application Support/CalorieBuddy/Photos/<id>.jpg`), not inside the JSON:
/// a handful of photos would otherwise make every save rewrite megabytes. Models only hold the
/// photo's id.
///
/// Files are written with complete file protection — progress photos are personal, so they're
/// unreadable while the iPhone is locked.
enum PhotoStore {
    /// Longest side kept: plenty for full-screen viewing, small enough to keep the folder light.
    static let maxDimension: CGFloat = 1600
    /// Longest side of the cached list thumbnails.
    static let thumbnailDimension: CGFloat = 200

    static var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("CalorieBuddy/Photos", isDirectory: true)
    }

    static func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    static func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    static func delete(_ id: UUID?) {
        guard let id else { return }
        try? FileManager.default.removeItem(at: url(for: id))
        #if canImport(UIKit)
        thumbnailCache.removeObject(forKey: id.uuidString as NSString)
        #endif
    }

    /// Removes every stored photo (used by "Eliminar Todos os Dados").
    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
        #if canImport(UIKit)
        thumbnailCache.removeAllObjects()
        #endif
    }

    /// The stored JPEG, as sent to the platform.
    static func data(_ id: UUID) -> Data? {
        try? Data(contentsOf: url(for: id))
    }

    /// Stores a JPEG that already has an id (a photo downloaded from the platform on restore).
    static func write(_ data: Data, id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(for: id), options: [.atomic, .completeFileProtection])
    }

    /// Ids of every photo file on disk, e.g. to find ones no record points at any more.
    static func storedIDs() -> Set<UUID> {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(files.compactMap { UUID(uuidString: ($0 as NSString).deletingPathExtension) })
    }

    #if canImport(UIKit)
    private static let thumbnailCache = NSCache<NSString, UIImage>()

    /// Saves `image` (downscaled, JPEG) and returns its new id, or `nil` if it couldn't be written.
    static func save(_ image: UIImage) -> UUID? {
        let id = UUID()
        guard let data = image.downscaled(maxDimension: maxDimension).jpegData(compressionQuality: 0.8) else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(for: id), options: [.atomic, .completeFileProtection])
            return id
        } catch {
            return nil
        }
    }

    static func image(_ id: UUID) -> UIImage? {
        UIImage(contentsOfFile: url(for: id).path)
    }

    /// A small version for lists, cached in memory so scrolling doesn't re-decode full photos.
    static func thumbnail(_ id: UUID) -> UIImage? {
        let key = id.uuidString as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let image = image(id)?.downscaled(maxDimension: thumbnailDimension) else { return nil }
        thumbnailCache.setObject(image, forKey: key)
        return image
    }
    #endif
}
