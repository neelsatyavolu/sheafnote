import Foundation
import Observation
import OSLog
import SheafnoteCore

/// Automatic backup of the whole library to a Files folder the user chose. The folder is remembered as a
/// security-scoped bookmark. One backup per day at most, only when something changed, and only files this feature
/// named itself (`BackupPolicy`) are ever removed when trimming old backups.
@MainActor @Observable
final class AutoBackupController {
    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "backup")
    private static let settingsKey = "backup.auto"
    private static let bookmarkKey = "backup.folderBookmark"
    private static let folderNameKey = "backup.folderName"

    let services: AppServices
    private(set) var settings: AutoBackupSettings
    private(set) var folderName: String?
    private(set) var isRunning = false

    init(services: AppServices) {
        self.services = services
        self.settings = services.settings.local(Self.settingsKey, as: AutoBackupSettings.self) ?? AutoBackupSettings()
        self.folderName = services.settings.local(Self.folderNameKey, as: String.self)
    }

    var hasFolder: Bool { services.settings.local(Self.bookmarkKey, as: Data.self) != nil }

    // MARK: Settings

    func setEnabled(_ on: Bool) { update { $0.isEnabled = on && hasFolder } }
    func setKeepCount(_ n: Int) { update { $0.keepCount = min(max(n, AutoBackupSettings.keepRange.lowerBound), AutoBackupSettings.keepRange.upperBound) } }

    /// `url` comes from the folder picker and is already accessible.
    func chooseFolder(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bookmark: Data
        do { bookmark = try url.bookmarkData() } catch {
            throw PdfIOAppError.backupFolderUnavailable(reason: error.localizedDescription)
        }
        services.settings.setLocal(bookmark, for: Self.bookmarkKey)
        services.settings.setLocal(url.lastPathComponent, for: Self.folderNameKey)
        folderName = url.lastPathComponent
        update { $0.lastError = nil }
    }

    private func update(_ change: (inout AutoBackupSettings) -> Void) {
        var next = settings
        change(&next)
        settings = next
        services.settings.setLocal(next, for: Self.settingsKey)
    }

    // MARK: Running

    /// Called on launch and when the app returns to the foreground.
    func runIfDue(now: Date = .now) async {
        guard settings.isEnabled, !isRunning else { return }
        do {
            let latest = try BackupChangeDetector.latestChange(in: services.context)
            guard BackupPolicy.shouldRun(settings: settings, latestChange: latest, now: now) else { return }
        } catch {
            record(error)
            return
        }
        await backUpNow(now: now)
    }

    /// Writes one backup file now. Failures are recorded for the settings screen, never swallowed.
    func backUpNow(now: Date = .now) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let name = try await writeBackup(now: now)
            update { $0.lastBackupAt = now; $0.lastBackupName = name; $0.lastError = nil }
            Self.log.info("Backup written: \(name, privacy: .public)")
        } catch {
            record(error)
        }
    }

    private func record(_ error: Error) {
        Self.log.error("Backup failed: \(error.localizedDescription, privacy: .public)")
        update { $0.lastError = error.localizedDescription }
    }

    private func writeBackup(now: Date) async throws -> String {
        let folder = try resolveFolder()
        guard folder.startAccessingSecurityScopedResource() else {
            throw PdfIOAppError.backupFolderUnavailable(reason: String(localized: "Access was denied.", table: "PdfIO"))
        }
        defer { folder.stopAccessingSecurityScopedResource() }
        let existing = try listNames(in: folder)
        let name = BackupPolicy.fileName(for: now, existing: existing)
        let temp = FileManager.default.temporaryDirectory.appending(path: "\(ExportFolder.prefix)\(UUID().uuidString).\(BackupPolicy.fileExtension)")
        defer { try? FileManager.default.removeItem(at: temp) }   // our own temp file; a leftover is swept at launch
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
        try await ArchiveExporter(context: services.context, appVersion: version).export(.library, to: temp, now: now)
        do {
            try FileManager.default.copyItem(at: temp, to: folder.appending(path: name))
        } catch {
            throw PdfIOAppError.backupFolderUnavailable(reason: error.localizedDescription)
        }
        trimOldBackups(in: folder, names: existing + [name])
        return name
    }

    private func resolveFolder() throws -> URL {
        guard let data = services.settings.local(Self.bookmarkKey, as: Data.self) else { throw PdfIOAppError.noBackupFolder }
        var stale = false
        let url: URL
        do { url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) } catch {
            throw PdfIOAppError.backupFolderUnavailable(reason: error.localizedDescription)
        }
        if stale {
            do { try refreshBookmark(for: url) } catch {
                Self.log.error("Could not refresh the backup folder bookmark: \(error.localizedDescription, privacy: .public)")
            }
        }
        return url
    }

    private func refreshBookmark(for url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        services.settings.setLocal(try url.bookmarkData(), for: Self.bookmarkKey)
    }

    private func listNames(in folder: URL) throws -> [String] {
        do { return try FileManager.default.contentsOfDirectory(atPath: folder.path) } catch {
            throw PdfIOAppError.backupFolderUnavailable(reason: error.localizedDescription)
        }
    }

    /// Removes the oldest backups this feature made, beyond the keep count. A file that can't be removed is logged
    /// and left; it never fails the backup that was just written.
    private func trimOldBackups(in folder: URL, names: [String]) {
        for old in BackupPolicy.filesToDelete(existing: names, keep: settings.clampedKeepCount) {
            do { try FileManager.default.removeItem(at: folder.appending(path: old)) } catch {
                Self.log.error("Could not remove old backup \(old, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
