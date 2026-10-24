import CoreGraphics
import Foundation

extension PageElement: SyncCodable {
    static var domainFields: [String] {
        ["pageID", "kind", "x", "y", "width", "height", "rotation", "zIndex", "payload", "assetID"]
    }
    static var requiredFields: [String] { ["pageID"] }

    func encodeDomain(into bag: inout FieldBag) {
        bag.set("pageID", pageID); bag.set("kind", kind.rawValue)
        bag.set("x", x); bag.set("y", y); bag.set("width", width); bag.set("height", height)
        bag.set("rotation", rotation); bag.set("zIndex", zIndex); bag.set("payload", payload); bag.set("assetID", assetID)
    }

    func assign(_ r: SyncRecord, fields: Set<String>) {
        if fields.contains("pageID") { pageID = r.uuid("pageID") ?? pageID }
        if fields.contains("kind") { kind = r.string("kind").flatMap(ElementKind.init(rawValue:)) ?? kind }
        if fields.contains("x") { x = r.double("x") ?? 0 }
        if fields.contains("y") { y = r.double("y") ?? 0 }
        if fields.contains("width") { width = r.double("width") ?? 0 }
        if fields.contains("height") { height = r.double("height") ?? 0 }
        if fields.contains("rotation") { rotation = r.double("rotation") ?? 0 }
        if fields.contains("zIndex") { zIndex = r.int("zIndex") ?? 0 }
        if fields.contains("payload") { payload = r.bytes("payload") ?? Data() }
        if fields.contains("assetID") { assetID = r.uuid("assetID") }
    }

    static func blank(id: UUID) -> PageElement {
        PageElement(value: ElementValue(id: id, pageID: UUID(), kind: .text, frame: .zero))
    }
}

extension Asset: SyncCodable {
    static var domainFields: [String] { ["kind", "data", "byteCount", "sha256", "filename", "uti"] }

    func encodeDomain(into bag: inout FieldBag) {
        bag.set("kind", kind.rawValue); bag.set("data", data); bag.set("byteCount", byteCount)
        bag.set("sha256", sha256); bag.set("filename", filename); bag.set("uti", uti)
    }

    func assign(_ r: SyncRecord, fields: Set<String>) {
        if fields.contains("kind") { kind = r.string("kind").flatMap(AssetKind.init(rawValue:)) ?? kind }
        if fields.contains("data") { data = r.bytes("data") ?? Data() }
        if fields.contains("byteCount") { byteCount = r.int("byteCount") ?? data.count }
        if fields.contains("sha256") { sha256 = r.string("sha256") ?? "" }
        if fields.contains("filename") { filename = r.string("filename") }
        if fields.contains("uti") { uti = r.string("uti") }
    }

    static func blank(id: UUID) -> Asset { Asset(id: id, kind: .image, data: Data(), sha256: "") }
}

extension OutlineEntry: SyncCodable {
    static var domainFields: [String] { ["notebookID", "title", "pageID", "pdfPageIndex", "parentID", "sortKey", "source"] }
    static var requiredFields: [String] { ["notebookID"] }

    func encodeDomain(into bag: inout FieldBag) {
        bag.set("notebookID", notebookID); bag.set("title", title); bag.set("pageID", pageID)
        bag.set("pdfPageIndex", pdfPageIndex); bag.set("parentID", parentID); bag.set("sortKey", sortKey)
        bag.set("source", source)
    }

    func assign(_ r: SyncRecord, fields: Set<String>) {
        if fields.contains("notebookID") { notebookID = r.uuid("notebookID") ?? notebookID }
        if fields.contains("title") { title = r.string("title") ?? "" }
        if fields.contains("pageID") { pageID = r.uuid("pageID") }
        if fields.contains("pdfPageIndex") { pdfPageIndex = r.int("pdfPageIndex") }
        if fields.contains("parentID") { parentID = r.uuid("parentID") }
        if fields.contains("sortKey") { sortKey = r.string("sortKey") ?? "" }
        if fields.contains("source") { source = r.string("source") ?? source }
    }

    static func blank(id: UUID) -> OutlineEntry {
        OutlineEntry(id: id, notebookID: UUID(), title: "", pageID: nil, sortKey: "")
    }
}

extension Bookmark: SyncCodable {
    static var domainFields: [String] { ["notebookID", "pageID", "title"] }
    static var requiredFields: [String] { ["notebookID", "pageID"] }

    func encodeDomain(into bag: inout FieldBag) {
        bag.set("notebookID", notebookID); bag.set("pageID", pageID); bag.set("title", title)
    }

    func assign(_ r: SyncRecord, fields: Set<String>) {
        if fields.contains("notebookID") { notebookID = r.uuid("notebookID") ?? notebookID }
        if fields.contains("pageID") { pageID = r.uuid("pageID") ?? pageID }
        if fields.contains("title") { title = r.string("title") }
    }

    static func blank(id: UUID) -> Bookmark { Bookmark(id: id, notebookID: UUID(), pageID: UUID()) }
}
