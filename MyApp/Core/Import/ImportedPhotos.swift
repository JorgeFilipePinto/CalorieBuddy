import Foundation

/// Photos taken in the AI import sheet to stay with what it creates: the article's and, for food, its
/// nutrition label's, as JPEG data. (Nothing on a Mac, where the sheet has no photo controls.)
struct ImportedPhotos {
    var product: Data?
    var label: Data?

    var isEmpty: Bool { product == nil && label == nil }
}

extension PhotoStore {
    /// Stores JPEG data under a new id (the photo was already downscaled and compressed), or `nil` if it couldn't be written.
    static func save(jpeg data: Data) -> UUID? {
        let id = UUID()
        do {
            try write(data, id: id)
            return id
        } catch {
            return nil
        }
    }
}
