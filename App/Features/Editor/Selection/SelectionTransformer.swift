import PencilKit
import UIKit
import SheafnoteCore

/// Applies selection edits (move/scale/rotate, delete, duplicate, recolor, width) to ink and elements as ONE undo step.
/// Ink edits go through `PageInk`, so stroke ids are recomputed and the page is saved like any other change.
@MainActor
final class SelectionTransformer: SelectionTransforming {
    private unowned let session: NotebookSession

    init(session: NotebookSession) { self.session = session }

    func apply(_ transform: CGAffineTransform, to selection: SelectionModel, in page: any PageContext) throws {
        guard let page = page as? PageSession, let bounds = selection.bounds, !selection.isEmpty else { return }
        let name: LocalizedStringResource = isPureTranslation(transform)
            ? LocalizedStringResource("Move", table: "Editor") : LocalizedStringResource("Transform", table: "Editor")
        try grouped {
            var newIDs = selection.strokeIDs
            if !selection.strokeIDs.isEmpty {
                let indices = page.inkAccess.indices(of: selection.strokeIDs)
                newIDs = page.inkAccess.edit(name, indices: indices) { $0.transform = $0.transform.concatenating(transform) }
            }
            for id in selection.elementIDs {
                guard let element = page.elementValues.first(where: { $0.id == id }) else { continue }
                let moved = hitTester(for: element).transformed(by: transform)
                try page.elementStore.update(id: id, undoName: name) { $0 = moved }
            }
            selection.select(pageID: page.pageID, strokeIDs: newIDs, elementIDs: selection.elementIDs,
                             bounds: SelectionGeometry.bounds(of: bounds, under: transform))
        }
    }

    func delete(selection: SelectionModel, in page: any PageContext) throws {
        guard let page = page as? PageSession, !selection.isEmpty else { return }
        let name = LocalizedStringResource("Delete", table: "Editor")
        try grouped {
            if !selection.strokeIDs.isEmpty {
                let indices = page.inkAccess.indices(of: selection.strokeIDs)
                page.inkAccess.edit(name) { strokes in
                    strokes = strokes.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
                }
            }
            if !selection.elementIDs.isEmpty { try page.elementStore.remove(ids: selection.elementIDs, undoName: name) }
            selection.clear()
        }
    }

    func duplicate(selection: SelectionModel, in page: any PageContext, offset: CGSize) throws -> SelectionSnapshot {
        guard let page = page as? PageSession, !selection.isEmpty else {
            return SelectionSnapshot(strokes: PKDrawing().dataRepresentation(), elements: [], bounds: .zero)
        }
        // A zero offset would produce strokes with identical ids, so always nudge.
        let shift = offset == .zero ? CGSize(width: 16, height: 16) : offset
        let t = CGAffineTransform(translationX: shift.width, y: shift.height)
        let name = LocalizedStringResource("Duplicate", table: "Editor")
        var copiedStrokes: [PKStroke] = []
        var copiedElements: [ElementValue] = []
        try grouped {
            let indices = page.inkAccess.indices(of: selection.strokeIDs)
            copiedStrokes = indices.sorted().map { i in
                var stroke = page.drawing.strokes[i]
                stroke.transform = stroke.transform.concatenating(t)
                return stroke
            }
            if !copiedStrokes.isEmpty { page.inkAccess.edit(name) { $0.append(contentsOf: copiedStrokes) } }
            let top = (page.elementValues.map(\.zIndex).max() ?? 0)
            for (n, element) in page.elementValues.filter({ selection.elementIDs.contains($0.id) }).enumerated() {
                var copy = hitTester(for: element).transformed(by: t)
                copy.id = UUID()
                copy.zIndex = top + 1 + n
                copiedElements.append(try page.elementStore.add(copy, undoName: name))
            }
        }
        let bounds = (selection.bounds ?? .zero).applying(t)
        return SelectionSnapshot(strokes: PKDrawing(strokes: copiedStrokes).dataRepresentation(), elements: copiedElements, bounds: bounds)
    }

    func recolor(selection: SelectionModel, to colorHex: String, in page: any PageContext) throws {
        try restyle(selection, in: page, name: LocalizedStringResource("Change Color", table: "Editor")) { stroke in
            let ink = PKInk(stroke.ink.inkType, color: UIColor(hex: colorHex))
            return PKStroke(ink: ink, path: stroke.path, transform: stroke.transform, mask: stroke.mask)
        }
    }

    func setWidth(selection: SelectionModel, to width: Double, in page: any PageContext) throws {
        try restyle(selection, in: page, name: LocalizedStringResource("Change Width", table: "Editor")) { stroke in
            let points = Array(stroke.path)
            guard !points.isEmpty else { return stroke }
            let current = points.map { Double($0.size.width) }.reduce(0, +) / Double(points.count)
            let factor = current > 0 ? CGFloat(width / current) : 1
            let resized = points.map {
                PKStrokePoint(location: $0.location, timeOffset: $0.timeOffset,
                              size: CGSize(width: $0.size.width * factor, height: $0.size.height * factor),
                              opacity: $0.opacity, force: $0.force, azimuth: $0.azimuth, altitude: $0.altitude)
            }
            let path = PKStrokePath(controlPoints: resized, creationDate: stroke.path.creationDate)
            return PKStroke(ink: stroke.ink, path: path, transform: stroke.transform, mask: stroke.mask)
        }
    }

    // MARK: Helpers

    private func restyle(_ selection: SelectionModel, in page: any PageContext, name: LocalizedStringResource,
                         _ change: (PKStroke) -> PKStroke) throws {
        guard let page = page as? PageSession, let bounds = selection.bounds, !selection.strokeIDs.isEmpty else { return }
        let indices = page.inkAccess.indices(of: selection.strokeIDs)
        let newIDs = page.inkAccess.edit(name, indices: indices) { $0 = change($0) }
        selection.select(pageID: page.pageID, strokeIDs: newIDs, elementIDs: selection.elementIDs, bounds: bounds)
    }

    private func hitTester(for element: ElementValue) -> any ElementHitTesting {
        session.host.elementRenderers.renderer(for: element.kind)?.hitTester(for: element) ?? OrientedBoxHitTester(element: element)
    }

    private func isPureTranslation(_ t: CGAffineTransform) -> Bool {
        abs(t.a - 1) < 1e-9 && abs(t.d - 1) < 1e-9 && abs(t.b) < 1e-9 && abs(t.c) < 1e-9
    }

    /// One undo step for everything the closure changes.
    private func grouped(_ body: () throws -> Void) throws {
        let manager = session.undoManager
        manager.beginUndoGrouping()
        defer { manager.endUndoGrouping() }
        try body()
    }
}
