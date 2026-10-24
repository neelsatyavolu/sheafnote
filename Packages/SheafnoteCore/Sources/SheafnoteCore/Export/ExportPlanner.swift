import CoreGraphics
import Foundation

public enum ExportFormat: Equatable, Sendable {
    case pdf
    case png
    case jpeg

    public var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .png: "png"
        case .jpeg: "jpg"
        }
    }

    public var isImage: Bool { self != .pdf }
}

/// A page as the exporter needs to know it: identity, position in the notebook (1-based) and size in points.
public struct ExportPageRef: Equatable, Sendable {
    public var id: UUID
    public var number: Int
    public var size: CGSize

    public init(id: UUID, number: Int, size: CGSize) {
        self.id = id
        self.number = number
        self.size = size
    }
}

/// Which pages of a notebook to export.
public enum ExportScope: Equatable, Sendable {
    case wholeNotebook
    /// These pages, always output in notebook order whatever order they were selected in.
    case pages(Set<UUID>)
    /// Page numbers typed by the user, e.g. "1-3, 5".
    case numbers([Int])
}

public enum PageRangeParser {
    /// "1-3, 5, 8-9" -> [1, 2, 3, 5, 8, 9], ascending and without duplicates. Nil when the text is empty, malformed
    /// or names a page outside 1...pageCount, so the UI can say so instead of exporting something unexpected.
    public static func parse(_ text: String, pageCount: Int) -> [Int]? {
        var numbers = Set<Int>()
        let parts = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "," || $0 == ";" }).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.contains(where: \.isEmpty) else { return nil }
        for part in parts {
            let ends = part.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard ends.count <= 2, let low = Int(ends[0]), let high = ends.count == 2 ? Int(ends[1]) : low,
                  low >= 1, high >= low, high <= pageCount else { return nil }
            numbers.formUnion(low...high)
        }
        return numbers.sorted()
    }
}

/// Decides which pages go out and what the files are called. Pure; the app does the rendering.
public enum ExportPlanner {
    /// Longest side, in pixels, of an exported image (keeps memory sane for huge pages at high scale).
    public static let maxImagePixels: CGFloat = 8192

    public static func select(_ scope: ExportScope, from pages: [ExportPageRef]) -> [ExportPageRef] {
        switch scope {
        case .wholeNotebook:
            return pages
        case .pages(let ids):
            return pages.filter { ids.contains($0.id) }
        case .numbers(let numbers):
            let wanted = Set(numbers)
            return pages.filter { wanted.contains($0.number) }
        }
    }

    /// File name for a single-file export (PDF).
    public static func fileName(title: String, format: ExportFormat) -> String {
        "\(sanitized(title)).\(format.fileExtension)"
    }

    /// `Biology-p01.png`, `Biology-p02.png`... numbered by position in the notebook, zero padded to the notebook's width.
    public static func imageFileNames(title: String, pages: [ExportPageRef], notebookPageCount: Int, format: ExportFormat) -> [String] {
        let digits = max(2, String(notebookPageCount).count)
        let base = sanitized(title)
        return pages.map { "\(base)-p\(String(format: "%0\(digits)d", $0.number)).\(format.fileExtension)" }
    }

    /// Pixels per point for an image export: the requested scale, reduced if the page would exceed `maxImagePixels`.
    public static func imageScale(requested: CGFloat, pageSize: CGSize) -> CGFloat {
        let longest = max(pageSize.width, pageSize.height)
        guard longest > 0 else { return 1 }
        return max(0.1, min(requested, maxImagePixels / longest))
    }

    /// A title made safe as a file name: no path separators or control characters, no leading dots, bounded length.
    public static func sanitized(_ title: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = title.unicodeScalars.map { banned.contains($0) ? "-" : Character($0) }
        var name = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        name = String(name.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Notebook" : name
    }
}
