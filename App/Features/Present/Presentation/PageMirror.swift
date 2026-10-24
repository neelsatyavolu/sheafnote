import Observation
import SwiftUI
import SheafnoteCore

/// A live picture of the page being presented. It follows the editor's current page and redraws when the ink or
/// elements change (a few times a second), so the audience sees the writing as it lands.
@MainActor @Observable
final class PageMirror {
    private(set) var image: CGImage?
    private(set) var pageID: UUID?
    private(set) var pageSize: CGSize = .zero
    private(set) var errorMessage: String?
    /// Pixel width to render at; the external view reports what its screen needs.
    var targetPixelWidth: CGFloat = 1600

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastSignature: Int?
    @ObservationIgnored private var lastWidth: CGFloat = 0
    @ObservationIgnored private weak var editor: (any EditorContext)?
    @ObservationIgnored private var onEditorGone: (@MainActor () -> Void)?

    var isRunning: Bool { task != nil }

    func start(editor: EditorContext, onEditorGone: @escaping @MainActor () -> Void) {
        stop()
        self.editor = editor
        self.onEditorGone = onEditorGone
        lastSignature = nil
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        image = nil
        pageID = nil
        errorMessage = nil
    }

    private func tick() async {
        guard let editor else { return onEditorGone?() ?? () }
        guard let page = editor.currentPage else { return }
        let signature = Self.signature(of: page)
        guard signature != lastSignature || targetPixelWidth != lastWidth else { return }
        lastSignature = signature
        lastWidth = targetPixelWidth
        await render(page: page, editor: editor)
    }

    private func render(page: any PageContext, editor: EditorContext) async {
        let size = page.pageSize
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(max(targetPixelWidth / size.width, 1), 4)
        do {
            let rendered = try await editor.services.pageRenderer.renderImage(pageID: page.pageID, rect: nil, scale: scale, options: .screen)
            image = rendered
            pageID = page.pageID
            pageSize = size
            errorMessage = nil
        } catch {
            lastSignature = nil
            errorMessage = error.localizedDescription
        }
    }

    /// Changes whenever the page, its ink or its elements change.
    static func signature(of page: any PageContext) -> Int {
        var hasher = Hasher()
        hasher.combine(page.pageID)
        hasher.combine(Int(page.pageSize.width))
        hasher.combine(Int(page.pageSize.height))
        for stroke in page.ink.strokes { hasher.combine(stroke.id) }
        for element in page.elements.all {
            hasher.combine(element.id)
            hasher.combine(element.frame.origin.x)
            hasher.combine(element.frame.origin.y)
            hasher.combine(element.frame.width)
            hasher.combine(element.frame.height)
            hasher.combine(element.rotation)
            hasher.combine(element.payload)
        }
        return hasher.finalize()
    }
}
