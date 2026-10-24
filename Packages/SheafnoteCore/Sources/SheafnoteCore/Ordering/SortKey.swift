import Foundation

/// Fractional sort keys: base-62 digit strings ordered by plain string comparison.
/// Keys never end in "0". Length grows by about one character per 31 appends or per 5 inserts at the same spot. `between` returns a key strictly between two keys without rewriting neighbours.
public enum SortKey {
    private static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let base = 62

    private static func value(_ c: Character) -> Int { digits.firstIndex(of: c) ?? 0 }

    /// Key strictly between `a` and `b` (nil = open end). If `a >= b` (equal keys made on two devices),
    /// returns a key just after `a`; callers break ties by id.
    public static func between(_ a: String?, _ b: String?) -> String {
        let lower = a ?? ""
        if let b, lower >= b { return lower + String(digits[base / 2]) }
        guard let b else { return lower.isEmpty ? String(digits[base / 2]) : increment(lower) }
        return midpoint(Array(lower), Array(b))
    }

    /// Ordering used everywhere pages/items are sorted: key, then id (deterministic when keys collide).
    public static func areInIncreasingOrder(_ l: (key: String, id: UUID), _ r: (key: String, id: UUID)) -> Bool {
        l.key == r.key ? l.id.uuidString < r.id.uuidString : l.key < r.key
    }

    private static func midpoint(_ a: [Character], _ b: [Character]?) -> String {
        if let b {
            var n = 0
            while n < b.count, (n < a.count ? a[n] : digits[0]) == b[n] { n += 1 }
            if n > 0 {
                return String(b.prefix(n)) + midpoint(Array(a.dropFirst(n)), Array(b.dropFirst(n)))
            }
        }
        let da = a.isEmpty ? 0 : value(a[0])
        let db = b.map { value($0[0]) } ?? base
        if db - da > 1 { return String(digits[(da + db) / 2]) }
        if let b, b.count > 1 { return String(b[0]) }
        return String(digits[da]) + midpoint(Array(a.dropFirst()), nil)
    }

    /// Next key after `a` (append): counts up in base 62 so long runs of appends stay short.
    private static func increment(_ a: String) -> String {
        var chars = Array(a)
        var i = chars.count - 1
        while i >= 0 {
            let v = value(chars[i])
            if v < base - 1 {
                chars[i] = digits[v + 1]
                var s = String(chars.prefix(i + 1))
                while s.hasSuffix("0") { s.removeLast() }
                return s
            }
            i -= 1
        }
        return a + String(digits[base / 2])
    }
}
