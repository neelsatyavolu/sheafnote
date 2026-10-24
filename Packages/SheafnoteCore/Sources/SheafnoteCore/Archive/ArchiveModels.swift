import Foundation

/// The JSON documents inside a `.sheafnote` archive. Plain values with explicit, stable field names (see docs/FORMAT.md).
/// Readers ignore unknown keys, so later versions can add fields without bumping `formatVersion`.
public enum ArchiveLayout {
    public static let formatName = "sheafnote-archive"
    public static let currentFormatVersion = 1
    public static let manifest = "manifest.json"
    public static let library = "library.json"
    public static func ink(_ pageID: UUID) -> String { "ink/\(pageID.uuidString).drawing" }
    public static func asset(_ id: UUID) -> String { "assets/\(id.uuidString)" }
    public static func richText(_ notebookID: UUID) -> String { "richtext/\(notebookID.uuidString).json" }
    public static func cardFront(_ id: UUID) -> String { "flashcards/\(id.uuidString).front.png" }
    public static func cardBack(_ id: UUID) -> String { "flashcards/\(id.uuidString).back.png" }
    public static func savedInk(_ id: UUID) -> String { "saved-elements/\(id.uuidString).drawing" }
    public static func savedThumbnail(_ id: UUID) -> String { "saved-elements/\(id.uuidString).thumbnail" }
}

public enum ArchiveScope: String, Codable, Sendable { case library, notebooks }

public struct ArchiveCounts: Codable, Equatable, Sendable {
    public var folders = 0, notebooks = 0, pages = 0, elements = 0, assets = 0
}

public struct ArchiveManifest: Codable, Equatable, Sendable {
    public var format: String
    public var formatVersion: Int
    public var createdAt: Date
    public var appVersion: String
    public var scope: ArchiveScope
    public var counts: ArchiveCounts
}

public struct ArchiveFolder: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var parentID: UUID?
    public var sortKey: String
    public var isFavorite: Bool
    public var colorName: String?
    public var createdAt: Date
    public var modifiedAt: Date
}

public struct ArchiveNotebook: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: NotebookKind
    public var folderID: UUID?
    public var cover: CoverSpec
    public var template: TemplateSpec
    public var paperSize: String
    public var orientation: String
    public var paperColor: String
    public var scrollDirection: String
    public var isFavorite: Bool
    public var isLocked: Bool
    public var sortKey: String
    public var pdfOutlineImported: Bool
    public var hasRichText: Bool
    public var createdAt: Date
    public var modifiedAt: Date
}

public struct ArchivePage: Codable, Equatable, Sendable {
    public var id: UUID
    public var notebookID: UUID
    public var sortKey: String
    public var width: Double
    public var height: Double
    public var templateOverride: TemplateSpec?
    public var paperColorOverride: String?
    public var backgroundAssetID: UUID?
    public var backgroundPageIndex: Int?
    public var strokeIDs: [String]
    public var inkHash: String
    public var recognizedText: String
    public var ocrInkHash: String
    public var isInfinite: Bool
    public var hasInk: Bool
    public var createdAt: Date
    public var modifiedAt: Date
}

public struct ArchiveElement: Codable, Equatable, Sendable {
    public var id: UUID
    public var pageID: UUID
    public var kind: ElementKind
    public var x: Double, y: Double, width: Double, height: Double
    public var rotation: Double
    public var zIndex: Int
    /// The kind's payload JSON, exactly as stored.
    public var payload: Data
    public var assetID: UUID?
    public var createdAt: Date
    public var modifiedAt: Date
}

public struct ArchiveAsset: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: AssetKind
    public var sha256: String
    public var byteCount: Int
    public var filename: String?
    public var uti: String?
}

public struct ArchiveOutlineEntry: Codable, Equatable, Sendable {
    public var id: UUID
    public var notebookID: UUID
    public var title: String
    public var pageID: UUID?
    public var pdfPageIndex: Int?
    public var parentID: UUID?
    public var sortKey: String
    public var source: String
}

public struct ArchiveBookmark: Codable, Equatable, Sendable {
    public var id: UUID
    public var notebookID: UUID
    public var pageID: UUID
    public var title: String?
}

public struct ArchiveAudioRecording: Codable, Equatable, Sendable {
    public var id: UUID
    public var notebookID: UUID
    public var assetID: UUID
    public var title: String
    public var startedAt: Date
    public var duration: Double
    /// JSON `[AudioStrokeMark]`, exactly as stored.
    public var timeline: Data
}

public struct ArchiveFlashcard: Codable, Equatable, Sendable {
    public var id: UUID
    public var notebookID: UUID
    public var deck: String
    public var sourcePageID: UUID?
    public var frontText: String?
    public var backText: String?
}

public struct ArchiveStudyState: Codable, Equatable, Sendable {
    public var id: UUID
    public var flashcardID: UUID
    public var ease: Double
    public var intervalDays: Int
    public var repetitions: Int
    public var lapses: Int
    public var dueAt: Date
    public var lastReviewedAt: Date?
}

public struct ArchiveSavedElement: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var category: String
    public var width: Double
    public var height: Double
    public var hasInk: Bool
    /// JSON `[ElementValue]`, exactly as stored.
    public var elements: Data
}

/// `library.json`: every record in the archive. Files named by `ArchiveLayout` hold the large blobs.
public struct ArchiveLibrary: Codable, Equatable, Sendable {
    public var folders: [ArchiveFolder] = []
    public var notebooks: [ArchiveNotebook] = []
    public var pages: [ArchivePage] = []
    public var elements: [ArchiveElement] = []
    public var assets: [ArchiveAsset] = []
    public var outline: [ArchiveOutlineEntry] = []
    public var bookmarks: [ArchiveBookmark] = []
    public var audioRecordings: [ArchiveAudioRecording] = []
    public var flashcards: [ArchiveFlashcard] = []
    public var studyStates: [ArchiveStudyState] = []
    public var savedElements: [ArchiveSavedElement] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        // Every list is optional so that archives written by older or newer versions still open.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folders = try c.decodeIfPresent([ArchiveFolder].self, forKey: .folders) ?? []
        notebooks = try c.decodeIfPresent([ArchiveNotebook].self, forKey: .notebooks) ?? []
        pages = try c.decodeIfPresent([ArchivePage].self, forKey: .pages) ?? []
        elements = try c.decodeIfPresent([ArchiveElement].self, forKey: .elements) ?? []
        assets = try c.decodeIfPresent([ArchiveAsset].self, forKey: .assets) ?? []
        outline = try c.decodeIfPresent([ArchiveOutlineEntry].self, forKey: .outline) ?? []
        bookmarks = try c.decodeIfPresent([ArchiveBookmark].self, forKey: .bookmarks) ?? []
        audioRecordings = try c.decodeIfPresent([ArchiveAudioRecording].self, forKey: .audioRecordings) ?? []
        flashcards = try c.decodeIfPresent([ArchiveFlashcard].self, forKey: .flashcards) ?? []
        studyStates = try c.decodeIfPresent([ArchiveStudyState].self, forKey: .studyStates) ?? []
        savedElements = try c.decodeIfPresent([ArchiveSavedElement].self, forKey: .savedElements) ?? []
    }

    var counts: ArchiveCounts {
        ArchiveCounts(folders: folders.count, notebooks: notebooks.count, pages: pages.count,
                      elements: elements.count, assets: assets.count)
    }
}

enum ArchiveJSON {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        do { return try enc.encode(value) } catch { throw ArchiveError.ioFailure(error.localizedDescription) }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, name: String) throws -> T {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do { return try dec.decode(type, from: data) } catch { throw ArchiveError.corrupt("\(name) can't be read") }
    }
}
