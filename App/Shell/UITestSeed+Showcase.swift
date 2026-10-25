import Foundation
import PencilKit
import UIKit
import SheafnoteCore

/// `-UITestScenario showcase -UITestShowcaseInk <path to showcase-ink.json>`: a lived-in library and a Biology
/// notebook with handwritten notes, for screenshots. The ink file holds pen strokes generated from a single-stroke
/// font (see `scripts/showcase/make_ink.py`); without it the notebooks are created with empty pages.
extension UITestSeed {
    private static let now = Date(timeIntervalSince1970: 1_792_400_000)   // late October 2026

    private struct InkFile: Decodable {
        struct Stroke: Decodable {
            let ink: String
            let color: String
            let alpha: Double
            let width: Double
            let points: [[Double]]   // x, y, time offset, force
        }
        struct Card: Decodable {
            struct Side: Decodable { let strokes: [Stroke]; let width: Double; let height: Double }
            let front: Side
            let back: Side
        }
        let pages: [[Stroke]]
        let cards: [Card]
    }

    static func showcase(_ services: AppServices) throws {
        let ink = UserDefaults.standard.string(forKey: "UITestShowcaseInk")
            .flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
            .flatMap { try? JSONDecoder().decode(InkFile.self, from: $0) }
        let ctx = services.context
        let school = Folder(id: fixedID(1), name: "School", parentID: nil, sortKey: "N", now: now)
        let projects = Folder(id: fixedID(2), name: "Projects", parentID: nil, sortKey: "P", now: now)
        let kitchen = Folder(id: fixedID(3), name: "Recipes & Meals", parentID: nil, sortKey: "R", now: now)
        [school, projects, kitchen].forEach(ctx.insert)

        let shelf: [(String, String, TemplateKind, Folder?)] = [
            ("Budget", "slate", .gridSmall, nil), ("Sketches", "blush", .blank, nil),
            ("Piano Practice", "orbit", .musicStaff, nil), ("Reading List", "confetti", .ruledWide, nil),
            ("Trip to Japan", "saffron", .dotted, nil), ("Journal", "plum", .ruledCollege, nil),
            ("Chemistry Lab Notes", "herringbone", .gridMedium, school), ("Physics 101", "scallop", .ruledCollege, school),
            ("Sprint Plan", "blueprint", .plannerWeekly, projects), ("Weeknight Dinners", "ember", .blank, kitchen),
        ]
        for (i, entry) in shelf.enumerated() {
            try notebook(services, n: 50 + i, title: entry.0, cover: entry.1, template: entry.2, folder: entry.3?.id,
                         created: now.addingTimeInterval(-86_400 * Double(20 - i)))
        }
        let biology = try notebook(services, n: 70, title: "Biology 201", cover: "meadow", template: .ruledCollege,
                                   pages: max(ink?.pages.count ?? 0, 3), created: now)
        let pages = try services.pages.orderedPages(of: biology.id)
        for (page, strokes) in zip(pages, ink?.pages ?? []) {
            let drawing = PKDrawing(strokes: strokes.map(pkStroke))
            try services.pages.saveInk(pageID: page.id, drawingData: drawing.dataRepresentation(),
                                       strokeIDs: drawing.strokeIDs, now: now)
        }
        if let first = pages.first {
            let star = ElementValue(pageID: first.id, kind: .sticker, frame: CGRect(x: 500, y: 520, width: 44, height: 44),
                                    rotation: -0.15, zIndex: 1, payload: PayloadCodec.encode(StickerPayload(stickerID: "star")))
            try services.pages.insertElement(star, now: now)
        }
        let study = StudyStore(context: ctx)
        for card in ink?.cards ?? [] {
            try study.createCard(notebookID: biology.id, deck: "Biology 201", sourcePageID: pages.first?.id,
                                 frontImage: cardImage(card.front), backImage: cardImage(card.back), now: now)
        }
        try ctx.save()
        // Search reads new handwriting after a library change; announce the seeded pages the way an edit would.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NotificationCenter.default.post(name: .sheafnoteModelDidChange, object: nil)
        }
    }

    private static func pkStroke(_ s: InkFile.Stroke) -> PKStroke {
        let type: PKInk.InkType = switch s.ink { case "marker": .marker; case "monoline": .monoline; default: .pen }
        let color = UIColor(hex: s.color).withAlphaComponent(s.alpha)
        let points = s.points.map { p in
            PKStrokePoint(location: CGPoint(x: p[0], y: p[1]), timeOffset: p[2], size: CGSize(width: s.width, height: s.width),
                          opacity: 1, force: p[3], azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(type, color: color), path: PKStrokePath(controlPoints: points, creationDate: now))
    }

    /// The card side's handwriting on white, as the card maker would capture it.
    private static func cardImage(_ side: InkFile.Card.Side) -> Data {
        let rect = CGRect(x: 0, y: 0, width: side.width, height: side.height)
        let ink = PKDrawing(strokes: side.strokes.map(pkStroke)).image(from: rect, scale: 2)
        return UIGraphicsImageRenderer(size: rect.size).pngData { _ in
            UIColor.white.setFill()
            UIRectFill(rect)
            ink.draw(in: rect)
        }
    }
}
