import SwiftUI
import PencilKit
import SheafnoteCore

/// Playback mode. While it is the active tool, the page is read-only: tap a stroke to jump to the moment it was
/// written, and strokes written after the playhead are dimmed. The options row is the player bar.
@MainActor
final class PlaybackTool: EditorTool {
    static let toolID: ToolID = "audioPlayback"

    let id = PlaybackTool.toolID
    let title = LocalizedStringResource("Audio playback", table: "AudioStudy")
    let symbolName = "waveform.circle"
    let placement = ToolPlacement.more(order: 90)
    let supportedKinds: Set<NotebookKind> = [.paged, .whiteboard]
    let inputPolicy = ToolInputPolicy.overlayCapturesAll

    func makeOptionsView(in editor: EditorContext) -> AnyView {
        let session = AudioStudyHub.shared.session(for: editor)
        return AnyView(PlaybackOptionsRow(session: session))
    }

    func makeOverlay(for page: PageContext, in editor: EditorContext) -> AnyView? {
        let session = AudioStudyHub.shared.session(for: editor)
        let paper = PaperPalette.palette(for: Self.paperColor(of: page, editor: editor)).paper
        return AnyView(PlaybackOverlay(page: page, session: session, paper: UIColor(cgColor: paper.cgColor)))
    }

    private static func paperColor(of page: PageContext, editor: EditorContext) -> PaperColor {
        let override = editor.services.pages.page(id: page.pageID)?.paperColorOverride.flatMap(PaperColor.init(rawValue:))
        return override ?? PaperColor(rawValue: editor.notebook.paperColor) ?? .white
    }
}

private struct PlaybackOptionsRow: View {
    let session: AudioStudySession

    var body: some View {
        if session.player.isLoaded {
            PlayerBar(session: session)
        } else {
            HStack {
                Image(systemName: "waveform")
                Text("Open a recording from the Audio menu to play it back here.", tableName: "AudioStudy").font(.subheadline)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(12)
        }
    }
}

extension PKStroke {
    /// The stroke as a polyline in page coordinates.
    func sampledPoints(step: CGFloat = 6) -> [CGPoint] {
        path.interpolatedPoints(by: .distance(step)).map { $0.location.applying(transform) }
    }
}

struct PlaybackOverlay: View {
    let page: any PageContext
    let session: AudioStudySession
    let paper: UIColor

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { tap in seek(at: tap.location) })
            PlaybackDimVeil(page: page, session: session, paper: paper).allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Audio playback overlay", tableName: "AudioStudy"))
        .accessibilityHint(Text("Tap writing to jump to when it was written.", tableName: "AudioStudy"))
        .accessibilityIdentifier("audio.overlay")
    }

    private func seek(at point: CGPoint) {
        let strokes = page.ink.strokes
        let tolerance = max(10, 18 / max(page.zoomScale, 0.25))
        let candidates = strokes.map { (id: $0.id, points: $0.stroke.sampledPoints()) }
        guard let hit = StrokeSeekHitTest.nearest(to: point, among: candidates, tolerance: tolerance),
              let stroke = strokes.first(where: { $0.id == hit }) else { return }
        let timed = TimedStroke(id: hit, creationDate: stroke.stroke.path.creationDate)
        if !session.player.seek(toStroke: timed) {
            session.editor?.showToast(LocalizedStringResource("That was written outside this recording.", table: "AudioStudy"))
        }
    }
}

/// Paper-colored copy of the strokes written after the playhead, drawn over the page so they look faded.
struct PlaybackDimVeil: View {
    let page: any PageContext
    let session: AudioStudySession
    let paper: UIColor
    @State private var veil: (image: UIImage, rect: CGRect)?

    var body: some View {
        let dimmed = session.player.dimmedStrokeIDs(among: AudioStudySession.timed(page.ink.strokes))
        ZStack {
            if let veil, !dimmed.isEmpty {
                Image(uiImage: veil.image)
                    .resizable()
                    .frame(width: veil.rect.width, height: veil.rect.height)
                    .position(x: veil.rect.midX, y: veil.rect.midY)
            }
        }
        .task(id: dimmed) { veil = Self.render(dimmed, page: page, paper: paper) }
    }

    static func render(_ ids: Set<StrokeID>, page: any PageContext, paper: UIColor) -> (UIImage, CGRect)? {
        let late = page.ink.strokes.filter { ids.contains($0.id) }.map(\.stroke)
        guard !late.isEmpty else { return nil }
        let drawing = PKDrawing(strokes: late)
        let rect = drawing.bounds.insetBy(dx: -4, dy: -4)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let scale = min(3, max(2, page.zoomScale * 2))
        let mask = drawing.image(from: rect, scale: scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { ctx in
            mask.draw(in: CGRect(origin: .zero, size: rect.size))
            ctx.cgContext.setBlendMode(.sourceAtop)
            ctx.cgContext.setFillColor(paper.withAlphaComponent(0.8).cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: rect.size))
        }
        return (image, rect)
    }
}
