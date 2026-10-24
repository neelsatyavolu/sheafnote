import Foundation
import Observation
import SheafnoteCore

/// The one text box being edited in place. Changes live in a working copy and are written back as ONE undoable step
/// when editing ends, so typing never floods the undo stack. A new box is only created if it has text.
@MainActor @Observable
final class TextEditSession {
    private(set) var elementID: UUID?
    private(set) var pageID: UUID?
    private(set) var isNew = false
    var working = TextPayload(text: "")
    var frame: CGRect = .zero

    @ObservationIgnored private weak var page: (any PageContext)?
    @ObservationIgnored private var original: ElementValue?
    @ObservationIgnored private var rotation: Double = 0
    @ObservationIgnored private var zIndex = 0

    var isEditing: Bool { elementID != nil }

    func isEditing(_ id: UUID) -> Bool { elementID == id }

    func isEditing(on pageID: UUID) -> Bool { self.pageID == pageID && isEditing }

    func begin(existing element: ElementValue, on page: any PageContext) {
        guard let payload = element.decoded(TextPayload.self) else { return }
        self.page = page
        pageID = page.pageID
        elementID = element.id
        isNew = false
        original = element
        working = payload
        frame = element.frame
        rotation = element.rotation
        zIndex = element.zIndex
    }

    func beginNew(at point: CGPoint, style: TextPayload, on page: any PageContext) {
        self.page = page
        pageID = page.pageID
        elementID = UUID()
        isNew = true
        original = nil
        working = style
        working.text = ""
        frame = TextBoxLayout.newFrame(at: point, pageSize: page.pageSize)
        rotation = 0
        zIndex = TextBoxLayout.nextZIndex(in: page.elements.all)
    }

    /// Ends editing and writes the result. Returns the stored element, or nil when nothing remains (an empty new box).
    /// If the write fails the edit stays open, so the typed text is not lost and the commit can be retried.
    @discardableResult
    func commit() throws -> ElementValue? {
        guard elementID != nil, page != nil else { reset(); return nil }
        let stored = try write()
        reset()
        return stored
    }

    private func write() throws -> ElementValue? {
        guard let id = elementID, let page else { return nil }
        let height = TextBoxLayout.fittedHeight(contentHeight: TextStyling.contentHeight(for: working, width: frame.width),
                                                current: frame.height)
        let finalFrame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: height)
        let isBlank = working.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isNew {
            guard !isBlank else { return nil }
            let element = ElementValue(id: id, pageID: page.pageID, kind: .text, frame: finalFrame, rotation: rotation,
                                       zIndex: zIndex, payload: PayloadCodec.encode(working))
            return try page.elements.add(element, undoName: LocalizedStringResource("Add Text", table: "Elements"))
        }
        if isBlank {
            try page.elements.remove(ids: [id], undoName: LocalizedStringResource("Delete Text", table: "Elements"))
            return nil
        }
        let payload = PayloadCodec.encode(working)
        guard original?.payload != payload || original?.frame != finalFrame else { return original }
        try page.elements.update(id: id, undoName: LocalizedStringResource("Edit Text", table: "Elements")) {
            $0.payload = payload
            $0.frame = finalFrame
        }
        return page.elements.all.first { $0.id == id }
    }

    /// Drops the edit without writing anything.
    func cancel() { reset() }

    private func reset() {
        elementID = nil
        pageID = nil
        isNew = false
        original = nil
        page = nil
    }
}
