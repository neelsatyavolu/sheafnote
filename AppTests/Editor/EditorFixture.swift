import PencilKit
import SwiftUI
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

/// An in-memory notebook with an editor session, for editor tests.
@MainActor
struct EditorFixture {
    let services: AppServices
    let host: FeatureHost
    let notebook: Notebook
    let session: NotebookSession

    init(pages: Int = 1, template: TemplateKind = .blank, sizing: PageSizing = .fixed(.zero)) throws {
        services = try AppServices.inMemory()
        host = FeatureHost(services: services)
        EditorFeature.register(into: host)
        notebook = try services.library.createNotebook(title: "Test", kind: .paged, cover: .default,
                                                       template: TemplateSpec(kind: template), paperSize: .a4,
                                                       orientation: .portrait, paperColor: .white, in: nil)
        for _ in 1..<max(pages, 1) { try services.pages.addPage(to: notebook.id, at: .end, template: nil) }
        session = NotebookSession(notebook: notebook, host: host, sizing: sizing)
    }

    var firstPageID: UUID { session.pageIDs[0] }

    func page(_ index: Int = 0) throws -> PageSession {
        try #require(session.pageSession(for: session.pageIDs[index]))
    }

    /// Settles the run loop so queued observation callbacks and `Task { @MainActor }` hops run.
    static func settle() async {
        for _ in 0..<3 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(30))
    }
}

enum TestInk {
    static func stroke(from a: CGPoint, to b: CGPoint, type: PKInk.InkType = .pen, color: UIColor = .black,
                       width: CGFloat = 3, date: Date = Date(timeIntervalSinceReferenceDate: 1_000)) -> PKStroke {
        let steps = 12
        let points = (0...steps).map { i -> PKStrokePoint in
            let t = CGFloat(i) / CGFloat(steps)
            return PKStrokePoint(location: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                                 timeOffset: Double(i) * 0.01, size: CGSize(width: width, height: width),
                                 opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: date)
        return PKStroke(ink: PKInk(type, color: color), path: path)
    }
}
