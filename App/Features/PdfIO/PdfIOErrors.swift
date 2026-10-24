import Foundation

/// App-level failures of import and export, worded for the person using the app.
enum PdfIOAppError: LocalizedError {
    case unreadableFile(name: String, reason: String)
    case textDocumentsNeedBackupFormat(title: String)
    case noBackupFolder
    case backupFolderUnavailable(reason: String)
    case nothingSelected

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let name, let reason):
            String(localized: "Sheafnote couldn't read \(name): \(reason)", table: "PdfIO")
        case .textDocumentsNeedBackupFormat(let title):
            String(localized: "\(title) is a text document. Export it as a Sheafnote backup instead; PDF and image export is for notebooks with pages.", table: "PdfIO")
        case .noBackupFolder:
            String(localized: "Choose a backup folder first.", table: "PdfIO")
        case .backupFolderUnavailable(let reason):
            String(localized: "Sheafnote can't use the backup folder: \(reason) Choose the folder again in Settings.", table: "PdfIO")
        case .nothingSelected:
            String(localized: "No pages match. Check the page numbers.", table: "PdfIO")
        }
    }
}

enum FileReading {
    /// Reads a file the user picked, through file coordination so a file that lives in iCloud Drive is downloaded first.
    static func data(at url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            var coordinationError: NSError?
            var outcome: Result<Data, Error>?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                outcome = Result { try Data(contentsOf: readable, options: .mappedIfSafe) }
            }
            do {
                if let coordinationError { throw coordinationError }
                guard let outcome else { throw CocoaError(.fileReadUnknown) }
                return try outcome.get()
            } catch {
                throw PdfIOAppError.unreadableFile(name: url.lastPathComponent, reason: error.localizedDescription)
            }
        }.value
    }
}
