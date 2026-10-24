import PencilKit
import SheafnoteCore
import UIKit

/// One point written in the zoom strip, in strip coordinates.
struct StripSample: Sendable, Equatable {
    var location: CGPoint
    var time: TimeInterval
    var azimuth: CGFloat
    var altitude: CGFloat
}

/// The ink the strip writes with: the pen's selected preset.
struct ZoomInkSpec {
    var ink: PKInk
    /// Page points.
    var width: CGFloat
    var color: UIColor

    @MainActor
    static func current(for editor: EditorContext) -> ZoomInkSpec {
        let session = editor as? NotebookSession
        let preset = session?.presetStore.selectedPreset(for: .pen) ?? editor.presets.presets(for: .pen).first
        let kind = (preset?.inkKind).map { $0 == .marker ? InkKind.pen : $0 } ?? .pen
        let hex = preset?.colorHex ?? "#000000"
        let width = session?.presetStore.widths(for: .pen).selected ?? preset?.width ?? 3
        let tool = InkToolFactory.pencilKitTool(kind: kind, colorHex: hex, width: width)
        return ZoomInkSpec(ink: tool.ink, width: tool.width, color: tool.color)
    }
}

/// Turns what was written in the strip into a `PKStroke` in page coordinates.
enum ZoomStrokeBuilder {
    static func build(samples: [StripSample], model: ZoomWindowModel, stripSize: CGSize, spec: ZoomInkSpec) -> PKStroke? {
        guard let first = samples.first else { return nil }
        var points = samples.map { sample in
            PKStrokePoint(location: model.pageLocation(forStrip: sample.location, stripSize: stripSize),
                          timeOffset: max(sample.time - first.time, 0),
                          size: CGSize(width: spec.width, height: spec.width), opacity: 1, force: 1,
                          azimuth: sample.azimuth, altitude: sample.altitude)
        }
        if points.count == 1, let dot = points.first {
            points.append(PKStrokePoint(location: dot.location, timeOffset: dot.timeOffset + 0.01, size: dot.size,
                                        opacity: dot.opacity, force: dot.force, azimuth: dot.azimuth, altitude: dot.altitude))
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKStroke(ink: spec.ink, path: path)
    }
}
