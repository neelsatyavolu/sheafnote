import Foundation

/// Everything that can go wrong reading or writing a `.sheafnote` archive. Messages are written for the user.
public enum ArchiveError: LocalizedError, Equatable {
    case notAnArchive
    case truncated
    case corrupt(String)
    case missingEntry(String)
    case invalidEntryName(String)
    case duplicateEntry(String)
    case unsupportedCompression(String)
    case newerFormat(Int)
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case .notAnArchive:
            "This file isn't a Sheafnote backup."
        case .truncated:
            "This backup file is incomplete. It may not have finished copying or downloading."
        case .corrupt(let what):
            "This backup is damaged (\(what)). Nothing was imported."
        case .missingEntry(let name):
            "This backup is missing a part it needs (\(name)). Nothing was imported."
        case .invalidEntryName(let name):
            "This backup contains an unsafe file name (\(name)). Nothing was imported."
        case .duplicateEntry(let name):
            "The backup contains \(name) twice."
        case .unsupportedCompression(let name):
            "This backup was repackaged with compression Sheafnote can't read (\(name))."
        case .newerFormat(let version):
            "This backup was made by a newer version of Sheafnote (format \(version)). Update Sheafnote to open it."
        case .ioFailure(let why):
            "Sheafnote couldn't read or write the backup file: \(why)"
        }
    }
}
