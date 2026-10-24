import PencilKit
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct InkModelTests {
    private let a = CGPoint(x: 10, y: 10), b = CGPoint(x: 200, y: 120)

    // MARK: StrokeRecord adapter

    @Test func strokeIDIsStableAcrossDrawingDataRoundTrip() throws {
        let drawing = PKDrawing(strokes: [TestInk.stroke(from: a, to: b), TestInk.stroke(from: b, to: a, color: .red)])
        let restored = try PKDrawing(data: drawing.dataRepresentation())
        #expect(drawing.strokeIDs == restored.strokeIDs)
        #expect(Set(drawing.strokeIDs).count == 2)
    }

    @Test func strokeIDChangesWithEveryVisibleProperty() {
        let base = TestInk.stroke(from: a, to: b)
        let id = base.strokeID
        #expect(TestInk.stroke(from: a, to: b, color: .blue).strokeID != id)
        #expect(TestInk.stroke(from: a, to: b, type: .pencil).strokeID != id)
        #expect(TestInk.stroke(from: a, to: CGPoint(x: 201, y: 120)).strokeID != id)
        #expect(TestInk.stroke(from: a, to: b, date: Date(timeIntervalSinceReferenceDate: 2_000)).strokeID != id)
        var moved = base
        moved.transform = CGAffineTransform(translationX: 5, y: 0)
        #expect(moved.strokeID != id)
        #expect(TestInk.stroke(from: a, to: b).strokeID == id)
    }

    @Test func recordCarriesInkColorTransformAndPoints() {
        var stroke = TestInk.stroke(from: a, to: b, type: .marker, color: UIColor(red: 1, green: 0, blue: 0, alpha: 1))
        stroke.transform = CGAffineTransform(translationX: 3, y: 4)
        let record = stroke.strokeRecord
        #expect(record.inkType == PKInk.InkType.marker.rawValue)
        #expect(record.colorRGBA.prefix(3) == [1, 0, 0])
        #expect(record.transform == [1, 0, 0, 1, 3, 4])
        #expect(record.points.count == 13 && record.points[0].x == 10)
    }

    // MARK: Colors

    @Test func hexRoundTrip() {
        for hex in ["#1B1B1F", "#FFE066", "#000000", "#FFFFFF"] {
            #expect(UIColor(hex: hex).hexString == hex)
        }
        #expect(UIColor(hex: "garbage").hexString == "#000000")
    }

    // MARK: Marker eraser

    @Test func markerEraserHitsOnlyHighlighterStrokes() {
        let pen = TestInk.stroke(from: CGPoint(x: 0, y: 100), to: CGPoint(x: 300, y: 100), type: .pen)
        let marker = TestInk.stroke(from: CGPoint(x: 0, y: 100), to: CGPoint(x: 300, y: 100), type: .marker, width: 20)
        let far = TestInk.stroke(from: CGPoint(x: 0, y: 500), to: CGPoint(x: 300, y: 500), type: .marker, width: 20)
        let drawing = PKDrawing(strokes: [pen, marker, far])
        let hits = MarkerEraser.markerStrokeIndices(in: drawing, near: [CGPoint(x: 150, y: 104)], radius: 8)
        #expect(hits == [1])
        let after = MarkerEraser.removing(hits, from: drawing)
        #expect(after.strokes.count == 2)
        #expect(after.strokes.map { $0.ink.inkType } == [.pen, .marker])
    }

    @Test func markerEraserIgnoresTouchesAwayFromStrokes() {
        let marker = TestInk.stroke(from: CGPoint(x: 0, y: 100), to: CGPoint(x: 300, y: 100), type: .marker, width: 20)
        let drawing = PKDrawing(strokes: [marker])
        #expect(MarkerEraser.markerStrokeIndices(in: drawing, near: [CGPoint(x: 150, y: 200)], radius: 8).isEmpty)
        #expect(MarkerEraser.markerStrokeIndices(in: drawing, near: [], radius: 8).isEmpty)
        #expect(MarkerEraser.removing([], from: drawing).strokes.count == 1)
    }

    // MARK: Presets

    /// Held so the in-memory SwiftData container outlives the settings store's ModelContext.
    private let services = try! AppServices.inMemory()

    private func store() throws -> EditorPresetStore {
        EditorPresetStore(settings: services.settings)
    }

    @Test func defaultsHaveColorsAndThreeWidths() throws {
        let s = try store()
        #expect(s.presets(for: .pen).count == 4)
        #expect(s.widths(for: .pen).values.count == 3)
        #expect(s.inkKind(for: .pen) == .pen)
        #expect(s.inkKind(for: .highlighter) == .marker)
        #expect(s.selectedPresetID(for: .pen) == s.presets(for: .pen).first?.id)
        #expect(s.widths(for: .eraser).values.count == 3)
    }

    @Test func selectionAndEditsPersistThroughSettings() throws {
        let services = try AppServices.inMemory()
        let s = EditorPresetStore(settings: services.settings)
        let second = s.presets(for: .pen)[1]
        s.selectPreset(second.id, for: .pen)
        s.updateSelectedColor(hex: "#123456", for: .pen)
        s.selectWidth(index: 2, for: .pen)
        s.setInkKind(.fountainPen, for: .pen)

        let reopened = EditorPresetStore(settings: services.settings)
        #expect(reopened.selectedPresetID(for: .pen) == second.id)
        #expect(reopened.selectedPreset(for: .pen)?.colorHex == "#123456")
        #expect(reopened.widths(for: .pen).selected == 6)
        #expect(reopened.presets(for: .pen).allSatisfy { $0.inkKind == .fountainPen })
        #expect(s.revision > 0)
    }

    @Test func addingColorsIsCappedAndSelectsTheNewOne() throws {
        let s = try store()
        for i in 0..<10 { s.addColor(hex: String(format: "#0000%02X", i), for: .pen, maxCount: 6) }
        #expect(s.presets(for: .pen).count == 6)
        #expect(s.selectedPreset(for: .pen)?.colorHex == "#000009")
    }

    @Test func toolFactoryClampsWidthToTheInkRange() {
        let tool = InkToolFactory.pencilKitTool(kind: .pen, colorHex: "#FF0000", width: 10_000)
        #expect(tool.width == PKInkingTool.InkType.pen.validWidthRange.upperBound)
        let thin = InkToolFactory.pencilKitTool(kind: .monoline, colorHex: "#FF0000", width: 0)
        #expect(thin.width == PKInkingTool.InkType.monoline.validWidthRange.lowerBound)
        #expect(InkKind.allCases.map(\.pkType).count == 7)
    }

    @Test func configuratorBuildsMarkerForHighlighterAndEraserModes() throws {
        let s = try store()
        let marker = ToolConfigurator.inkingTool(for: .highlighter, store: s)
        #expect(marker.inkType == .marker)
        #expect(ToolConfigurator.inkingTool(for: .pen, store: s).inkType == .pen)
        #expect(ToolConfigurator.eraserTool(mode: .stroke, store: s).eraserType == .vector)
        // With an explicit width PencilKit reports the fixed-width bitmap variant.
        #expect(ToolConfigurator.eraserTool(mode: .partial, store: s).eraserType != .vector)
    }

    @Test func preferencesPersist() throws {
        let services = try AppServices.inMemory()
        let prefs = EditorPreferences(settings: services.settings)
        prefs.values.doubleTap = .showPalette
        prefs.inputMode = .pencilOnly
        prefs.values.eraserSwitchBack = true
        let again = EditorPreferences(settings: services.settings)
        #expect(again.values.doubleTap == .showPalette)
        #expect(again.inputMode == .pencilOnly)
        #expect(again.values.eraserSwitchBack)
    }
}
