import Foundation

/// Rewrites ids that appear inside stored JSON (link targets, audio timelines) when an archive is imported as new
/// copies. Any string value equal to a known old id is replaced; everything else is left byte-for-byte alone.
enum UUIDRemapper {
    static func remap(_ json: Data, using map: [UUID: UUID]) -> Data {
        guard !json.isEmpty, !map.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed]) else { return json }
        var changed = false
        let rewritten = walk(object, map, &changed)
        guard changed,
              let data = try? JSONSerialization.data(withJSONObject: rewritten, options: [.sortedKeys, .fragmentsAllowed])
        else { return json }
        return data
    }

    private static func walk(_ value: Any, _ map: [UUID: UUID], _ changed: inout Bool) -> Any {
        switch value {
        case let text as String:
            guard let old = UUID(uuidString: text), let new = map[old] else { return text }
            changed = true
            return new.uuidString
        case let array as [Any]:
            return array.map { walk($0, map, &changed) }
        case let dict as [String: Any]:
            return dict.mapValues { walk($0, map, &changed) }
        default:
            return value
        }
    }
}
