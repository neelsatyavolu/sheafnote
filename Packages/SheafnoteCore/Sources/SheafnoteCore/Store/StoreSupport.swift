import CryptoKit
import Foundation
import SwiftData

public enum StoreError: LocalizedError, Equatable {
    case notFound(String)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let what): "Sheafnote could not find \(what). It may have been deleted on another device."
        case .invalid(let why): why
        }
    }
}

public enum LibraryItemRef: Hashable, Sendable {
    case folder(UUID)
    case notebook(UUID)

    public var id: UUID {
        switch self {
        case .folder(let id), .notebook(let id): id
        }
    }
}

public enum PagePosition: Sendable, Equatable {
    case before(UUID)
    case after(UUID)
    case end
}

/// A row removed for good (30-day purge or explicit "Delete Permanently"). Sync deletes the matching CloudKit record.
public struct PurgedRecord: Sendable, Hashable {
    public let recordType: String
    public let id: UUID
}

/// Resolves stored asset bytes (PDF, image, audio) by id.
public protocol AssetResolver: Sendable {
    func data(for assetID: UUID) async throws -> Data
}

enum Hashing {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Deterministic UUID from a string, so the same setting key maps to one record on every device.
    static func stableUUID(_ string: String) -> UUID {
        var b = Array(SHA256.hash(data: Data(string.utf8)).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
