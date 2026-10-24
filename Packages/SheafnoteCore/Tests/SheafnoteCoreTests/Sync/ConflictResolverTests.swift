import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct ConflictResolverTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    private func server(_ type: String = "SNFolder", modified: Date, deleted: Date? = nil) -> SyncRecord {
        var fields: [String: SyncValue] = [CommonField.modifiedAt: .date(modified)]
        if let deleted { fields[CommonField.deletedAt] = .date(deleted) }
        return SyncRecord(key: RecordKey(recordType: type, id: UUID()), fields: fields)
    }
    private func resolve(_ type: String = "SNFolder", dirty: Set<String>, modified: Date, deleted: Date? = nil,
                         server: SyncRecord) -> ConflictResolution {
        ConflictResolver.resolve(recordType: type, domainFields: ["name", "sortKey", "isFavorite"],
                                 local: LocalRowState(dirtyFields: dirty, modifiedAt: modified, deletedAt: deleted), server: server)
    }

    @Test func dirtyFieldKeepsOursOthersTakeServers() {
        let r = resolve(dirty: ["name"], modified: at(5), server: server(modified: at(9)))
        #expect(r.fieldsFromServer == ["sortKey", "isFavorite"])
        #expect(r.remainingDirtyFields == ["name"])
        #expect(r.modifiedAt == at(9))
    }

    @Test func differentFieldsChangedOnBothSidesAllSurvive() {
        // Device A renamed (dirty name), device B favorited (server isFavorite); the merge keeps both.
        let r = resolve(dirty: ["name"], modified: at(5), server: server(modified: at(6)))
        #expect(r.fieldsFromServer.contains("isFavorite") && !r.fieldsFromServer.contains("name"))
    }

    @Test func serverDeleteBeatsLocalEdit() {
        let r = resolve(dirty: ["name"], modified: at(10), server: server(modified: at(5), deleted: at(5)))
        #expect(r.deletedAt == at(5))
        #expect(r.remainingDirtyFields == ["name"])
    }

    @Test func localDeleteBeatsServerEdit() {
        let r = resolve(dirty: ["deletedAt"], modified: at(5), deleted: at(5), server: server(modified: at(20)))
        #expect(r.deletedAt == at(5))
        #expect(r.remainingDirtyFields.contains("deletedAt"))
    }

    @Test func syncedLocalDeleteIsUndoneByAServerRestore() {
        let r = resolve(dirty: ["name"], modified: at(5), deleted: at(1), server: server(modified: at(30)))
        #expect(r.deletedAt == nil)
    }

    @Test func restoreAfterTheServerDeleteWins() {
        let r = resolve(dirty: ["deletedAt"], modified: at(20), server: server(modified: at(5), deleted: at(5)))
        #expect(r.deletedAt == nil)
        #expect(r.remainingDirtyFields.contains("deletedAt"))
    }

    @Test func restoreBeforeTheServerDeleteLoses() {
        let r = resolve(dirty: ["deletedAt"], modified: at(3), server: server(modified: at(9), deleted: at(9)))
        #expect(r.deletedAt == at(9))
        #expect(!r.remainingDirtyFields.contains("deletedAt"))
    }

    @Test func deletedOnBothSidesKeepsTheLaterTombstone() {
        let r = resolve(dirty: ["deletedAt"], modified: at(5), deleted: at(3), server: server(modified: at(9), deleted: at(8)))
        #expect(r.deletedAt == at(8))
    }

    @Test func identicalEditsLeaveNothingToResend() {
        let r = resolve(dirty: [], modified: at(5), server: server(modified: at(5)))
        #expect(r.remainingDirtyFields.isEmpty)
        #expect(r.fieldsFromServer == ["name", "sortKey", "isFavorite"])
    }

    @Test func elementsAreLastWriterWins() {
        let newer = resolve("SNPageElement", dirty: ["x"], modified: at(5), server: server("SNPageElement", modified: at(9)))
        #expect(newer.fieldsFromServer == ["name", "sortKey", "isFavorite"] && newer.remainingDirtyFields.isEmpty)
        let older = resolve("SNPageElement", dirty: ["name"], modified: at(9), server: server("SNPageElement", modified: at(5)))
        #expect(older.fieldsFromServer.isEmpty && older.remainingDirtyFields == ["name"])
    }

    @Test func specialFieldsAreLeftToTheirOwnRule() {
        let r = ConflictResolver.resolve(recordType: "SNPage", domainFields: ["sortKey", "inkData"], excluding: ["inkData"],
                                         local: LocalRowState(dirtyFields: ["inkData"], modifiedAt: at(1), deletedAt: nil),
                                         server: server("SNPage", modified: at(2)))
        #expect(r.fieldsFromServer == ["sortKey"] && r.remainingDirtyFields == ["inkData"])
    }
}
