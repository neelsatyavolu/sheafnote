import CoreGraphics
import Foundation
import PencilKit
import SheafnoteCore

enum ElementLibraryError: LocalizedError {
    case unreadableInk
    case missing

    var errorDescription: String? {
        switch self {
        case .unreadableInk: String(localized: "The saved drawing could not be read.")
        case .missing: String(localized: "That saved element no longer exists.")
        }
    }
}

/// Saved elements: Core persists the rows, this adapts them to selections and pages (needs PencilKit).
@MainActor
final class ElementLibraryStore: ElementLibrary {
    private let store: SavedElementStore

    init(store: SavedElementStore) { self.store = store }

    func all() throws -> [SavedElementValue] {
        try store.all().map { SavedElementValue(id: $0.id, name: $0.name, category: $0.category, size: $0.size, thumbnail: $0.thumbnail) }
    }

    @discardableResult
    func save(name: String, category: String, from snapshot: SelectionSnapshot, thumbnail: Data) throws -> SavedElementValue {
        let toOrigin = CGAffineTransform(translationX: -snapshot.bounds.minX, y: -snapshot.bounds.minY)
        var inkData: Data?
        if !snapshot.strokes.isEmpty {
            guard let drawing = try? PKDrawing(data: snapshot.strokes) else { throw ElementLibraryError.unreadableInk }
            inkData = drawing.transformed(using: toOrigin).dataRepresentation()
        }
        let elements = snapshot.elements.map { OrientedBoxHitTester(element: $0).transformed(by: toOrigin) }
        let record = try store.save(name: name, category: category, size: snapshot.bounds.size,
                                    inkData: inkData, elements: elements, thumbnail: thumbnail)
        return SavedElementValue(id: record.id, name: record.name, category: record.category,
                                 size: record.size, thumbnail: record.thumbnail)
    }

    func rename(id: UUID, to name: String) throws { try store.rename(id: id, to: name) }
    func delete(id: UUID) throws { try store.delete(id: id) }

    func insert(_ saved: SavedElementValue, into page: any PageContext, at center: CGPoint, scale: CGFloat) throws -> SelectionSnapshot {
        guard let record = try store.all().first(where: { $0.id == saved.id }) else { throw ElementLibraryError.missing }
        let size = CGSize(width: record.size.width * scale, height: record.size.height * scale)
        let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        let transform = CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale)

        var strokeData = Data()
        if let ink = record.inkData, !ink.isEmpty {
            guard let drawing = try? PKDrawing(data: ink) else { throw ElementLibraryError.unreadableInk }
            let moved = drawing.transformed(using: transform)
            page.ink.edit("Insert Element") { $0.append(contentsOf: moved.strokes) }
            strokeData = moved.dataRepresentation()
        }
        var added: [ElementValue] = []
        for element in record.elements {
            var copy = OrientedBoxHitTester(element: element).transformed(by: transform)
            copy.id = UUID()
            copy.pageID = page.pageID
            added.append(try page.elements.add(copy, undoName: "Insert Element"))
        }
        return SelectionSnapshot(strokes: strokeData, elements: added, bounds: CGRect(origin: origin, size: size))
    }
}
