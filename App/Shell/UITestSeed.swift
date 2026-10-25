import Foundation
import PDFKit
import SwiftData
import UIKit
import SheafnoteCore

/// Launch-argument driven test mode: `-UITestMode 1 -UITestScenario <name>`.
/// In-memory store, sync off, animations off, deterministic ids. Scenarios:
/// empty, libraryBasic, notebookWith3Pages, pdfNotebook, recorded, showcase (screenshots; see UITestSeed+Showcase).
@MainActor
enum UITestSeed {
    static var isActive: Bool { UserDefaults.standard.bool(forKey: "UITestMode") }
    static var scenario: String { UserDefaults.standard.string(forKey: "UITestScenario") ?? "empty" }

    static func fixedID(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static func makeServices() throws -> AppServices {
        UIView.setAnimationsEnabled(false)
        let suiteName = "co.xanom.sheafnote.uitest"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        let services = try AppServices.inMemory(defaults: UserDefaults(suiteName: suiteName))
        services.syncStatus.isSyncEnabled = false
        try seed(scenario, into: services)
        return services
    }

    static func seed(_ name: String, into services: AppServices) throws {
        switch name {
        case "libraryBasic": try libraryBasic(services)
        case "notebookWith3Pages": try threePages(services)
        case "pdfNotebook": try pdfNotebook(services)
        case "recorded": try recorded(services)
        case "showcase": try showcase(services)
        default: break
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @discardableResult
    static func notebook(_ services: AppServices, n: Int, title: String, cover: String, template: TemplateKind,
                         folder: UUID? = nil, pages: Int = 1, size: CGSize? = nil, created: Date? = nil) throws -> Notebook {
        let ctx = services.context
        let nb = Notebook(id: fixedID(n), title: title, kind: .paged, folderID: folder, cover: CoverSpec(coverID: cover),
                          template: TemplateSpec(kind: template), paperSize: .a4, orientation: .portrait, paperColor: .white,
                          sortKey: SortKey.between(nil, nil), now: created ?? t0.addingTimeInterval(Double(n)))
        ctx.insert(nb)
        var previous: String?
        for i in 0..<pages {
            let key = SortKey.between(previous, nil)
            previous = key
            let page = Page(id: fixedID(n * 100 + i), notebookID: nb.id, sortKey: key, size: size ?? nb.pageSize, now: created ?? t0)
            ctx.insert(page)
        }
        try ctx.save()
        return nb
    }

    private static func libraryBasic(_ services: AppServices) throws {
        let folder = Folder(id: fixedID(1), name: "Projects", parentID: nil, sortKey: "V", now: t0)
        services.context.insert(folder)
        try notebook(services, n: 10, title: "Physics 101", cover: "tide", template: .ruledCollege)
        try notebook(services, n: 11, title: "Recipes", cover: "ember", template: .blank)
        try notebook(services, n: 12, title: "Sprint Plan", cover: "blueprint", template: .plannerWeekly, folder: folder.id)
    }

    private static func threePages(_ services: AppServices) throws {
        try notebook(services, n: 20, title: "Three Pages", cover: "moss", template: .gridMedium, pages: 3)
    }

    private static func pdfNotebook(_ services: AppServices) throws {
        let size = CGSize(width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { ctx in
            for i in 1...3 {
                ctx.beginPage()
                ("Fixture page \(i)" as NSString).draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 32)])
            }
        }
        let asset = try services.pages.importAsset(data: data, kind: .pdf, filename: "fixture.pdf", uti: "com.adobe.pdf")
        let nb = try notebook(services, n: 30, title: "Fixture PDF", cover: "graphite", template: .blank, pages: 3, size: size)
        for (i, page) in try services.pages.orderedPages(of: nb.id).enumerated() {
            page.backgroundAssetID = asset.id
            page.backgroundPageIndex = i
        }
        try services.context.save()
    }

    private static func recorded(_ services: AppServices) throws {
        let nb = try notebook(services, n: 40, title: "Lecture", cover: "plum", template: .ruledNarrow)
        let audio = try services.pages.importAsset(data: Data(repeating: 1, count: 64), kind: .audio, filename: "lecture.m4a")
        services.context.insert(AudioRecording(id: fixedID(41), notebookID: nb.id, assetID: audio.id, title: "Lecture audio",
                                               startedAt: t0, duration: 60, now: t0))
        try services.context.save()
    }
}
