import Foundation
import SwiftData

/// Finds every `Asset` that something still points at. Shared by the orphan purge (what may be deleted) and the
/// archive exporter (what must be included), so the two can never disagree.
///
/// Besides the plain `assetID` columns, assets are referenced from inside JSON blobs: saved elements, page
/// revisions (`[ElementValue]`) and text documents (image blocks). Those blobs are scanned for `assetID` keys, which
/// keeps the scan correct if a payload gains new fields.
enum AssetReferences {
    /// UUIDs stored under an `assetID` key anywhere in the JSON.
    static func ids(inJSON data: Data?) -> Set<UUID> {
        guard let data, !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return [] }
        var found = Set<UUID>()
        collect(object, into: &found)
        return found
    }

    private static func collect(_ value: Any, into found: inout Set<UUID>) {
        if let array = value as? [Any] {
            for item in array { collect(item, into: &found) }
        } else if let dict = value as? [String: Any] {
            for (key, item) in dict {
                if key == "assetID", let text = item as? String, let id = UUID(uuidString: text) {
                    found.insert(id)
                } else {
                    collect(item, into: &found)
                }
            }
        }
    }

    /// References held by saved elements and text documents (the ones that live inside JSON blobs of alive and
    /// soft-deleted rows alike: a restored row must find its picture).
    @MainActor
    static func blobReferences(in context: ModelContext) throws -> Set<UUID> {
        var used = Set<UUID>()
        for saved in try context.fetch(FetchDescriptor<SavedElement>()) { used.formUnion(ids(inJSON: saved.elements)) }
        for revision in try context.fetch(FetchDescriptor<PageRevision>()) { used.formUnion(ids(inJSON: revision.elements)) }
        for notebook in try context.fetch(FetchDescriptor<Notebook>()) { used.formUnion(ids(inJSON: notebook.richText)) }
        return used
    }

    /// Every asset id referenced by any row in the store.
    @MainActor
    static func allReferenced(in context: ModelContext) throws -> Set<UUID> {
        var used = Set(try context.fetch(FetchDescriptor<Page>()).compactMap(\.backgroundAssetID))
        used.formUnion(try context.fetch(FetchDescriptor<PageElement>()).compactMap(\.assetID))
        used.formUnion(try context.fetch(FetchDescriptor<AudioRecording>()).map(\.assetID))
        used.formUnion(try blobReferences(in: context))
        return used
    }
}
