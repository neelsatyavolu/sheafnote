import Foundation

public struct StrokeEntry: Hashable, Sendable {
    public var id: StrokeID
    public var creationDate: Date

    public init(id: StrokeID, creationDate: Date) {
        self.id = id
        self.creationDate = creationDate
    }
}

public enum MergeSide: Sendable { case ours, theirs }

public struct MergeResult: Sendable {
    /// Strokes to keep, in drawing order, with the side whose copy of the stroke should be used.
    public var ordered: [(id: StrokeID, from: MergeSide)]
    /// Kept strokes that exist only on the server side.
    public var addedFromTheirs: Int
    /// Strokes we had that the server side deleted.
    public var removedByTheirs: Int
}

/// Three-way merge of stroke identity lists. Pure, no PencilKit.
public enum StrokeMerger {
    /// base = last server version we synced, ours = local now, theirs = server now.
    /// keep = (ours ∪ theirs) minus (base − ours) minus (base − theirs); sorted by creationDate then id.
    /// A transformed or recolored stroke has a new id, so an edit is "delete old + add new" and survives the merge.
    public static func merge(base: [StrokeEntry], ours: [StrokeEntry], theirs: [StrokeEntry]) -> MergeResult {
        let baseIDs = Set(base.map(\.id))
        let ourIDs = Set(ours.map(\.id))
        let theirIDs = Set(theirs.map(\.id))
        let deleted = baseIDs.subtracting(ourIDs).union(baseIDs.subtracting(theirIDs))

        var chosen: [StrokeID: (entry: StrokeEntry, side: MergeSide)] = [:]
        for entry in theirs where !deleted.contains(entry.id) { chosen[entry.id] = (entry, .theirs) }
        for entry in ours where !deleted.contains(entry.id) { chosen[entry.id] = (entry, .ours) }

        let sorted = chosen.values.sorted {
            $0.entry.creationDate != $1.entry.creationDate
                ? $0.entry.creationDate < $1.entry.creationDate
                : $0.entry.id < $1.entry.id
        }
        let addedFromTheirs = sorted.filter { !ourIDs.contains($0.entry.id) }.count
        let removedByTheirs = baseIDs.subtracting(theirIDs).intersection(ourIDs).count
        return MergeResult(ordered: sorted.map { ($0.entry.id, $0.side) },
                           addedFromTheirs: addedFromTheirs, removedByTheirs: removedByTheirs)
    }
}
