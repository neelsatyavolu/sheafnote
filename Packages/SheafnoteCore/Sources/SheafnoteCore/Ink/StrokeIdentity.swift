import CryptoKit
import Foundation

/// Stable identity of a stroke (PKStroke has none). Equal content gives an equal id; any change gives a new one.
public struct StrokeID: Hashable, Codable, Sendable, Comparable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static func < (l: StrokeID, r: StrokeID) -> Bool { l.rawValue < r.rawValue }
}

public struct StrokePoint: Codable, Hashable, Sendable {
    public var x: Float, y: Float, timeOffset: Float, force: Float
    public var azimuth: Float, altitude: Float, width: Float, height: Float

    public init(x: Float, y: Float, timeOffset: Float, force: Float,
                azimuth: Float, altitude: Float, width: Float, height: Float) {
        self.x = x; self.y = y; self.timeOffset = timeOffset; self.force = force
        self.azimuth = azimuth; self.altitude = altitude; self.width = width; self.height = height
    }
}

/// PencilKit-free snapshot of one stroke, built in the app by `PKStroke+StrokeRecord`.
public struct StrokeRecord: Codable, Hashable, Sendable {
    public var inkType: String
    public var colorRGBA: [Double]          // 4 doubles
    public var transform: [Double]          // a,b,c,d,tx,ty
    public var creationDate: Date
    public var maskPath: Data?
    public var points: [StrokePoint]

    public init(inkType: String, colorRGBA: [Double], transform: [Double], creationDate: Date,
                maskPath: Data?, points: [StrokePoint]) {
        self.inkType = inkType
        self.colorRGBA = colorRGBA
        self.transform = transform
        self.creationDate = creationDate
        self.maskPath = maskPath
        self.points = points
    }
}

public enum StrokeIdentity {
    /// SHA-256 over canonical little-endian bytes of ALL fields, hex, first 32 chars.
    public static func id(for s: StrokeRecord) -> StrokeID {
        var bytes = Data()
        bytes.appendString(s.inkType)
        bytes.appendDoubles(s.colorRGBA)
        bytes.appendDoubles(s.transform)
        bytes.appendLE(s.creationDate.timeIntervalSinceReferenceDate.bitPattern)
        if let mask = s.maskPath {
            bytes.append(1)
            bytes.appendLE(UInt32(mask.count))
            bytes.append(mask)
        } else {
            bytes.append(0)
        }
        bytes.appendLE(UInt32(s.points.count))
        for p in s.points {
            for f in [p.x, p.y, p.timeOffset, p.force, p.azimuth, p.altitude, p.width, p.height] {
                bytes.appendLE(f.bitPattern)
            }
        }
        let digest = SHA256.hash(data: bytes)
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return StrokeID(rawValue: hex)
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ v: T) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func appendString(_ s: String) {
        let utf8 = Data(s.utf8)
        appendLE(UInt32(utf8.count))
        append(utf8)
    }

    mutating func appendDoubles(_ values: [Double]) {
        appendLE(UInt32(values.count))
        for v in values { appendLE(v.bitPattern) }
    }
}
