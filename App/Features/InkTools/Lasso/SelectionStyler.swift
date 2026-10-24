import PencilKit
import UIKit
import SheafnoteCore

/// Colour, width and fill changes for a selection, each one undo step. Ink goes through the editor's selection
/// transformer (which also keeps the selection pointing at the re-identified strokes); shapes are updated here.
@MainActor
struct SelectionStyler {
    let selection: SelectionModel
    let page: any PageContext
    let editor: EditorContext

    var contents: SelectionContents? { SelectionContents(selection: selection, page: page) }

    func recolor(_ hex: String) throws {
        try grouped {
            if !selection.strokeIDs.isEmpty { try editor.selectionTransformer.recolor(selection: selection, to: hex, in: page) }
            try updateShapes(LocalizedStringResource("Change Color", table: "InkTools")) { ShapeElementGeometry.restyled($0, strokeHex: hex) }
        }
    }

    func setWidth(_ width: Double) throws {
        try grouped {
            if !selection.strokeIDs.isEmpty { try editor.selectionTransformer.setWidth(selection: selection, to: width, in: page) }
            try updateShapes(LocalizedStringResource("Change Width", table: "InkTools")) { ShapeElementGeometry.restyled($0, lineWidth: width) }
        }
    }

    func setFill(_ hex: String?) throws {
        try grouped {
            try updateShapes(LocalizedStringResource("Change Fill", table: "InkTools")) { ShapeElementGeometry.refilled($0, fillHex: hex) }
        }
    }

    // MARK: Helpers

    private func updateShapes(_ name: LocalizedStringResource, _ change: (ElementValue) -> ElementValue) throws {
        for element in contents?.shapeElements ?? [] {
            let updated = change(element)
            try page.elements.update(id: element.id, undoName: name) { $0.payload = updated.payload }
        }
    }

    private func grouped(_ body: () throws -> Void) throws {
        let manager = editor.undoManager
        manager.beginUndoGrouping()
        defer { manager.endUndoGrouping() }
        try body()
    }
}
