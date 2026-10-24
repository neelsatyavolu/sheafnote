import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

enum ImageHash {
    static func pixels(_ image: CGImage) -> Int {
        guard let data = image.dataProvider?.data as Data? else { return 0 }
        var h = Hasher()
        h.combine(data)
        return h.finalize()
    }
}

@Suite struct CoverTests {
    @Test func twentyUniqueCovers() {
        #expect(CoverCatalog.all.count == 20)
        #expect(Set(CoverCatalog.all.map(\.id)).count == 20)
        #expect(Set(CoverCatalog.all.map(\.name)).count == 20)
    }

    @Test func mixOfSolidsAndPatterns() {
        let solids = CoverCatalog.all.filter { $0.pattern == .solid }.count
        #expect(solids >= 6)
        #expect(Set(CoverCatalog.all.map(\.pattern)).count >= 10)
    }

    @Test func everyCoverRendersUniquely() throws {
        var hashes = Set<Int>()
        for cover in CoverCatalog.all {
            let img = try #require(CoverRenderer.renderImage(cover, size: CGSize(width: 120, height: 160)))
            hashes.insert(ImageHash.pixels(img))
        }
        #expect(hashes.count == 20)
    }

    @Test func renderingIsDeterministic() throws {
        let c = CoverCatalog.all[10]
        let a = try #require(CoverRenderer.renderImage(c, size: CGSize(width: 90, height: 120)))
        let b = try #require(CoverRenderer.renderImage(c, size: CGSize(width: 90, height: 120)))
        #expect(ImageHash.pixels(a) == ImageHash.pixels(b))
    }

    @Test func unknownIDFallsBackToFirst() {
        #expect(CoverCatalog.definition(for: "nonexistent").id == CoverCatalog.all[0].id)
        #expect(CoverSpec.default.definition.id == "slate")
    }

    @Test func specRoundTrip() {
        let spec = CoverSpec(coverID: "tide")
        #expect(JSONCoding.decode(CoverSpec.self, from: JSONCoding.encode(spec)) == spec)
    }

    @Test func tinySizesDoNotCrash() {
        for c in CoverCatalog.all { _ = CoverRenderer.renderImage(c, size: CGSize(width: 1, height: 1)) }
    }
}
