import PencilKit
import SwiftUI
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

/// Reads back fixed text instead of running Vision, so conversion tests are fast and exact.
struct StubRecognizer: HandwritingRecognizing {
    var text: String

    func recognizeText(in image: CGImage, languages: [String]) async throws -> RecognizedText {
        text.isEmpty ? RecognizedText(lines: []) : RecognizedText(lines: [RecognizedLine(text: text, confidence: 1, boundingBox: .zero)])
    }
}

/// An in-memory notebook with the editor and the ink tools registered, plus direct handles to the tools under test.
@MainActor
struct InkToolsFixture {
    let services: AppServices
    let host: FeatureHost
    let notebook: Notebook
    let session: NotebookSession
    let settings: InkToolsSettings
    let pasteboard: UIPasteboard
    let clipboard: ClipboardService
    let lasso: LassoTool
    let shapes: ShapesTool

    init(pages: Int = 1, recognizedText: String = "hello world") throws {
        let defaults = try #require(UserDefaults(suiteName: "co.xanom.sheafnote.inktools.\(UUID().uuidString)"))
        services = AppServices(container: try SheafnoteStore.makeContainer(inMemory: true), defaults: defaults,
                               recognizer: StubRecognizer(text: recognizedText))
        host = FeatureHost(services: services)
        EditorFeature.register(into: host)
        InkToolsFeature.register(into: host)
        notebook = try services.library.createNotebook(title: "Ink", kind: .paged, cover: .default, template: TemplateSpec(kind: .blank),
                                                       paperSize: .a4, orientation: .portrait, paperColor: .white, in: nil)
        for _ in 1..<max(pages, 1) { try services.pages.addPage(to: notebook.id, at: .end, template: nil) }
        session = NotebookSession(notebook: notebook, host: host, sizing: .fixed(.zero))
        settings = InkToolsSettings(store: services.settings)
        pasteboard = try #require(UIPasteboard(name: UIPasteboard.Name("co.xanom.sheafnote.test.\(UUID().uuidString)"), create: true))
        clipboard = ClipboardService(host: host, pasteboard: pasteboard)
        lasso = LassoTool(host: host, settings: settings, clipboard: clipboard)
        shapes = ShapesTool(settings: settings)
        lasso.activate(in: session)
        shapes.activate(in: session)
    }

    func page(_ index: Int = 0) throws -> PageSession {
        try #require(session.pageSession(for: session.pageIDs[index]))
    }

    func action(_ id: String) throws -> any SelectionAction {
        try #require(InkSelectionActions.make(host: host, clipboard: clipboard).first { $0.id == id }, "no action \(id)")
    }

    func select(_ strokeIndices: [Int], on page: PageSession) {
        let ids = page.strokeIDs
        let chosen = strokeIndices.map { page.drawing.strokes[$0] }
        session.selection.select(pageID: page.pageID, strokeIDs: Set(strokeIndices.map { ids[$0] }), elementIDs: [],
                                 bounds: PKDrawing(strokes: chosen).bounds)
    }

    @discardableResult
    func addShape(_ figure: ShapeFigure, to page: PageSession, fill: String? = nil, width: Double = 3) throws -> ElementValue {
        let element = ShapeElementGeometry.element(for: figure, pageID: page.pageID, zIndex: 1, strokeHex: "#112233", fillHex: fill, lineWidth: width)
        return try page.elements.add(element, undoName: "Add Shape")
    }

    /// The shape payload of the element with `id` (default: the first element) on `page`.
    func shapePayload(_ id: UUID? = nil, on page: PageSession) throws -> ShapePayload {
        let element = try #require(page.elements.all.first { id == nil || $0.id == id })
        return try #require(PayloadCodec.decode(ShapePayload.self, from: element.payload))
    }

    static func settle() async { await EditorFixture.settle() }
}

enum InkSketch {
    static func stroke(points: [CGPoint], type: PKInk.InkType = .pen, color: UIColor = .black, width: CGFloat = 3,
                       date: Date = Date(timeIntervalSinceReferenceDate: 2_000)) -> PKStroke {
        let controls = points.enumerated().map { index, p in
            PKStrokePoint(location: p, timeOffset: Double(index) * 0.01, size: CGSize(width: width, height: width),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(type, color: color), path: PKStrokePath(controlPoints: controls, creationDate: date))
    }

    static func line(_ a: CGPoint, _ b: CGPoint, type: PKInk.InkType = .pen, width: CGFloat = 3) -> PKStroke {
        stroke(points: samples([a, b], step: 4), type: type, width: width)
    }

    /// Points along a polyline, `step` apart.
    static func samples(_ corners: [CGPoint], step: CGFloat) -> [CGPoint] {
        var out = [corners[0]]
        for (a, b) in zip(corners, corners.dropFirst()) {
            let n = max(1, Int((hypot(b.x - a.x, b.y - a.y) / step).rounded(.up)))
            for i in 1...n { out.append(CGPoint(x: a.x + (b.x - a.x) * CGFloat(i) / CGFloat(n), y: a.y + (b.y - a.y) * CGFloat(i) / CGFloat(n))) }
        }
        return out
    }

    /// A closed loop around a rectangle, as a finger or Pencil would drag it.
    static func loop(around rect: CGRect) -> [CGPoint] {
        samples([CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY),
                 CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY)], step: 5)
    }

    static func circle(center: CGPoint, radius: CGFloat, wobble: CGFloat = 0, count: Int = 90) -> [CGPoint] {
        (0...count).map { i in
            let a = 2 * Double.pi * Double(i) / Double(count)
            let r = radius + wobble * CGFloat(sin(Double(i) * 1.7))
            return CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
        }
    }

    /// A wandering path that is no shape.
    static func randomWalk(count: Int = 80) -> [CGPoint] {
        var x: UInt64 = 88172645463325252
        func next() -> CGFloat {
            x ^= x << 13; x ^= x >> 7; x ^= x << 17
            return CGFloat(x % 2000) / 1000 - 1
        }
        var p = CGPoint(x: 200, y: 200)
        return (0..<count).map { _ in
            p = CGPoint(x: p.x + next() * 14, y: p.y + next() * 14)
            return p
        }
    }

    static func sample(_ p: CGPoint, at time: TimeInterval) -> InkSample {
        InkSample(location: p, timestamp: time, force: 1, altitude: .pi / 2, azimuth: 0, isPencil: true)
    }

    /// Alpha channel of one pixel of an image, at image coordinates.
    static func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data), x >= 0, y >= 0, x < image.width, y < image.height else { return 0 }
        return bytes[y * image.bytesPerRow + x * (image.bitsPerPixel / 8) + 3]
    }
}
