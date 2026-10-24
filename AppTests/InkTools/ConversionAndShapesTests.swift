import PencilKit
import SwiftUI
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct TextConversionTests {
    func writtenPage(_ f: InkToolsFixture) async throws -> (PageSession, SelectionContents) {
        let page = try f.page()
        page.setDrawing(PKDrawing(strokes: [InkSketch.line(CGPoint(x: 100, y: 100), CGPoint(x: 260, y: 110), width: 4),
                                            InkSketch.line(CGPoint(x: 100, y: 140), CGPoint(x: 220, y: 150), width: 4)]), undoName: "Draw")
        f.select([0, 1], on: page)
        await InkToolsFixture.settle()
        return (page, try #require(SelectionContents(selection: f.session.selection, page: page)))
    }

    @Test func recognizedTextComesFromTheRecognizerWithTheInkRenderedBlackOnWhite() async throws {
        let f = try InkToolsFixture(recognizedText: "meeting notes")
        let (_, contents) = try await writtenPage(f)
        #expect(try await TextConversion(host: f.host).recognizedText(for: contents) == "meeting notes")
        let image = try await SelectionImageRenderer(host: f.host).handwritingImage(of: contents)
        #expect(image.width > 100 && InkSketch.alpha(of: image, x: 2, y: 2) == 255, "opaque white background")
    }

    @Test func nothingReadableIsReportedNotInserted() async throws {
        let f = try InkToolsFixture(recognizedText: "")
        let (page, contents) = try await writtenPage(f)
        await #expect(throws: InkToolsError.self) { try await TextConversion(host: f.host).recognizedText(for: contents) }
        #expect(page.elements.all.isEmpty)
    }

    @Test func insertAddsATextBoxAndKeepsTheInk() async throws {
        let f = try InkToolsFixture()
        let (page, contents) = try await writtenPage(f)
        try TextConversion(host: f.host).place("hello world", over: contents, page: page, editor: f.session, replacing: false)
        let element = try #require(page.elements.all.first)
        let payload = try #require(PayloadCodec.decode(TextPayload.self, from: element.payload))
        #expect(element.kind == .text && payload.text == "hello world" && payload.colorHex == "#000000")
        #expect(element.frame.minX <= contents.bounds.minX + 0.5 && element.frame.minY <= contents.bounds.minY + 0.5)
        #expect(page.drawing.strokes.count == 2, "the handwriting stays")
        #expect(f.session.selection.elementIDs == [element.id])
        #expect(f.services.revisions.revisions(for: page.pageID).isEmpty)
    }

    @Test func replaceSavesACopyFirstAndUndoRestoresBoth() async throws {
        let f = try InkToolsFixture()
        let (page, contents) = try await writtenPage(f)
        page.flush()
        try TextConversion(host: f.host).place("hello world", over: contents, page: page, editor: f.session, replacing: true)
        #expect(page.drawing.strokes.isEmpty && page.elements.all.count == 1)
        let copies = f.services.revisions.revisions(for: page.pageID)
        #expect(copies.count == 1 && copies[0].reason == RevisionReason.beforeClear.rawValue)
        #expect(copies[0].inkData != nil, "the saved copy holds the handwriting")

        await InkToolsFixture.settle()
        f.session.undo()
        #expect(page.drawing.strokes.count == 2 && page.elements.all.isEmpty, "one undo reverses the whole replace")
    }

    @Test func replaceOnlyRemovesTheSelectedStrokes() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        page.setDrawing(PKDrawing(strokes: [InkSketch.line(CGPoint(x: 100, y: 100), CGPoint(x: 260, y: 110)),
                                            InkSketch.line(CGPoint(x: 100, y: 500), CGPoint(x: 260, y: 510))]), undoName: "Draw")
        f.select([0], on: page)
        await InkToolsFixture.settle()
        let contents = try #require(SelectionContents(selection: f.session.selection, page: page))
        try TextConversion(host: f.host).place("one line", over: contents, page: page, editor: f.session, replacing: true)
        #expect(page.drawing.strokes.count == 1 && page.drawing.strokes[0].renderBounds.minY > 400)
    }

    @Test func convertActionNeedsInkAndOpensTheSheet() async throws {
        let f = try InkToolsFixture()
        let (page, _) = try await writtenPage(f)
        let convert = try f.action("ink.convertText")
        #expect(convert.isEnabled(for: f.session.selection, editor: f.session))
        try await convert.perform(selection: f.session.selection, page: page, editor: f.session)
        #expect(f.session.sheet != nil)
        let shape = try f.addShape(.line(from: .zero, to: CGPoint(x: 50, y: 0)), to: page)
        f.session.selection.select(pageID: page.pageID, strokeIDs: [], elementIDs: [shape.id], bounds: shape.frame)
        #expect(!convert.isEnabled(for: f.session.selection, editor: f.session))
    }
}

@MainActor
@Suite struct ShapesToolTests {
    let squarePath = InkSketch.loop(around: CGRect(x: 150, y: 200, width: 160, height: 160))

    @Test func aDrawnSquareBecomesAShapeElementThatIsSelected() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        f.shapes.commit(squarePath, page: page, editor: f.session)
        let element = try #require(page.elements.all.first)
        #expect(element.kind == .shape && page.drawing.strokes.isEmpty)
        guard case .rectangle(let center, let size, let rotation)? = ShapeElementGeometry.figure(of: element) else {
            Issue.record("not a rectangle"); return
        }
        #expect(abs(center.x - 230) < 2 && abs(size.width - 160) < 3 && rotation == 0)
        #expect(f.session.selection.elementIDs == [element.id])
        await InkToolsFixture.settle()
        f.session.undo()
        #expect(page.elements.all.isEmpty)
        await InkToolsFixture.settle()
        #expect(f.session.selection.isEmpty, "undo must not leave handles around a shape that is gone")
    }

    @Test func optionsDecideColoursWidthAndFill() throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        f.settings.updateShape { $0.strokeHex = "#D6336C"; $0.fillHex = "#FFE066"; $0.lineWidth = 6 }
        f.shapes.commit(InkSketch.circle(center: CGPoint(x: 300, y: 300), radius: 80), page: page, editor: f.session)
        let payload = try f.shapePayload(on: page)
        #expect(payload.shapeKind == .ellipse && payload.strokeHex == "#D6336C" && payload.fillHex == "#FFE066" && payload.lineWidth == 6)
    }

    @Test func openShapesDoNotKeepTheFill() throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        f.settings.updateShape { $0.fillHex = "#FFE066" }
        f.shapes.commit(InkSketch.samples([CGPoint(x: 100, y: 100), CGPoint(x: 400, y: 104)], step: 4), page: page, editor: f.session)
        let payload = try f.shapePayload(on: page)
        #expect(payload.shapeKind == .line && payload.fillHex == nil)
    }

    @Test func fixedKindsBuildFromTheDrag() throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        for (mode, kind) in [(ShapeMode.arrow, ShapeKind.arrow), (.triangle, .triangle), (.polygon, .polygon), (.ellipse, .ellipse)] {
            f.settings.updateShape { $0.mode = mode }
            f.shapes.commit([CGPoint(x: 100, y: 100), CGPoint(x: 260, y: 220)], page: page, editor: f.session)
            #expect(page.elements.all.last?.kind == .shape)
            let latest = try #require(page.elements.all.last)
            let figure = try #require(ShapeElementGeometry.figure(of: latest))
            #expect(figure.kind == kind)
        }
        #expect(page.elements.all.count == 4)
    }

    @Test func aGestureThatIsNoShapeStaysAsInkInTheOutlineColour() throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        f.settings.updateShape { $0.strokeHex = "#2F5BEA"; $0.lineWidth = 6 }
        f.shapes.commit(InkSketch.randomWalk(), page: page, editor: f.session)
        #expect(page.elements.all.isEmpty && page.drawing.strokes.count == 1)
        #expect(page.drawing.strokes[0].ink.color.hexString == "#2F5BEA")
    }

    @Test func aTapInAFixedModeDrawsNothing() throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        f.settings.updateShape { $0.mode = .rectangle }
        f.shapes.commit([CGPoint(x: 100, y: 100), CGPoint(x: 103, y: 102)], page: page, editor: f.session)
        #expect(page.elements.all.isEmpty && page.drawing.strokes.isEmpty)
    }

    @Test func newShapesStackAboveEarlierOnes() throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        f.shapes.commit(squarePath, page: page, editor: f.session)
        f.shapes.commit(InkSketch.circle(center: CGPoint(x: 230, y: 280), radius: 60), page: page, editor: f.session)
        #expect(page.elements.all.map(\.zIndex).sorted() == [1, 2])
    }
}

@MainActor
@Suite struct ShapeRendererTests {
    func render(_ element: ElementValue, in f: InkToolsFixture, size: Int = 300) async throws -> CGImage {
        let ctx = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)
        let renderer = try #require(f.host.elementRenderers.renderer(for: .shape))
        try await renderer.draw(element, into: ctx, assets: f.services.pages, options: .screen)
        return try #require(ctx.makeImage())
    }

    @Test func outlineIsDrawnAndTheInsideStaysClearWithoutAFill() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let element = try f.addShape(.rectangle(center: CGPoint(x: 150, y: 150), size: CGSize(width: 160, height: 100), rotation: 0), to: page, width: 6)
        let image = try await render(element, in: f)
        #expect(InkSketch.alpha(of: image, x: 150, y: 100) > 200, "top edge")
        #expect(InkSketch.alpha(of: image, x: 150, y: 150) == 0, "hollow")
        #expect(InkSketch.alpha(of: image, x: 10, y: 10) == 0)
    }

    @Test func fillCoversTheInside() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let element = try f.addShape(.ellipse(center: CGPoint(x: 150, y: 150), radii: CGSize(width: 70, height: 50), rotation: 0), to: page, fill: "#FF0000")
        let image = try await render(element, in: f)
        #expect(InkSketch.alpha(of: image, x: 150, y: 150) == 255)
        #expect(InkSketch.alpha(of: image, x: 150 + 90, y: 150) == 0)
    }

    @Test func rotationTurnsTheDrawing() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        var element = try f.addShape(.line(from: CGPoint(x: 50, y: 150), to: CGPoint(x: 250, y: 150)), to: page, width: 8)
        element.rotation = .pi / 2
        let image = try await render(element, in: f)
        #expect(InkSketch.alpha(of: image, x: 150, y: 70) > 200, "the line now runs top to bottom")
        #expect(InkSketch.alpha(of: image, x: 70, y: 150) == 0)
    }

    @Test func brokenPayloadDrawsNothingAndDoesNotThrow() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let broken = ElementValue(pageID: page.pageID, kind: .shape, frame: CGRect(x: 0, y: 0, width: 100, height: 100), payload: Data([1, 2, 3]))
        let image = try await render(broken, in: f)
        #expect(InkSketch.alpha(of: image, x: 50, y: 50) == 0)
    }

    @Test func hitTesterIsTheOutlineOne() throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let element = try f.addShape(.line(from: .zero, to: CGPoint(x: 200, y: 200)), to: page)
        let renderer = try #require(f.host.elementRenderers.renderer(for: .shape))
        let tester = renderer.hitTester(for: element)
        #expect(tester is ShapeHitTester)
        #expect(f.host.elementRenderers.renderer(for: .shape)?.slot == .belowInk)
    }

    @Test func beginEditingSelectsTheShape() throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let element = try f.addShape(.rectangle(center: CGPoint(x: 100, y: 100), size: CGSize(width: 50, height: 50), rotation: 0), to: page)
        let renderer = try #require(f.host.elementRenderers.renderer(for: .shape))
        renderer.beginEditing(element, page: page, editor: f.session)
        #expect(f.session.selection.elementIDs == [element.id])
    }
}
