import Foundation
import Testing
@testable import SheafnoteCore

@MainActor
@Suite("Automatic backup policy")
struct BackupPolicyTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func settings(enabled: Bool = true, last: Date? = nil) -> AutoBackupSettings {
        var s = AutoBackupSettings()
        s.isEnabled = enabled
        s.lastBackupAt = last
        return s
    }

    @Test func neverRunsWhenOffOrWhenThereIsNothingToBackUp() {
        let now = date("2026-10-23T12:00:00Z")
        #expect(!BackupPolicy.shouldRun(settings: settings(enabled: false), latestChange: now, now: now, calendar: utc))
        #expect(!BackupPolicy.shouldRun(settings: settings(), latestChange: nil, now: now, calendar: utc))
    }

    @Test func runsTheFirstTimeThereIsContent() {
        let now = date("2026-10-23T12:00:00Z")
        #expect(BackupPolicy.shouldRun(settings: settings(), latestChange: date("2026-10-01T00:00:00Z"), now: now, calendar: utc))
    }

    @Test func runsAtMostOncePerDayAndOnlyIfChanged() {
        let last = date("2026-10-22T09:00:00Z")
        let s = settings(last: last)
        // Same day as the last backup: never again.
        #expect(!BackupPolicy.shouldRun(settings: s, latestChange: date("2026-10-22T10:00:00Z"),
                                        now: date("2026-10-22T23:00:00Z"), calendar: utc))
        // Next day, nothing changed since: skip.
        #expect(!BackupPolicy.shouldRun(settings: s, latestChange: date("2026-10-22T08:00:00Z"),
                                        now: date("2026-10-23T08:00:00Z"), calendar: utc))
        // Next day, changed after the last backup: run.
        #expect(BackupPolicy.shouldRun(settings: s, latestChange: date("2026-10-22T10:00:00Z"),
                                       now: date("2026-10-23T08:00:00Z"), calendar: utc))
    }

    @Test func fileNamesSortByTimeAndAvoidCollisions() {
        let when = date("2026-10-23T15:30:00Z")
        let first = BackupPolicy.fileName(for: when, existing: [], calendar: utc)
        #expect(first == "Sheafnote Backup 2026-10-23 1530.sheafnote")
        let second = BackupPolicy.fileName(for: when, existing: [first], calendar: utc)
        #expect(second == "Sheafnote Backup 2026-10-23 1530 (2).sheafnote")
        #expect(BackupPolicy.fileName(for: when, existing: [first, second], calendar: utc).hasSuffix("(3).sheafnote"))
    }

    @Test func retentionDeletesOnlyOurOldestBackups() {
        let names = [
            "Sheafnote Backup 2026-10-20 0900.sheafnote",
            "Sheafnote Backup 2026-10-21 0900.sheafnote",
            "Sheafnote Backup 2026-10-22 0900 (2).sheafnote",
            "Sheafnote Backup 2026-10-22 0900.sheafnote",
            "Sheafnote Backup 2026-10-23 0900.sheafnote",
            "My Thesis.sheafnote",
            "Sheafnote Backup notes.txt",
            "Sheafnote Backup 2026-10-19 0900.sheafnote.icloud",
        ]
        let doomed = BackupPolicy.filesToDelete(existing: names, keep: 3)
        #expect(doomed == ["Sheafnote Backup 2026-10-20 0900.sheafnote", "Sheafnote Backup 2026-10-21 0900.sheafnote"])
        #expect(BackupPolicy.filesToDelete(existing: names, keep: 10).isEmpty)
        #expect(BackupPolicy.filesToDelete(existing: names, keep: 0).count == 4, "keep is at least 1")
    }

    @Test func recognizesOnlyOurFileNames() {
        #expect(BackupPolicy.isBackupFileName("Sheafnote Backup 2026-10-23 1530.sheafnote"))
        #expect(BackupPolicy.isBackupFileName("Sheafnote Backup 2026-10-23 1530 (4).sheafnote"))
        #expect(!BackupPolicy.isBackupFileName("Sheafnote Backup 2026-10-23.sheafnote"))
        #expect(!BackupPolicy.isBackupFileName("Sheafnote Backup 2026-10-23 1530 (1).sheafnote"))
        #expect(!BackupPolicy.isBackupFileName("Sheafnote Backup 2026-1x-23 1530.sheafnote"))
        #expect(!BackupPolicy.isBackupFileName("Biology.sheafnote"))
    }

    @Test func keepCountIsClamped() {
        var s = AutoBackupSettings()
        s.keepCount = 0
        #expect(s.clampedKeepCount == 1)
        s.keepCount = 500
        #expect(s.clampedKeepCount == 50)
    }

    @Test func latestChangeFollowsTheNewestEdit() throws {
        let fx = try StoreFixture()
        #expect(try BackupChangeDetector.latestChange(in: fx.context) == nil)
        let early = Date(timeIntervalSince1970: 1_700_000_000), late = early.addingTimeInterval(5_000)
        try fx.notebook("A", now: early)
        #expect(try BackupChangeDetector.latestChange(in: fx.context) == early)
        let nb = try fx.notebook("B", now: late)
        #expect(try BackupChangeDetector.latestChange(in: fx.context) == late)
        _ = nb
    }
}
