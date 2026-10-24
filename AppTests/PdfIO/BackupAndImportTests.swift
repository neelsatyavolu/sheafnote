import PDFKit
import SwiftUI
import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite("Backup and import actions")
struct BackupAndImportTests {
    private func context(_ fx: PdfIOFixture, opened: @escaping (Notebook) -> Void = { _ in }) -> LibraryActionContext {
        LibraryActionContext(services: fx.services, currentFolderID: nil, present: { _ in }, open: opened, showError: { _ in })
    }

    private func write(_ data: Data, named name: String, in folder: URL) throws -> URL {
        let url = folder.appending(path: name)
        try data.write(to: url)
        return url
    }

    // MARK: Import handlers

    @Test func importingOnePdfCreatesAndOpensANotebookNamedAfterTheFile() async throws {
        let fx = try PdfIOFixture()
        let folder = try PdfIOFixture.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try write(PdfIOFixture.pdf(pages: 3), named: "Quarterly Report.pdf", in: folder)
        var opened: Notebook?
        try await ImportActions.importPDFs([url], context(fx) { opened = $0 })
        let notebook = try #require(opened)
        #expect(notebook.title == "Quarterly Report")
        #expect(try fx.services.pages.orderedPages(of: notebook.id).count == 3)
    }

    @Test func importingSeveralPdfsCreatesOneNotebookEachWithoutOpeningAny() async throws {
        let fx = try PdfIOFixture()
        let folder = try PdfIOFixture.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = [try write(PdfIOFixture.pdf(pages: 1), named: "a.pdf", in: folder), try write(PdfIOFixture.pdf(pages: 2), named: "b.pdf", in: folder)]
        var opened = 0
        try await ImportActions.importPDFs(urls, context(fx) { _ in opened += 1 })
        #expect(try fx.services.library.allNotebooks().count == 2 && opened == 0)
    }

    @Test func aDamagedPdfThrowsAndAddsNothing() async throws {
        let fx = try PdfIOFixture()
        let folder = try PdfIOFixture.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try write(Data("%PDF-1.4 broken".utf8), named: "bad.pdf", in: folder)
        await #expect(throws: PdfIOError.unreadablePDF) { try await ImportActions.importPDFs([url], context(fx)) }
        #expect(try fx.services.library.allNotebooks().isEmpty)
    }

    @Test func aMissingFileGivesAFriendlyError() async throws {
        let fx = try PdfIOFixture()
        let error = await #expect(throws: PdfIOAppError.self) {
            try await ImportActions.importPDFs([URL(filePath: "/nonexistent/none.pdf")], context(fx))
        }
        #expect(error?.errorDescription?.contains("none.pdf") == true)
    }

    @Test func importingImagesMakesOneNotebookWithAPagePerImage() async throws {
        let fx = try PdfIOFixture()
        let folder = try PdfIOFixture.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 70)).pngData { $0.fill(CGRect(x: 0, y: 0, width: 50, height: 70)) }
        let urls = [try write(png, named: "one.png", in: folder), try write(png, named: "two.png", in: folder)]
        try await ImportActions.importImages(urls, context(fx))
        let notebook = try #require(try fx.services.library.allNotebooks().first)
        #expect(try fx.services.pages.orderedPages(of: notebook.id).count == 2)
    }

    @Test func importingAnArchiveRestoresAsCopiesAndPresentsASummary() async throws {
        let source = try PdfIOFixture()
        _ = try await source.importer.importPDF(PdfIOFixture.pdf(pages: 2), title: "Restorable", into: nil)
        let folder = try PdfIOFixture.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "lib.sheafnote")
        try await ArchiveExporter(context: source.services.context).export(.library, to: file)

        let target = try PdfIOFixture()
        var presented = 0
        let ctx = LibraryActionContext(services: target.services, currentFolderID: nil, present: { _ in presented += 1 }, open: { _ in }, showError: { _ in })
        try await ImportActions.importArchives([file], ctx)
        #expect(presented == 1)
        let folders = try target.services.library.allFolders()
        #expect(folders.count == 1 && folders[0].name.hasPrefix("Sheafnote Backup"), "a library backup lands in its own folder")
        #expect(try target.services.library.allNotebooks().map(\.title) == ["Restorable"])
    }

    @Test func aGarbageArchiveIsRejectedWithAUserFacingError() async throws {
        let fx = try PdfIOFixture()
        let folder = try PdfIOFixture.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try write(Data("not a zip".utf8), named: "x.sheafnote", in: folder)
        await #expect(throws: ArchiveError.notAnArchive) { try await ImportActions.importArchives([file], context(fx)) }
        #expect(try fx.services.library.allNotebooks().isEmpty)
    }

    // MARK: Automatic backup

    @Test func backupWritesToTheChosenFolderAndKeepsOnlyTheNewestOfItsOwnFiles() async throws {
        let fx = try PdfIOFixture()
        _ = try await fx.importer.importPDF(PdfIOFixture.pdf(pages: 1), title: "Doc", into: nil)
        let folder = try PdfIOFixture.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let foreign = [try write(Data("keep me".utf8), named: "notes.txt", in: folder),
                       try write(Data("mine".utf8), named: "Thesis.sheafnote", in: folder)]
        let controller = AutoBackupController(services: fx.services)
        try controller.chooseFolder(folder)
        controller.setEnabled(true)
        controller.setKeepCount(2)
        let start = Date()
        for minute in 0..<4 { await controller.backUpNow(now: start.addingTimeInterval(Double(minute) * 120)) }

        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        let backups = names.filter(BackupPolicy.isBackupFileName)
        #expect(backups.count == 2, "only the 2 newest backups remain: \(names)")
        #expect(foreign.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "files we didn't make are never touched")
        #expect(controller.settings.lastError == nil && controller.settings.lastBackupName == backups.sorted().last)
        let archive = try ZipReader(url: folder.appending(path: try #require(controller.settings.lastBackupName)))
        #expect(archive.contains(ArchiveLayout.manifest))
    }

    @Test func backupRunsOnlyOncePerDayAndOnlyAfterChanges() async throws {
        let fx = try PdfIOFixture()
        let result = try await fx.importer.importPDF(PdfIOFixture.pdf(pages: 1), title: "Doc", into: nil)
        let folder = try PdfIOFixture.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let controller = AutoBackupController(services: fx.services)
        try controller.chooseFolder(folder)
        controller.setEnabled(true)
        func count() throws -> Int { try FileManager.default.contentsOfDirectory(atPath: folder.path).count }

        let t0 = Date()
        await controller.runIfDue(now: t0)
        #expect(try count() == 1)
        await controller.runIfDue(now: t0.addingTimeInterval(3600))
        #expect(try count() == 1, "same day")
        await controller.runIfDue(now: t0.addingTimeInterval(2 * 86_400))
        #expect(try count() == 1, "a later day, but nothing changed since the last backup")
        try fx.services.library.rename(.notebook(result.notebookID), to: "Renamed")
        await controller.runIfDue(now: Date().addingTimeInterval(3 * 86_400))
        #expect(try count() == 2, "changed and due")
    }

    @Test func backupWithoutAFolderReportsAFriendlyError() async throws {
        let fx = try PdfIOFixture()
        let controller = AutoBackupController(services: fx.services)
        await controller.backUpNow()
        #expect(controller.settings.lastError == PdfIOAppError.noBackupFolder.errorDescription)
        #expect(!controller.settings.isEnabled)
        controller.setEnabled(true)
        #expect(!controller.settings.isEnabled, "can't be switched on without a folder")
    }

    @Test func aVanishedFolderIsReportedNotSwallowed() async throws {
        let fx = try PdfIOFixture()
        _ = try await fx.importer.importPDF(PdfIOFixture.pdf(pages: 1), title: "Doc", into: nil)
        let folder = try PdfIOFixture.temporaryFolder()
        let controller = AutoBackupController(services: fx.services)
        try controller.chooseFolder(folder)
        try FileManager.default.removeItem(at: folder)
        await controller.backUpNow()
        #expect(controller.settings.lastError != nil && controller.settings.lastBackupAt == nil)
    }

    @Test func settingsSurviveARestart() async throws {
        let fx = try PdfIOFixture()
        let folder = try PdfIOFixture.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = AutoBackupController(services: fx.services)
        try first.chooseFolder(folder)
        first.setEnabled(true)
        first.setKeepCount(5)
        let second = AutoBackupController(services: fx.services)
        #expect(second.settings.isEnabled && second.settings.keepCount == 5 && second.hasFolder && second.folderName == folder.lastPathComponent)
    }

    // MARK: Performance

    @Test func fiveHundredPagePdfImportsAndOpensWithinTheBudget() async throws {
        let fx = try PdfIOFixture()
        let data = PdfIOFixture.pdf(pages: 500)
        let started = Date()
        let result = try await fx.importer.importPDF(data, title: "Big", into: nil)
        let importTime = Date().timeIntervalSince(started)
        #expect(result.pageIDs.count == 500)

        let assetID = try #require(fx.services.pages.page(id: result.pageIDs[0])?.backgroundAssetID)
        let opened = Date()
        let cache = BackgroundAssetCache(pages: fx.services.pages)
        let asset = try await cache.asset(assetID)
        let ctx = CGContext(data: nil, width: 612, height: 792, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: 792)
        ctx.scaleBy(x: 1, y: -1)
        asset.draw(pageIndex: 250, in: ctx, rect: CGRect(x: 0, y: 0, width: 612, height: 792))
        let firstPageTime = Date().timeIntervalSince(opened)
        print("PERF import 500 pages: \(importTime) s; open + draw page 251: \(firstPageTime) s")
        #expect(importTime < 5, "import took \(importTime) s")
        #expect(firstPageTime < 2, "first page took \(firstPageTime) s")
    }
}
