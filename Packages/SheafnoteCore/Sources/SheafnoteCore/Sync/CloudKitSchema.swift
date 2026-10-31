import Foundation

/// The CloudKit type of every synced field. CloudKit fixes a field's type the first time it is saved, and production
/// cannot create types or fields at all, so this is the single source for both `CKRecordBridge` (binary fields always go
/// out as their declared type, whatever their size) and `cloudkit/schema.ckdb` (`ckdb()`, imported with
/// `cktool import-schema`, then deployed to production). The schema only grows: never change or remove a field here.
public enum CloudKitSchema {
    public enum FieldType: String, Sendable {
        case string = "STRING", int64 = "INT64", double = "DOUBLE", timestamp = "TIMESTAMP"
        case bytes = "BYTES", asset = "ASSET", stringList = "LIST<STRING>"
    }

    static let common: [String: FieldType] = [
        "formatVersion": .int64, "createdAt": .timestamp, "modifiedAt": .timestamp, "deletedAt": .timestamp,
    ]

    /// Domain fields per record type. Bytes fields hold small JSON; everything that can grow large is an Asset.
    static let domain: [String: [String: FieldType]] = [
        "SNFolder": ["name": .string, "parentID": .string, "sortKey": .string, "isFavorite": .int64, "colorName": .string],
        "SNNotebook": [
            "title": .string, "kind": .string, "folderID": .string, "coverSpec": .asset, "defaultTemplate": .bytes,
            "paperSize": .string, "orientation": .string, "paperColor": .string, "scrollDirection": .string,
            "isFavorite": .int64, "isLocked": .int64, "lastOpenedAt": .timestamp, "sortKey": .string,
            "richText": .asset, "pdfOutlineImported": .int64,
        ],
        "SNPage": [
            "notebookID": .string, "sortKey": .string, "widthPts": .double, "heightPts": .double,
            "templateOverride": .bytes, "paperColorOverride": .string, "backgroundAssetID": .string,
            "backgroundPageIndex": .int64, "inkData": .asset, "strokeIDs": .stringList, "inkHash": .string,
            "recognizedText": .string, "ocrInkHash": .string, "isInfinite": .int64,
        ],
        "SNPageElement": [
            "pageID": .string, "kind": .string, "x": .double, "y": .double, "width": .double, "height": .double,
            "rotation": .double, "zIndex": .int64, "payload": .bytes, "assetID": .string,
        ],
        "SNAsset": ["kind": .string, "data": .asset, "byteCount": .int64, "sha256": .string, "filename": .string, "uti": .string],
        "SNOutlineEntry": [
            "notebookID": .string, "title": .string, "pageID": .string, "pdfPageIndex": .int64, "parentID": .string,
            "sortKey": .string, "source": .string,
        ],
        "SNBookmark": ["notebookID": .string, "pageID": .string, "title": .string],
        "SNAudioRecording": [
            "notebookID": .string, "assetID": .string, "title": .string, "startedAt": .timestamp, "duration": .double,
            "timeline": .asset,
        ],
        "SNFlashcard": [
            "notebookID": .string, "deck": .string, "sourcePageID": .string, "frontImage": .asset, "backImage": .asset,
            "frontText": .string, "backText": .string,
        ],
        "SNStudyState": [
            "flashcardID": .string, "ease": .double, "intervalDays": .int64, "repetitions": .int64, "lapses": .int64,
            "dueAt": .timestamp, "lastReviewedAt": .timestamp,
        ],
        "SNSavedElement": [
            "name": .string, "category": .string, "width": .double, "height": .double, "inkData": .asset,
            "elements": .bytes, "thumbnail": .asset,
        ],
        "SNSetting": ["key": .string, "valueJSON": .bytes],
    ]

    /// All fields (domain and common) per record type.
    public static let recordTypes: [String: [String: FieldType]] = domain.mapValues { $0.merging(common) { field, _ in field } }

    public static func type(of field: String, in recordType: String) -> FieldType? {
        recordTypes[recordType]?[field]
    }

    /// The schema in CloudKit's `.ckdb` language: every record type with the standard system fields, readable and
    /// writable only by the record's creator (private database), plus the built-in `Users` type.
    public static func ckdb() -> String {
        var out = "DEFINE SCHEMA\n"
        for recordType in recordTypes.keys.sorted() {
            let fields = recordTypes[recordType, default: [:]].sorted { $0.key < $1.key }
                .map { "        \"\($0.key)\" \($0.value.rawValue),\n" }.joined()
            out += "\n    RECORD TYPE \(recordType) (\n\(systemFields(recordNameQueryable: true))\(fields)"
                + "        GRANT WRITE TO \"_creator\",\n        GRANT CREATE TO \"_icloud\",\n        GRANT READ TO \"_world\"\n    );\n"
        }
        out += "\n    RECORD TYPE Users (\n\(systemFields(recordNameQueryable: false))        \"roles\" LIST<INT64>,\n"
            + "        GRANT WRITE TO \"_creator\",\n        GRANT READ TO \"_world\"\n    );\n"
        return out
    }

    private static func systemFields(recordNameQueryable: Bool) -> String {
        """
                "___createTime" TIMESTAMP,
                "___createdBy" REFERENCE,
                "___etag" STRING,
                "___modTime" TIMESTAMP,
                "___modifiedBy" REFERENCE,
                "___recordID" REFERENCE\(recordNameQueryable ? " QUERYABLE" : ""),

        """
    }
}
