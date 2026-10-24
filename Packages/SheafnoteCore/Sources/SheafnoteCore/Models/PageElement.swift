import CoreGraphics
import Foundation
import SwiftData

/// Value copy of a `PageElement`; used everywhere instead of the @Model class.
public struct ElementValue: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var pageID: UUID
    public var kind: ElementKind
    public var frame: CGRect
    public var rotation: Double
    public var zIndex: Int
    public var payload: Data
    public var assetID: UUID?

    public init(id: UUID = UUID(), pageID: UUID, kind: ElementKind, frame: CGRect, rotation: Double = 0,
                zIndex: Int = 0, payload: Data = Data(), assetID: UUID? = nil) {
        self.id = id
        self.pageID = pageID
        self.kind = kind
        self.frame = frame
        self.rotation = rotation
        self.zIndex = zIndex
        self.payload = payload
        self.assetID = assetID
    }
}

@Model
public final class PageElement: SyncableRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?
    public var syncDirty: Bool
    public var dirtyFields: [String]
    public var ckSystemFields: Data?
    public var formatVersion: Int

    public var pageID: UUID
    public var kind: ElementKind
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var rotation: Double
    public var zIndex: Int
    public var payload: Data
    public var assetID: UUID?

    public static var recordType: String { "SNPageElement" }

    public init(value: ElementValue, now: Date = .now) {
        self.id = value.id
        self.createdAt = now
        self.modifiedAt = now
        self.deletedAt = nil
        self.syncDirty = true
        self.dirtyFields = []
        self.ckSystemFields = nil
        self.formatVersion = SchemaFormat.currentVersion
        self.pageID = value.pageID
        self.kind = value.kind
        self.x = Double(value.frame.origin.x)
        self.y = Double(value.frame.origin.y)
        self.width = Double(value.frame.size.width)
        self.height = Double(value.frame.size.height)
        self.rotation = value.rotation
        self.zIndex = value.zIndex
        self.payload = value.payload
        self.assetID = value.assetID
    }
}

public extension PageElement {
    var value: ElementValue {
        get {
            ElementValue(id: id, pageID: pageID, kind: kind, frame: CGRect(x: x, y: y, width: width, height: height),
                         rotation: rotation, zIndex: zIndex, payload: payload, assetID: assetID)
        }
        set {
            pageID = newValue.pageID
            kind = newValue.kind
            x = Double(newValue.frame.origin.x)
            y = Double(newValue.frame.origin.y)
            width = Double(newValue.frame.size.width)
            height = Double(newValue.frame.size.height)
            rotation = newValue.rotation
            zIndex = newValue.zIndex
            payload = newValue.payload
            assetID = newValue.assetID
        }
    }
}
