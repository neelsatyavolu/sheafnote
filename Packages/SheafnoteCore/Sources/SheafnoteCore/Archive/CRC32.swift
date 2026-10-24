import Foundation

/// CRC-32 (IEEE 802.3, the polynomial ZIP uses), table driven and incremental.
public struct CRC32: Sendable {
    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private var state: UInt32 = 0xFFFF_FFFF

    public init() {}

    public mutating func update<D: DataProtocol>(_ data: D) {
        var c = state
        for region in data.regions {
            region.withUnsafeBytes { raw in
                for byte in raw { c = Self.table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
            }
        }
        state = c
    }

    public var value: UInt32 { state ^ 0xFFFF_FFFF }

    public static func checksum<D: DataProtocol>(of data: D) -> UInt32 {
        var crc = CRC32()
        crc.update(data)
        return crc.value
    }
}
