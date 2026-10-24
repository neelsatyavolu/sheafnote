import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct StrokeIdentityTests {
    func base() -> StrokeRecord {
        StrokeRecord(inkType: "pen", colorRGBA: [0, 0, 0, 1], transform: [1, 0, 0, 1, 0, 0],
                     creationDate: Date(timeIntervalSinceReferenceDate: 1000), maskPath: nil,
                     points: [StrokePoint(x: 1, y: 2, timeOffset: 0, force: 0.5, azimuth: 0, altitude: 1, width: 3, height: 3),
                              StrokePoint(x: 4, y: 5, timeOffset: 0.1, force: 0.6, azimuth: 0, altitude: 1, width: 3, height: 3)])
    }

    @Test func stableAndShaped() {
        let a = StrokeIdentity.id(for: base()), b = StrokeIdentity.id(for: base())
        #expect(a == b)
        #expect(a.rawValue.count == 32)
        #expect(a.rawValue.allSatisfy { $0.isHexDigit })
    }

    @Test func sensitiveToEveryField() {
        let id = StrokeIdentity.id(for: base())
        var variants: [StrokeRecord] = []
        var v = base(); v.inkType = "marker"; variants.append(v)
        v = base(); v.colorRGBA = [1, 0, 0, 1]; variants.append(v)
        v = base(); v.transform = [1, 0, 0, 1, 5, 0]; variants.append(v)
        v = base(); v.creationDate = Date(timeIntervalSinceReferenceDate: 1001); variants.append(v)
        v = base(); v.maskPath = Data([1, 2, 3]); variants.append(v)
        v = base(); v.points[0].x = 1.5; variants.append(v)
        v = base(); v.points[0].y = 2.5; variants.append(v)
        v = base(); v.points[1].timeOffset = 0.2; variants.append(v)
        v = base(); v.points[1].force = 0.9; variants.append(v)
        v = base(); v.points[1].azimuth = 0.3; variants.append(v)
        v = base(); v.points[1].altitude = 0.4; variants.append(v)
        v = base(); v.points[1].width = 9; variants.append(v)
        v = base(); v.points[1].height = 9; variants.append(v)
        v = base(); v.points.removeLast(); variants.append(v)
        let ids = Set(variants.map { StrokeIdentity.id(for: $0) })
        #expect(ids.count == variants.count)
        #expect(!ids.contains(id))
    }

    @Test func differentMaskContentsDiffer() {
        var a = base(), b = base()
        a.maskPath = Data([1]); b.maskPath = Data([2])
        #expect(StrokeIdentity.id(for: a) != StrokeIdentity.id(for: b))
    }

    @Test func recordCodableRoundTrip() throws {
        let r = base()
        let back = try JSONDecoder().decode(StrokeRecord.self, from: JSONEncoder().encode(r))
        #expect(back == r)
    }
}
