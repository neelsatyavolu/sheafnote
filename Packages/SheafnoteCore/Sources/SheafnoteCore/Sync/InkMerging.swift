import Foundation

/// The ink of one side of a page: PKDrawing bytes plus the ordered stable ids of its strokes.
public struct InkState: Sendable, Equatable {
    public var data: Data?
    public var strokeIDs: [String]

    public init(data: Data?, strokeIDs: [String]) {
        self.data = data
        self.strokeIDs = strokeIDs
    }
}

/// Merges page ink three ways. The app implements it with PencilKit (`PageInkMerger`): it decodes both drawings,
/// calls `StrokeMerger`, and rebuilds one drawing. Core only needs this seam, so it stays free of PencilKit.
/// Implementations throw when either side cannot be decoded; the caller then keeps both versions.
public protocol InkMerging: Sendable {
    func merge(baseStrokeIDs: [String], ours: InkState, theirs: InkState) throws -> InkState
}

/// Used when no ink engine is available: every ink conflict falls back to "keep both versions".
public struct UnavailableInkMerging: InkMerging {
    public init() {}
    public func merge(baseStrokeIDs: [String], ours: InkState, theirs: InkState) throws -> InkState {
        throw InkMergeError.unavailable
    }
}

public enum InkMergeError: LocalizedError, Equatable {
    case unavailable
    case undecodable(side: String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Ink merging is not available."
        case .undecodable(let side): "The \(side) version of this page's ink could not be read."
        }
    }
}
