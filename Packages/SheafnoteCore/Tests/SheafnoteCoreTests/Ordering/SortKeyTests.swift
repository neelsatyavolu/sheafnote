import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct SortKeyTests {
    @Test func firstKeyIsMiddle() {
        #expect(SortKey.between(nil, nil) == "V")
    }

    @Test func appendIsMonotonic() {
        var keys = [SortKey.between(nil, nil)]
        for _ in 0..<500 { keys.append(SortKey.between(keys.last, nil)) }
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == keys.count)
    }

    @Test func tenThousandAppendsGrowSlowly() {
        var key = SortKey.between(nil, nil)
        var last = key
        for _ in 0..<10_000 { last = key; key = SortKey.between(key, nil); #expect(key > last) }
        // About one extra character per 31 appends (a notebook rarely passes a few hundred pages).
        #expect(key.count <= 10_000 / 25)
    }

    @Test func prependIsMonotonic() {
        var keys = [SortKey.between(nil, nil)]
        for _ in 0..<200 { keys.insert(SortKey.between(nil, keys.first), at: 0) }
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == keys.count)
    }

    @Test func repeatedInsertAtSameSpotKeepsOrderAndStaysBounded() {
        let lo = "V"
        var hi = "W"
        for _ in 0..<2_000 {
            let mid = SortKey.between(lo, hi)
            #expect(mid > lo && mid < hi)
            hi = mid
        }
        #expect(hi.count <= 2_000 / 5 + 4)
    }

    @Test func betweenTwoKeys() {
        let k = SortKey.between("A", "B")
        #expect(k > "A" && k < "B")
        let j = SortKey.between("zz", nil)
        #expect(j > "zz")
        let m = SortKey.between("V", "VV")
        #expect(m > "V" && m < "VV")
    }

    @Test func keysNeverEndInZero() {
        var keys = ["V"]
        for i in 0..<300 {
            let k = i % 3 == 0 ? SortKey.between(nil, keys.first)
                : i % 3 == 1 ? SortKey.between(keys[0], keys.count > 1 ? keys[1] : nil) : SortKey.between(keys.last, nil)
            #expect(!k.hasSuffix("0"))
            keys.append(k)
            keys.sort()
        }
    }

    @Test func equalKeysFromTwoDevicesSortDeterministically() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        #expect(SortKey.areInIncreasingOrder(("V", a), ("V", b)))
        #expect(!SortKey.areInIncreasingOrder(("V", b), ("V", a)))
        #expect(SortKey.areInIncreasingOrder(("A", b), ("B", a)))
    }

    @Test func equalBoundsReturnKeyAfterLower() {
        let k = SortKey.between("V", "V")
        #expect(k > "V")
    }
}
