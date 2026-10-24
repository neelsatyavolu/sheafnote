import Foundation
import SwiftData
@testable import SheafnoteCore

@MainActor
struct StoreFixture {
    let container: ModelContainer
    let context: ModelContext
    let library: LibraryStore
    let revisions: RevisionStore
    let pages: PageStore

    init() throws {
        container = try SheafnoteStore.makeContainer(inMemory: true)
        context = container.mainContext
        library = LibraryStore(context: context)
        revisions = RevisionStore(context: context)
        pages = PageStore(context: context, revisions: revisions)
    }

    @discardableResult
    func notebook(_ title: String = "Notes", kind: NotebookKind = .paged, in folder: UUID? = nil, now: Date = .now) throws -> Notebook {
        try library.createNotebook(title: title, kind: kind, cover: .default, template: .blank, paperSize: .a4,
                                   orientation: .portrait, paperColor: .white, in: folder, now: now)
    }
}

let day: TimeInterval = 86_400
