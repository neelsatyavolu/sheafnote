import CoreGraphics
import Observation
import SwiftUI
import SheafnoteCore

@MainActor @Observable
final class SelectionModel {
    private(set) var pageID: UUID?
    private(set) var strokeIDs: Set<StrokeID> = []
    private(set) var elementIDs: Set<UUID> = []
    /// Page coordinates.
    private(set) var bounds: CGRect?
    /// Drag/resize/rotate in progress.
    var livePreviewTransform: CGAffineTransform = .identity

    var isEmpty: Bool { strokeIDs.isEmpty && elementIDs.isEmpty }

    func select(pageID: UUID, strokeIDs: Set<StrokeID>, elementIDs: Set<UUID>, bounds: CGRect) {
        self.pageID = pageID
        self.strokeIDs = strokeIDs
        self.elementIDs = elementIDs
        self.bounds = bounds
        self.livePreviewTransform = .identity
    }

    func clear() {
        pageID = nil
        strokeIDs = []
        elementIDs = []
        bounds = nil
        livePreviewTransform = .identity
    }
}

struct SelectionSnapshot: Sendable {
    /// `PKDrawing` data
    var strokes: Data
    var elements: [ElementValue]
    var bounds: CGRect
}

/// Editor implements; one undo step per gesture.
@MainActor
protocol SelectionTransforming: AnyObject {
    func apply(_ transform: CGAffineTransform, to selection: SelectionModel, in page: any PageContext) throws
    func delete(selection: SelectionModel, in page: any PageContext) throws
    func duplicate(selection: SelectionModel, in page: any PageContext, offset: CGSize) throws -> SelectionSnapshot
    func recolor(selection: SelectionModel, to colorHex: String, in page: any PageContext) throws
    func setWidth(selection: SelectionModel, to width: Double, in page: any PageContext) throws
}

@MainActor
protocol SelectionAction: AnyObject {
    var id: String { get }
    var title: LocalizedStringResource { get }
    var symbolName: String { get }
    var order: Int { get }
    func isEnabled(for selection: SelectionModel, editor: EditorContext) -> Bool
    func perform(selection: SelectionModel, page: any PageContext, editor: EditorContext) async throws
}

@MainActor
final class SelectionActionRegistry {
    private var storage: [any SelectionAction] = []

    func register(_ action: any SelectionAction) { storage.append(action) }
    var actions: [any SelectionAction] { storage.sorted { $0.order < $1.order } }
}
