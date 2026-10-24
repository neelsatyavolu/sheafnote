import CoreGraphics
import Foundation
import SheafnoteCore

enum ExportKind: String, CaseIterable, Identifiable {
    case pdf, png, jpeg, archive
    var id: String { rawValue }

    var format: ExportFormat? {
        switch self {
        case .pdf: .pdf
        case .png: .png
        case .jpeg: .jpeg
        case .archive: nil
        }
    }
}

struct ExportRequest {
    var notebooks: [Notebook]
    var scope: ExportScope
    var kind: ExportKind
    var includeBackground: Bool
    /// Pixels per point for image exports.
    var imageScale: CGFloat
}

/// What an export produced: files in a private temporary folder, ready to share.
struct ExportOutput {
    var directory: URL
    var files: [URL]
    var pageCount: Int
}

/// Renders notebooks through the shared `PageRenderer` into PDF, image or archive files.
@MainActor
struct ExportRunner {
    let services: AppServices

    func run(_ request: ExportRequest, progress: @escaping @MainActor (Double) -> Void) async throws -> ExportOutput {
        let directory = FileManager.default.temporaryDirectory.appending(path: "\(ExportFolder.prefix)\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let output: ExportOutput
            switch request.kind {
            case .archive: output = try await writeArchive(request, in: directory, progress: progress)
            case .pdf: output = try await writePDFs(request, in: directory, progress: progress)
            case .png, .jpeg: output = try await writeImages(request, in: directory, progress: progress)
            }
            return output
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    // MARK: Archive

    private func writeArchive(_ request: ExportRequest, in directory: URL, progress: @escaping @MainActor (Double) -> Void) async throws -> ExportOutput {
        let name = request.notebooks.count == 1 ? ExportPlanner.sanitized(request.notebooks[0].title) : String(localized: "Sheafnote Notebooks", table: "PdfIO")
        let url = directory.appending(path: "\(name).\(BackupPolicy.fileExtension)")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
        try await ArchiveExporter(context: services.context, appVersion: version)
            .export(.notebooks(request.notebooks.map(\.id)), to: url, progress: progress)
        let pages = try request.notebooks.reduce(0) { $0 + (try services.pages.orderedPages(of: $1.id)).count }
        return ExportOutput(directory: directory, files: [url], pageCount: pages)
    }

    // MARK: PDF

    private func writePDFs(_ request: ExportRequest, in directory: URL, progress: @escaping @MainActor (Double) -> Void) async throws -> ExportOutput {
        var files: [URL] = []
        var total = 0
        let jobs = try request.notebooks.map { try job(for: $0, request) }
        let allPages = jobs.reduce(0) { $0 + $1.pages.count }
        var done = 0
        var usedNames = Set<String>()
        for job in jobs {
            let url = directory.appending(path: uniqueName(ExportPlanner.fileName(title: job.notebook.title, format: .pdf), &usedNames))
            let options = renderOptions(request)
            try await PDFExportWriter.write(sizes: job.pages.map(\.size), to: url, title: job.notebook.title) { index, ctx, box in
                try await services.pageRenderer.renderPDFPage(pageID: job.pages[index].id, into: ctx, mediaBox: box, options: options)
                done += 1
                progress(Double(done) / Double(allPages))
            }
            files.append(url)
            total += job.pages.count
        }
        return ExportOutput(directory: directory, files: files, pageCount: total)
    }

    // MARK: Images

    private func writeImages(_ request: ExportRequest, in directory: URL, progress: @escaping @MainActor (Double) -> Void) async throws -> ExportOutput {
        guard let format = request.kind.format, let notebook = request.notebooks.first else { throw ExportError.noPages }
        let job = try job(for: notebook, request)
        let names = ExportPlanner.imageFileNames(title: notebook.title, pages: job.pages, notebookPageCount: job.notebookPageCount, format: format)
        var files: [URL] = []
        for (index, page) in job.pages.enumerated() {
            try Task.checkCancellation()
            let scale = ExportPlanner.imageScale(requested: request.imageScale, pageSize: page.size)
            let image = try await services.pageRenderer.renderImage(pageID: page.id, rect: nil, scale: scale, options: renderOptions(request))
            let url = directory.appending(path: names[index])
            try ImageEncoder.encode(image, as: format).write(to: url, options: .atomic)
            files.append(url)
            progress(Double(index + 1) / Double(job.pages.count))
        }
        return ExportOutput(directory: directory, files: files, pageCount: files.count)
    }

    // MARK: Helpers

    private struct Job {
        var notebook: Notebook
        var pages: [ExportPageRef]
        var notebookPageCount: Int
    }

    private func job(for notebook: Notebook, _ request: ExportRequest) throws -> Job {
        let stored = try services.pages.orderedPages(of: notebook.id)
        guard !stored.isEmpty, notebook.kind != .text else {
            throw PdfIOAppError.textDocumentsNeedBackupFormat(title: notebook.title)
        }
        let refs = stored.enumerated().map { ExportPageRef(id: $1.id, number: $0 + 1, size: $1.size) }
        let scope = request.notebooks.count == 1 ? request.scope : .wholeNotebook
        let chosen = ExportPlanner.select(scope, from: refs)
        guard !chosen.isEmpty else { throw PdfIOAppError.nothingSelected }
        return Job(notebook: notebook, pages: chosen, notebookPageCount: refs.count)
    }

    private func renderOptions(_ request: ExportRequest) -> RenderOptions {
        RenderOptions(includeBackground: request.includeBackground, includeInk: true, includeElements: true,
                      forExport: true, hideTape: false)
    }

    private func uniqueName(_ name: String, _ used: inout Set<String>) -> String {
        var candidate = name
        var n = 2
        let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
        while !used.insert(candidate).inserted {
            candidate = "\(stem) \(n).\(ext)"
            n += 1
        }
        return candidate
    }
}

enum ExportFolder {
    static let prefix = "sheafnote-export-"

    /// Removes export folders left behind by earlier runs (a crash, or a share sheet that outlived its screen).
    static func removeStale(in directory: URL = FileManager.default.temporaryDirectory, olderThan age: TimeInterval = 3600, now: Date = .now) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in items where url.lastPathComponent.hasPrefix(prefix) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if now.timeIntervalSince(modified) > age { try? fm.removeItem(at: url) }
        }
    }
}
