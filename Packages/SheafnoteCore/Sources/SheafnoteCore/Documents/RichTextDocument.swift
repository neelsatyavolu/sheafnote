import Foundation

public enum RichTextError: LocalizedError, Equatable {
    case unreadable
    case newerFormat(Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable:
            "This text document could not be read. Nothing was changed; the original is still stored."
        case .newerFormat:
            "This text document was saved by a newer version of Sheafnote. Update the app to edit it. Nothing was changed."
        }
    }
}

public enum RichTextBlockKind: String, Codable, CaseIterable, Sendable {
    case paragraph, heading1, heading2, heading3, bullet, numbered, checklist, image

    public var isList: Bool { self == .bullet || self == .numbered || self == .checklist }
}

public enum RichTextStyle: Sendable { case bold, italic, underline }

/// One paragraph-level block. Inline styles apply to the whole block.
public struct RichTextBlock: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: RichTextBlockKind
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var checked: Bool
    /// Image blocks: the `Asset` holding the picture.
    public var assetID: UUID?

    public init(id: UUID = UUID(), kind: RichTextBlockKind = .paragraph, text: String = "", bold: Bool = false,
                italic: Bool = false, underline: Bool = false, checked: Bool = false, assetID: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.checked = checked
        self.assetID = assetID
    }

    private enum CodingKeys: String, CodingKey { case id, kind, text, bold, italic, underline, checked, assetID }

    /// Lenient: unknown kinds become paragraphs and missing fields take defaults, so newer builds' blocks still open.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let rawKind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        kind = RichTextBlockKind(rawValue: rawKind) ?? .paragraph
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try c.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        underline = try c.decodeIfPresent(Bool.self, forKey: .underline) ?? false
        checked = try c.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        assetID = try c.decodeIfPresent(UUID.self, forKey: .assetID)
    }
}

/// A text document: an ordered list of blocks (headings, paragraphs, lists, checklists, images), stored as JSON
/// in `Notebook.richText`. All edits return a new value.
public struct RichTextDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var blocks: [RichTextBlock]

    public init(blocks: [RichTextBlock]) {
        self.version = Self.currentVersion
        self.blocks = blocks.isEmpty ? [RichTextBlock()] : blocks
    }

    public static var empty: RichTextDocument { RichTextDocument(blocks: [RichTextBlock()]) }

    // MARK: Codec

    public func encoded() -> Data { JSONCoding.encode(self) }

    /// Throws instead of returning an empty document, so a caller can never overwrite stored text it failed to read.
    public static func decode(_ data: Data) throws -> RichTextDocument {
        guard let doc = JSONCoding.decode(RichTextDocument.self, from: data) else { throw RichTextError.unreadable }
        if doc.version > currentVersion { throw RichTextError.newerFormat(doc.version) }
        return RichTextDocument(blocks: doc.blocks)
    }

    // MARK: Queries

    public func index(of id: UUID) -> Int? { blocks.firstIndex { $0.id == id } }

    /// Position within a run of consecutive numbered blocks (1-based); nil for other blocks.
    public var numbers: [Int?] {
        var count = 0
        return blocks.map { block in
            guard block.kind == .numbered else { count = 0; return nil }
            count += 1
            return count
        }
    }

    /// Text with list markers, for sharing.
    public var plainText: String {
        let nums = numbers
        return blocks.enumerated().compactMap { i, b -> String? in
            switch b.kind {
            case .bullet: "• " + b.text
            case .checklist: (b.checked ? "☑ " : "☐ ") + b.text
            case .numbered: "\(nums[i] ?? 1). " + b.text
            case .image: nil
            default: b.text
            }
        }.joined(separator: "\n")
    }

    /// Text only, for the search index.
    public var searchableText: String {
        blocks.filter { $0.kind != .image && !$0.text.isEmpty }.map(\.text).joined(separator: "\n")
    }

    // MARK: Edits

    private func updating(_ id: UUID, _ change: (inout RichTextBlock) -> Void) -> RichTextDocument {
        guard let i = index(of: id) else { return self }
        var copy = self
        change(&copy.blocks[i])
        return copy
    }

    public func settingText(_ text: String, for id: UUID) -> RichTextDocument {
        updating(id) { $0.text = text }
    }

    public func settingKind(_ kind: RichTextBlockKind, for id: UUID) -> RichTextDocument {
        updating(id) {
            $0.kind = kind
            if kind != .checklist { $0.checked = false }
        }
    }

    public func togglingChecked(for id: UUID) -> RichTextDocument {
        updating(id) { if $0.kind == .checklist { $0.checked.toggle() } }
    }

    public func togglingStyle(_ style: RichTextStyle, for id: UUID) -> RichTextDocument {
        updating(id) {
            switch style {
            case .bold: $0.bold.toggle()
            case .italic: $0.italic.toggle()
            case .underline: $0.underline.toggle()
            }
        }
    }

    /// Applies new text from a field. Each newline starts a new block that continues a list or, after a heading,
    /// becomes a paragraph. A newline pressed in an empty list item ends the list. Returns the block to focus.
    public func applyingEdit(_ newText: String, to id: UUID) -> (document: RichTextDocument, focus: UUID) {
        guard let i = index(of: id) else { return (self, id) }
        let lines = newText.components(separatedBy: "\n")
        guard lines.count > 1 else { return (settingText(newText, for: id), id) }
        let source = blocks[i]
        if source.kind.isList, source.text.isEmpty, lines.allSatisfy(\.isEmpty) {
            return (settingKind(.paragraph, for: id), id)
        }
        var copy = self
        copy.blocks[i].text = lines[0]
        let followKind: RichTextBlockKind = source.kind.isList ? source.kind : .paragraph
        let added = lines.dropFirst().map {
            RichTextBlock(kind: followKind, text: $0, bold: source.bold, italic: source.italic, underline: source.underline)
        }
        copy.blocks.insert(contentsOf: added, at: i + 1)
        return (copy, added.last?.id ?? id)
    }

    public func removingBlock(_ id: UUID) -> RichTextDocument {
        guard let i = index(of: id) else { return self }
        var copy = self
        copy.blocks.remove(at: i)
        if copy.blocks.isEmpty { copy.blocks = [RichTextBlock()] }
        return copy
    }

    public func movingBlock(_ id: UUID, to destination: Int) -> RichTextDocument {
        guard let i = index(of: id) else { return self }
        var copy = self
        let block = copy.blocks.remove(at: i)
        copy.blocks.insert(block, at: min(max(destination, 0), copy.blocks.count))
        return copy
    }

    /// Inserts an image block after `id` followed by an empty paragraph to keep typing.
    public func insertingImage(_ assetID: UUID, after id: UUID?) -> (document: RichTextDocument, focus: UUID) {
        var copy = self
        let at = id.flatMap(index(of:)).map { $0 + 1 } ?? copy.blocks.count
        let image = RichTextBlock(kind: .image, assetID: assetID)
        let tail = RichTextBlock()
        copy.blocks.insert(contentsOf: [image, tail], at: at)
        return (copy, tail.id)
    }
}
