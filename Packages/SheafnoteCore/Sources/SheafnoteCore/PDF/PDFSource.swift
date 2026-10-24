import CoreGraphics
import Foundation
import PDFKit

public enum PdfIOError: LocalizedError, Equatable {
    case unreadablePDF
    case passwordProtected
    case emptyPDF
    case unreadableImage(String)
    case nothingToImport
    case notAPagedNotebook
    case notebookMissing

    public var errorDescription: String? {
        switch self {
        case .unreadablePDF: "Sheafnote couldn't open this PDF. The file may be damaged."
        case .passwordProtected: "This PDF is password protected. Remove the password in another app, then import it again."
        case .emptyPDF: "This PDF has no pages."
        case .unreadableImage(let name): "Sheafnote couldn't read the image \u{201C}\(name)\u{201D}."
        case .nothingToImport: "There was nothing to import."
        case .notAPagedNotebook: "Pages can only be inserted into a regular notebook."
        case .notebookMissing: "That notebook is no longer available."
        }
    }
}

public struct PDFOutlineItem: Equatable, Sendable {
    public var title: String
    /// Zero-based PDF page the entry points to; nil when the destination can't be resolved.
    public var pageIndex: Int?
    public var depth: Int
    /// Index in the flattened list of the parent entry, nil at the top level.
    public var parent: Int?
}

/// A PDF opened for import and for drawing page backgrounds. PDFKit objects are not thread safe, so every use goes
/// through one lock; that is what lets `CATiledLayer` draw tiles of the same page from several threads.
public final class PDFSource: @unchecked Sendable {
    public static let fallbackPageSize = PaperSize.a4.portraitSize

    private let document: PDFDocument
    private let lock = NSLock()
    public let pageCount: Int

    public init(data: Data) throws {
        guard let document = PDFDocument(data: data) else { throw PdfIOError.unreadablePDF }
        if document.isLocked, !document.unlock(withPassword: "") { throw PdfIOError.passwordProtected }
        guard document.pageCount > 0 else { throw PdfIOError.emptyPDF }
        self.document = document
        self.pageCount = document.pageCount
    }

    // MARK: Sizes

    /// The page as shown: crop box, with the page's own rotation applied, in points.
    public func size(ofPage index: Int) -> CGSize {
        lock.withLock {
            guard let page = document.page(at: index)?.pageRef else { return Self.fallbackPageSize }
            return Self.displaySize(of: page)
        }
    }

    public func sizes() -> [CGSize] { (0..<pageCount).map(size(ofPage:)) }

    static func displaySize(of page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox).standardized
        let rotated = abs(page.rotationAngle) % 180 == 90
        let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
        return size.width >= 1 && size.height >= 1 ? size : fallbackPageSize
    }

    // MARK: Drawing

    /// Draws page `index` scaled to fill `rect`. The context's user space is top-left origin with y pointing down
    /// (the convention of every Sheafnote page layer); the PDF is flipped into it here.
    public func draw(pageIndex index: Int, in ctx: CGContext, rect: CGRect) {
        lock.withLock {
            guard let page = document.page(at: index)?.pageRef, rect.width > 0, rect.height > 0 else { return }
            ctx.saveGState()
            defer { ctx.restoreGState() }
            ctx.clip(to: rect)
            ctx.translateBy(x: rect.minX, y: rect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            let target = CGRect(origin: .zero, size: rect.size)
            ctx.concatenate(page.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: false))
            ctx.clip(to: page.getBoxRect(.cropBox))
            ctx.drawPDFPage(page)
        }
    }

    // MARK: Outline

    /// The PDF's own table of contents, flattened in reading order.
    public func outline() -> [PDFOutlineItem] {
        lock.withLock {
            guard let root = document.outlineRoot else { return [] }
            var items: [PDFOutlineItem] = []
            walk(root, depth: 0, parent: nil, into: &items)
            return items
        }
    }

    private func walk(_ node: PDFOutline, depth: Int, parent: Int?, into items: inout [PDFOutlineItem]) {
        for i in 0..<node.numberOfChildren {
            guard let child = node.child(at: i) else { continue }
            let title = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let me = items.count
            if title.isEmpty {
                walk(child, depth: depth, parent: parent, into: &items)   // untitled folders add no level
                continue
            }
            items.append(PDFOutlineItem(title: title, pageIndex: pageIndex(of: child), depth: depth, parent: parent))
            walk(child, depth: depth + 1, parent: me, into: &items)
        }
    }

    private func pageIndex(of item: PDFOutline) -> Int? {
        let destination = item.destination ?? (item.action as? PDFActionGoTo)?.destination
        guard let page = destination?.page else { return nil }
        let index = document.index(for: page)
        return index == NSNotFound ? nil : index
    }
}

/// What kind of file a page background is, decided from its first bytes (not its name).
public enum BackgroundKind: Equatable, Sendable {
    case pdf, image

    public static func sniff(_ data: Data) -> BackgroundKind {
        data.prefix(1024).range(of: Data("%PDF-".utf8)) != nil ? .pdf : .image
    }
}
