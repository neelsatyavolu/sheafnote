import Foundation
import SwiftData

@Model
public final class Notebook: SyncableRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?
    public var syncDirty: Bool
    public var dirtyFields: [String]
    public var ckSystemFields: Data?
    public var formatVersion: Int

    public var title: String
    public var kind: NotebookKind
    public var folderID: UUID?
    public var coverSpec: Data
    public var defaultTemplate: Data
    public var paperSize: String
    public var orientation: String
    public var paperColor: String
    public var scrollDirection: String
    public var isFavorite: Bool
    public var isLocked: Bool
    public var lastOpenedAt: Date?
    public var sortKey: String
    @Attribute(.externalStorage) public var richText: Data?
    public var pdfOutlineImported: Bool

    public static var recordType: String { "SNNotebook" }

    public init(id: UUID = UUID(), title: String, kind: NotebookKind, folderID: UUID?,
                cover: CoverSpec, template: TemplateSpec, paperSize: PaperSize,
                orientation: PageOrientation, paperColor: PaperColor, sortKey: String, now: Date = .now) {
        self.id = id
        self.createdAt = now
        self.modifiedAt = now
        self.deletedAt = nil
        self.syncDirty = true
        self.dirtyFields = []
        self.ckSystemFields = nil
        self.formatVersion = SchemaFormat.currentVersion
        self.title = title
        self.kind = kind
        self.folderID = folderID
        self.coverSpec = JSONCoding.encode(cover)
        self.defaultTemplate = JSONCoding.encode(template)
        self.paperSize = paperSize.rawValue
        self.orientation = orientation.rawValue
        self.paperColor = paperColor.rawValue
        self.scrollDirection = ScrollDirection.vertical.rawValue
        self.isFavorite = false
        self.isLocked = false
        self.lastOpenedAt = nil
        self.sortKey = sortKey
        self.richText = nil
        self.pdfOutlineImported = false
    }
}

public extension Notebook {
    var cover: CoverSpec {
        get { JSONCoding.decode(CoverSpec.self, from: coverSpec) ?? CoverSpec.default }
        set { coverSpec = JSONCoding.encode(newValue) }
    }
    var template: TemplateSpec {
        get { JSONCoding.decode(TemplateSpec.self, from: defaultTemplate) ?? TemplateSpec(kind: .blank) }
        set { defaultTemplate = JSONCoding.encode(newValue) }
    }
    var paperSizeValue: PaperSize { PaperSize(rawValue: paperSize) ?? .a4 }
    var orientationValue: PageOrientation { PageOrientation(rawValue: orientation) ?? .portrait }
    var paperColorValue: PaperColor { PaperColor(rawValue: paperColor) ?? .white }
    var scrollDirectionValue: ScrollDirection {
        get { ScrollDirection(rawValue: scrollDirection) ?? .vertical }
        set { scrollDirection = newValue.rawValue }
    }
    /// Page size in points for new pages of this notebook.
    var pageSize: CGSize { paperSizeValue.size(orientation: orientationValue) }
}
