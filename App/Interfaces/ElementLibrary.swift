import CoreGraphics
import Foundation

struct SavedElementValue: Identifiable, Sendable {
    var id: UUID
    var name: String
    var category: String
    var size: CGSize
    var thumbnail: Data
}

/// Saved elements ("Save as element"). Implementation: `ElementLibraryStore` in App/Shell.
@MainActor
protocol ElementLibrary: AnyObject {
    func all() throws -> [SavedElementValue]
    @discardableResult func save(name: String, category: String, from snapshot: SelectionSnapshot, thumbnail: Data) throws -> SavedElementValue
    func rename(id: UUID, to name: String) throws
    /// Soft delete, synced.
    func delete(id: UUID) throws
    func insert(_ saved: SavedElementValue, into page: any PageContext, at center: CGPoint, scale: CGFloat) throws -> SelectionSnapshot
}
