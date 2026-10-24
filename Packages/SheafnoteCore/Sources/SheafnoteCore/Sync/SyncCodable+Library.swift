import CoreGraphics
import Foundation

extension Folder: SyncCodable {
    static var domainFields: [String] { ["name", "parentID", "sortKey", "isFavorite", "colorName"] }

    func encodeDomain(into bag: inout FieldBag) {
        bag.set("name", name); bag.set("parentID", parentID); bag.set("sortKey", sortKey)
        bag.set("isFavorite", isFavorite); bag.set("colorName", colorName)
    }

    func assign(_ r: SyncRecord, fields: Set<String>) {
        if fields.contains("name") { name = r.string("name") ?? name }
        if fields.contains("parentID") { parentID = r.uuid("parentID") }
        if fields.contains("sortKey") { sortKey = r.string("sortKey") ?? sortKey }
        if fields.contains("isFavorite") { isFavorite = r.bool("isFavorite") ?? false }
        if fields.contains("colorName") { colorName = r.string("colorName") }
    }

    static func blank(id: UUID) -> Folder { Folder(id: id, name: "", parentID: nil, sortKey: "") }
}

extension Notebook: SyncCodable {
    static var domainFields: [String] {
        ["title", "kind", "folderID", "coverSpec", "defaultTemplate", "paperSize", "orientation", "paperColor",
         "scrollDirection", "isFavorite", "isLocked", "lastOpenedAt", "sortKey", "richText", "pdfOutlineImported"]
    }

    func encodeDomain(into bag: inout FieldBag) {
        bag.set("title", title); bag.set("kind", kind.rawValue); bag.set("folderID", folderID)
        bag.set("coverSpec", coverSpec); bag.set("defaultTemplate", defaultTemplate)
        bag.set("paperSize", paperSize); bag.set("orientation", orientation); bag.set("paperColor", paperColor)
        bag.set("scrollDirection", scrollDirection); bag.set("isFavorite", isFavorite); bag.set("isLocked", isLocked)
        bag.set("lastOpenedAt", lastOpenedAt); bag.set("sortKey", sortKey); bag.set("richText", richText)
        bag.set("pdfOutlineImported", pdfOutlineImported)
    }

    func assign(_ r: SyncRecord, fields: Set<String>) {
        if fields.contains("title") { title = r.string("title") ?? title }
        if fields.contains("kind") { kind = r.string("kind").flatMap(NotebookKind.init(rawValue:)) ?? kind }
        if fields.contains("folderID") { folderID = r.uuid("folderID") }
        if fields.contains("coverSpec") { coverSpec = r.bytes("coverSpec") ?? coverSpec }
        if fields.contains("defaultTemplate") { defaultTemplate = r.bytes("defaultTemplate") ?? defaultTemplate }
        if fields.contains("paperSize") { paperSize = r.string("paperSize") ?? paperSize }
        if fields.contains("orientation") { orientation = r.string("orientation") ?? orientation }
        if fields.contains("paperColor") { paperColor = r.string("paperColor") ?? paperColor }
        if fields.contains("scrollDirection") { scrollDirection = r.string("scrollDirection") ?? scrollDirection }
        if fields.contains("isFavorite") { isFavorite = r.bool("isFavorite") ?? false }
        if fields.contains("isLocked") { isLocked = r.bool("isLocked") ?? false }
        if fields.contains("lastOpenedAt") { lastOpenedAt = r.date("lastOpenedAt") }
        if fields.contains("sortKey") { sortKey = r.string("sortKey") ?? sortKey }
        if fields.contains("richText") { richText = r.bytes("richText") }
        if fields.contains("pdfOutlineImported") { pdfOutlineImported = r.bool("pdfOutlineImported") ?? false }
    }

    static func blank(id: UUID) -> Notebook {
        Notebook(id: id, title: "", kind: .paged, folderID: nil, cover: .default, template: .blank, paperSize: .a4,
                 orientation: .portrait, paperColor: .white, sortKey: "")
    }
}

extension Page: SyncCodable {
    static var domainFields: [String] {
        ["notebookID", "sortKey", "widthPts", "heightPts", "templateOverride", "paperColorOverride", "backgroundAssetID",
         "backgroundPageIndex", "inkData", "strokeIDs", "inkHash", "recognizedText", "ocrInkHash", "isInfinite"]
    }

    func encodeDomain(into bag: inout FieldBag) {
        bag.set("notebookID", notebookID); bag.set("sortKey", sortKey)
        bag.set("widthPts", widthPts); bag.set("heightPts", heightPts)
        bag.set("templateOverride", templateOverride); bag.set("paperColorOverride", paperColorOverride)
        bag.set("backgroundAssetID", backgroundAssetID); bag.set("backgroundPageIndex", backgroundPageIndex)
        bag.set("inkData", inkData); bag.set("strokeIDs", strokeIDs); bag.set("inkHash", inkHash)
        bag.set("recognizedText", recognizedText); bag.set("ocrInkHash", ocrInkHash); bag.set("isInfinite", isInfinite)
    }

    func assign(_ r: SyncRecord, fields: Set<String>) {
        if fields.contains("notebookID") { notebookID = r.uuid("notebookID") ?? notebookID }
        if fields.contains("sortKey") { sortKey = r.string("sortKey") ?? sortKey }
        if fields.contains("widthPts") { widthPts = r.double("widthPts") ?? widthPts }
        if fields.contains("heightPts") { heightPts = r.double("heightPts") ?? heightPts }
        if fields.contains("templateOverride") { templateOverride = r.bytes("templateOverride") }
        if fields.contains("paperColorOverride") { paperColorOverride = r.string("paperColorOverride") }
        if fields.contains("backgroundAssetID") { backgroundAssetID = r.uuid("backgroundAssetID") }
        if fields.contains("backgroundPageIndex") { backgroundPageIndex = r.int("backgroundPageIndex") }
        if fields.contains("inkData") { inkData = r.bytes("inkData") }
        if fields.contains("strokeIDs") { strokeIDs = r.strings("strokeIDs") ?? [] }
        if fields.contains("inkHash") { inkHash = r.string("inkHash") ?? "" }
        if fields.contains("recognizedText") { recognizedText = r.string("recognizedText") ?? "" }
        if fields.contains("ocrInkHash") { ocrInkHash = r.string("ocrInkHash") ?? "" }
        if fields.contains("isInfinite") { isInfinite = r.bool("isInfinite") ?? false }
    }

    static var requiredFields: [String] { ["notebookID"] }

    static func blank(id: UUID) -> Page { Page(id: id, notebookID: UUID(), sortKey: "", size: .zero) }
}
