import Foundation
import SwiftData

/// Device-local settings for automatic backup to a Files folder. The folder itself is kept as a security-scoped
/// bookmark by the app (not part of this value).
public struct AutoBackupSettings: Codable, Equatable, Sendable {
    public static let keepRange = 1...50
    public static let defaultKeepCount = 7

    public var isEnabled = false
    public var keepCount = defaultKeepCount
    public var lastBackupAt: Date?
    public var lastBackupName: String?
    /// User-facing text of the last failure; cleared by the next success.
    public var lastError: String?

    public init() {}

    public var clampedKeepCount: Int { min(max(keepCount, Self.keepRange.lowerBound), Self.keepRange.upperBound) }
}

/// Pure rules for the automatic backup: when to run, what to name the file and which old backups to remove.
public enum BackupPolicy {
    public static let fileExtension = "sheafnote"
    private static let prefix = "Sheafnote Backup "

    /// Daily, on launch or foreground, and only if something changed since the last backup.
    public static func shouldRun(settings: AutoBackupSettings, latestChange: Date?, now: Date,
                                 calendar: Calendar = .current) -> Bool {
        guard settings.isEnabled, let latestChange else { return false }
        guard let last = settings.lastBackupAt else { return true }
        return !calendar.isDate(last, inSameDayAs: now) && latestChange > last
    }

    /// `Sheafnote Backup 2026-10-23 1530.sheafnote`, with ` (2)`, ` (3)`... when that name is taken.
    public static func fileName(for date: Date, existing: [String], calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(format: "%04d-%02d-%02d %02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        let taken = Set(existing)
        var name = "\(prefix)\(stamp).\(fileExtension)"
        var n = 2
        while taken.contains(name) {
            name = "\(prefix)\(stamp) (\(n)).\(fileExtension)"
            n += 1
        }
        return name
    }

    /// Only files this policy named count as backups; anything else in the folder is never listed for deletion.
    public static func isBackupFileName(_ name: String) -> Bool { sortKey(name) != nil }

    /// The oldest backups beyond `keep`, oldest first.
    public static func filesToDelete(existing: [String], keep: Int) -> [String] {
        let backups = existing.compactMap { name in sortKey(name).map { (name, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        let limit = max(1, keep)
        return backups.count > limit ? Array(backups.prefix(backups.count - limit)) : []
    }

    /// (timestamp, duplicate number) parsed from a backup file name, or nil if it isn't one of ours.
    private static func sortKey(_ name: String) -> String? {
        let suffix = ".\(fileExtension)"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let body = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        let parts = body.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2, isDigits(parts[0], "dddd-dd-dd"), isDigits(parts[1], "dddd") else { return nil }
        var number = 1
        if parts.count == 3 {
            let tail = parts[2]
            guard tail.hasPrefix("("), tail.hasSuffix(")"), let n = Int(tail.dropFirst().dropLast()), n >= 2 else { return nil }
            number = n
        }
        return "\(parts[0]) \(parts[1]) \(String(format: "%06d", number))"
    }

    private static func isDigits(_ text: String, _ pattern: String) -> Bool {
        text.count == pattern.count && zip(text, pattern).allSatisfy { $1 == "d" ? $0.isNumber && $0.isASCII : $0 == $1 }
    }
}

/// Finds the most recent edit anywhere in the library, to decide whether a backup is due.
@MainActor
public enum BackupChangeDetector {
    public static func latestChange(in context: ModelContext) throws -> Date? {
        var latest: Date?
        func consider(_ date: Date?) { if let date, date > (latest ?? .distantPast) { latest = date } }
        consider(try newest(\Folder.modifiedAt, in: context))
        consider(try newest(\Notebook.modifiedAt, in: context))
        consider(try newest(\Page.modifiedAt, in: context))
        consider(try newest(\PageElement.modifiedAt, in: context))
        consider(try newest(\Asset.modifiedAt, in: context))
        return latest
    }

    /// Takes a concrete key path: SwiftData cannot resolve `\T.modifiedAt` formed in generic code in optimized builds.
    private static func newest<T: SyncableRecord>(_ modifiedAt: any KeyPath<T, Date> & Sendable,
                                                  in context: ModelContext) throws -> Date? {
        var descriptor = FetchDescriptor<T>(sortBy: [SortDescriptor(modifiedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.modifiedAt
    }
}
