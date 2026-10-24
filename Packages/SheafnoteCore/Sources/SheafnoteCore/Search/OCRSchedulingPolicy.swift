import Foundation

/// What the OCR indexer needs to know about a page to decide whether to read its handwriting.
public struct OCRPageState: Sendable, Hashable {
    public var pageID: UUID
    public var notebookID: UUID
    public var inkHash: String
    public var ocrInkHash: String
    public var strokeCount: Int
    public var hasRecognizedText: Bool
    public var modifiedAt: Date

    public init(pageID: UUID, notebookID: UUID, inkHash: String, ocrInkHash: String, strokeCount: Int,
                hasRecognizedText: Bool, modifiedAt: Date) {
        self.pageID = pageID
        self.notebookID = notebookID
        self.inkHash = inkHash
        self.ocrInkHash = ocrInkHash
        self.strokeCount = strokeCount
        self.hasRecognizedText = hasRecognizedText
        self.modifiedAt = modifiedAt
    }
}

public enum OCRAction: Sendable, Equatable { case recognize, clearText, skip }

public struct OCRPlanItem: Sendable, Hashable {
    public var pageID: UUID
    public var notebookID: UUID
    public var inkHash: String
    public var action: OCRAction
}

/// Decides which pages get OCR. A page is read only when its ink changed since the last OCR (`inkHash` differs
/// from `ocrInkHash`), so a page already read on another device is never read again. Pages the user is still
/// writing on are left alone until they settle.
public enum OCRSchedulingPolicy {
    /// Seconds since the last edit before a page is read.
    public static let settleInterval: TimeInterval = 4

    public static func action(for page: OCRPageState) -> OCRAction {
        guard page.inkHash != page.ocrInkHash else { return .skip }
        if page.strokeCount > 0 { return .recognize }
        return page.hasRecognizedText ? .clearText : .skip
    }

    /// Newest-edited pages first, at most `limit`.
    public static func plan(_ pages: [OCRPageState], now: Date, limit: Int) -> [OCRPlanItem] {
        pages
            .filter { now.timeIntervalSince($0.modifiedAt) >= settleInterval }
            .map { ($0, action(for: $0)) }
            .filter { $0.1 != .skip }
            .sorted { $0.0.modifiedAt > $1.0.modifiedAt }
            .prefix(limit)
            .map { OCRPlanItem(pageID: $0.0.pageID, notebookID: $0.0.notebookID, inkHash: $0.0.inkHash, action: $0.1) }
    }
}
