import Foundation

/// Small helpers for the JSON blobs stored on models. Encoding is deterministic (sorted keys).
public enum JSONCoding {
    public static func encode<T: Encodable>(_ value: T) -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        // Encoding our own plain value types cannot fail; an empty blob decodes to nil and callers fall back to defaults.
        return (try? enc.encode(value)) ?? Data()
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(type, from: data)
    }
}
