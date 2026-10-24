import PencilKit
import UIKit
import SheafnoteCore

/// Adapter from PencilKit strokes to the PencilKit-free `StrokeRecord` that core hashes into a stable `StrokeID`.
extension PKStroke {
    var strokeRecord: StrokeRecord {
        let color = ink.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let t = transform
        let points = path.map { p in
            StrokePoint(x: Float(p.location.x), y: Float(p.location.y), timeOffset: Float(p.timeOffset),
                        force: Float(p.force), azimuth: Float(p.azimuth), altitude: Float(p.altitude),
                        width: Float(p.size.width), height: Float(p.size.height))
        }
        return StrokeRecord(inkType: ink.inkType.rawValue,
                            colorRGBA: [Double(r), Double(g), Double(b), Double(a)],
                            transform: [t.a, t.b, t.c, t.d, t.tx, t.ty].map(Double.init),
                            creationDate: path.creationDate,
                            maskPath: mask.map(Self.encode(mask:)),
                            points: points)
    }

    var strokeID: StrokeID { StrokeIdentity.id(for: strokeRecord) }

    /// Canonical bytes of the mask outline (element type + points), stable across runs.
    private static func encode(mask: UIBezierPath) -> Data {
        var values: [Float] = []
        mask.cgPath.applyWithBlock { element in
            let e = element.pointee
            values.append(Float(e.type.rawValue))
            let count: Int
            switch e.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            for i in 0..<count {
                values.append(Float(e.points[i].x))
                values.append(Float(e.points[i].y))
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

extension PKDrawing {
    /// Ids aligned with `strokes`.
    var strokeIDs: [StrokeID] { strokes.map(\.strokeID) }
}

/// Carries a drawing across actors. `PKDrawing` is an immutable value; this keeps strict concurrency quiet.
struct SendableDrawing: @unchecked Sendable {
    let drawing: PKDrawing
}
