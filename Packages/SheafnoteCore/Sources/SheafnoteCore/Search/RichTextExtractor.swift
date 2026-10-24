import Foundation

/// Plain text of a text document (`Notebook.richText`). The document is JSON; every string stored under a
/// `text` key is collected in reading order, so the extractor keeps working while the editor's format grows.
public enum RichTextExtractor {
    public static func plainText(fromJSON data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return "" }
        var parts: [String] = []
        collect(root, into: &parts)
        return parts.joined(separator: "\n")
    }

    private static func collect(_ value: Any, into parts: inout [String]) {
        if let array = value as? [Any] {
            for item in array { collect(item, into: &parts) }
        } else if let object = value as? [String: Any] {
            if let text = object["text"] as? String, !text.isEmpty { parts.append(text) }
            for key in object.keys.sorted() where key != "text" { collect(object[key] as Any, into: &parts) }
        }
    }
}
