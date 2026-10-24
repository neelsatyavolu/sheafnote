import Foundation
import SwiftData

@Model
public final class Page: SyncableRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?
    public var syncDirty: Bool
    public var dirtyFields: [String]
    public var ckSystemFields: Data?
    public var formatVersion: Int

    public var notebookID: UUID
    public var sortKey: String
    public var widthPts: Double
    public var heightPts: Double
    public var templateOverride: Data?
    public var paperColorOverride: String?
    public var backgroundAssetID: UUID?
    public var backgroundPageIndex: Int?
    @Attribute(.externalStorage) public var inkData: Data?
    public var strokeIDs: [String]
    public var inkHash: String
    /// LOCAL ONLY: last server version of the ink, base for three-way merge.
    @Attribute(.externalStorage) public var baseInkData: Data?
    /// LOCAL ONLY
    public var baseStrokeIDs: [String]
    public var recognizedText: String
    public var ocrInkHash: String
    public var isInfinite: Bool

    public static var recordType: String { "SNPage" }

    public init(id: UUID = UUID(), notebookID: UUID, sortKey: String, size: CGSize,
                isInfinite: Bool = false, now: Date = .now) {
        self.id = id
        self.createdAt = now
        self.modifiedAt = now
        self.deletedAt = nil
        self.syncDirty = true
        self.dirtyFields = []
        self.ckSystemFields = nil
        self.formatVersion = SchemaFormat.currentVersion
        self.notebookID = notebookID
        self.sortKey = sortKey
        self.widthPts = Double(size.width)
        self.heightPts = Double(size.height)
        self.templateOverride = nil
        self.paperColorOverride = nil
        self.backgroundAssetID = nil
        self.backgroundPageIndex = nil
        self.inkData = nil
        self.strokeIDs = []
        self.inkHash = ""
        self.baseInkData = nil
        self.baseStrokeIDs = []
        self.recognizedText = ""
        self.ocrInkHash = ""
        self.isInfinite = isInfinite
    }
}

public extension Page {
    var size: CGSize { CGSize(width: widthPts, height: heightPts) }
    var template: TemplateSpec? {
        get { templateOverride.flatMap { JSONCoding.decode(TemplateSpec.self, from: $0) } }
        set { templateOverride = newValue.map { JSONCoding.encode($0) } }
    }
    var paperColorOverrideValue: PaperColor? { paperColorOverride.flatMap(PaperColor.init(rawValue:)) }
    var hasInk: Bool { !strokeIDs.isEmpty }
}
