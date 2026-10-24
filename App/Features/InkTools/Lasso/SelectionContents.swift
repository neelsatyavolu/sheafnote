import PencilKit
import UIKit
import SheafnoteCore

/// What a selection holds right now: the strokes and elements it names, read from the page.
@MainActor
struct SelectionContents {
    let pageID: UUID
    let strokes: [IdentifiedStroke]
    let elements: [ElementValue]
    let bounds: CGRect

    /// Nil when nothing is selected or the selection belongs to another page.
    init?(selection: SelectionModel, page: any PageContext) {
        guard !selection.isEmpty, selection.pageID == page.pageID, let bounds = selection.bounds else { return nil }
        self.pageID = page.pageID
        self.strokes = page.ink.strokes.filter { selection.strokeIDs.contains($0.id) }
        self.elements = page.elements.all.filter { selection.elementIDs.contains($0.id) }.sorted { $0.zIndex < $1.zIndex }
        self.bounds = bounds
        if strokes.isEmpty && elements.isEmpty { return nil }
    }

    init(pageID: UUID, strokes: [IdentifiedStroke], elements: [ElementValue], bounds: CGRect) {
        self.pageID = pageID
        self.strokes = strokes
        self.elements = elements
        self.bounds = bounds
    }

    func replacing(strokes: [IdentifiedStroke], elements: [ElementValue]) -> SelectionContents {
        SelectionContents(pageID: pageID, strokes: strokes, elements: elements, bounds: bounds)
    }

    var drawing: PKDrawing { PKDrawing(strokes: strokes.map(\.stroke)) }

    var snapshot: SelectionSnapshot {
        SelectionSnapshot(strokes: strokes.isEmpty ? Data() : drawing.dataRepresentation(), elements: elements, bounds: bounds)
    }

    var shapeElements: [ElementValue] { elements.filter { $0.kind == .shape } }

    /// Strokes whose colour or width can change, and shapes that can.
    var isStyleable: Bool { !strokes.isEmpty || !shapeElements.isEmpty }

    /// The width most strokes and shapes share, for the starting value of the width slider.
    var representativeWidth: Double {
        if let first = strokes.first?.stroke {
            let points = Array(first.path)
            if !points.isEmpty { return points.map { Double($0.size.width) }.reduce(0, +) / Double(points.count) }
        }
        if let shape = shapeElements.first, let payload = PayloadCodec.decode(ShapePayload.self, from: shape.payload) { return payload.lineWidth }
        return 3
    }
}

enum InkToolsError: LocalizedError {
    case nothingToPaste
    case noTextFound
    case imageFailed
    case pageNotReady

    var errorDescription: String? {
        switch self {
        case .nothingToPaste: String(localized: "There is nothing to paste. Copy something in Sheafnote or copy an image first.", table: "InkTools")
        case .noTextFound: String(localized: "No handwriting could be read in the selection. Try selecting only the writing.", table: "InkTools")
        case .imageFailed: String(localized: "The image of the selection could not be created.", table: "InkTools")
        case .pageNotReady: String(localized: "This page is not ready to be changed yet. Try again in a moment.", table: "InkTools")
        }
    }
}
