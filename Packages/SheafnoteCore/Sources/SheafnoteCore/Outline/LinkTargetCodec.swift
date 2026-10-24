import Foundation

public enum LinkURLError: LocalizedError, Equatable {
    case empty
    case invalid
    case unsupportedScheme(String)

    public var errorDescription: String? {
        switch self {
        case .empty: "Type a web address to link to."
        case .invalid: "That doesn't look like a web address."
        case .unsupportedScheme(let s): "Links starting with \"\(s):\" aren't supported. Use a web address or an email address."
        }
    }
}

/// Reads typed web addresses for links and turns link targets into text and back (sheafnote:// addresses are used
/// for accessibility values and drag and drop).
public enum LinkTargetCodec {
    public static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    public static func parseURL(_ input: String) -> Result<LinkTarget, LinkURLError> {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        if let scheme = explicitScheme(of: text) {
            guard allowedSchemes.contains(scheme) else { return .failure(.unsupportedScheme(scheme)) }
            guard let url = URL(string: text), url.host != nil || scheme == "mailto" else { return .failure(.invalid) }
            return .success(.url(url))
        }
        guard !text.contains(" "), text.contains("."), let url = URL(string: "https://" + text), url.host != nil else {
            return .failure(.invalid)
        }
        return .success(.url(url))
    }

    public static func encode(_ target: LinkTarget) -> String {
        switch target {
        case .page(let id): "sheafnote://page/\(id.uuidString)"
        case .notebook(let id): "sheafnote://notebook/\(id.uuidString)"
        case .url(let url): url.absoluteString
        }
    }

    public static func decode(_ text: String) -> LinkTarget? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "sheafnote" {
            guard let kind = url.host, let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            switch kind {
            case "page": return .page(id)
            case "notebook": return .notebook(id)
            default: return nil
            }
        }
        return allowedSchemes.contains(scheme) ? .url(url) : nil
    }

    /// "javascript:..." or "https://..."; nil for "example.com" or "host:8080/x" (a port, not a scheme).
    private static func explicitScheme(of text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let scheme = String(text[..<colon])
        guard !scheme.isEmpty, scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }),
              scheme.first?.isLetter == true else { return nil }
        let rest = text[text.index(after: colon)...]
        if rest.hasPrefix("//") || scheme.lowercased() == "mailto" || !(rest.first?.isNumber ?? false) {
            return scheme.lowercased()
        }
        return nil
    }
}
