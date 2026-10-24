import CoreGraphics
import Foundation
import SheafnoteCore

/// A decoded page background: a PDF (any of its pages) or a whole-page image.
enum BackgroundAsset: Sendable {
    case pdf(PDFSource)
    case image(ImagePageSource)

    /// Draws into a top-left-origin, y-down context, filling `rect`.
    func draw(pageIndex: Int?, in ctx: CGContext, rect: CGRect) {
        switch self {
        case .pdf(let source): source.draw(pageIndex: min(max(pageIndex ?? 0, 0), source.pageCount - 1), in: ctx, rect: rect)
        case .image(let image): image.draw(in: ctx, rect: rect)
        }
    }
}

/// Keeps the few most recently used backgrounds decoded. A 500-page PDF is parsed once and every page tile and
/// thumbnail shares that one document; pages themselves are only rendered when they are on screen.
@MainActor
final class BackgroundAssetCache {
    private let pages: PageStore
    private let capacity: Int
    private var loaded: [(id: UUID, asset: BackgroundAsset)] = []
    private var inFlight: [UUID: Task<BackgroundAsset, Error>] = [:]

    init(pages: PageStore, capacity: Int = 3) {
        self.pages = pages
        self.capacity = capacity
    }

    func asset(_ id: UUID) async throws -> BackgroundAsset {
        if let index = loaded.firstIndex(where: { $0.id == id }) {
            let hit = loaded.remove(at: index)
            loaded.append(hit)
            return hit.asset
        }
        if let task = inFlight[id] { return try await task.value }
        let data = try await pages.data(for: id)
        let task = Task.detached(priority: .userInitiated) { try Self.decode(data) }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        let asset = try await task.value
        loaded.append((id, asset))
        if loaded.count > capacity { loaded.removeFirst(loaded.count - capacity) }
        return asset
    }

    private nonisolated static func decode(_ data: Data) throws -> BackgroundAsset {
        switch BackgroundKind.sniff(data) {
        case .pdf: .pdf(try PDFSource(data: data))
        case .image: .image(try ImagePageSource(data: data))
        }
    }
}
