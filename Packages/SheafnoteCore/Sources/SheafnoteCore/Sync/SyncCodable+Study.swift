import Foundation

extension AudioRecording: SyncCodable {
    static var domainFields: [String] { ["notebookID", "assetID", "title", "startedAt", "duration", "timeline"] }
    static var requiredFields: [String] { ["notebookID", "assetID"] }

    func encodeDomain(into bag: inout FieldBag) {
        bag.set("notebookID", notebookID); bag.set("assetID", assetID); bag.set("title", title)
        bag.set("startedAt", startedAt); bag.set("duration", duration); bag.set("timeline", timeline)
    }

    func assign(_ r: SyncRecord, fields: Set<String>) {
        if fields.contains("notebookID") { notebookID = r.uuid("notebookID") ?? notebookID }
        if fields.contains("assetID") { assetID = r.uuid("assetID") ?? assetID }
        if fields.contains("title") { title = r.string("title") ?? "" }
        if fields.contains("startedAt") { startedAt = r.date("startedAt") ?? startedAt }
        if fields.contains("duration") { duration = r.double("duration") ?? 0 }
        if fields.contains("timeline") { timeline = r.bytes("timeline") ?? Data() }
    }

    static func blank(id: UUID) -> AudioRecording {
        AudioRecording(id: id, notebookID: UUID(), assetID: UUID(), title: "", startedAt: .distantPast, duration: 0)
    }
}

extension Flashcard: SyncCodable {
    static var domainFields: [String] {
        ["notebookID", "deck", "sourcePageID", "frontImage", "backImage", "frontText", "backText"]
    }
    static var requiredFields: [String] { ["notebookID"] }

    func encodeDomain(into bag: inout FieldBag) {
        bag.set("notebookID", notebookID); bag.set("deck", deck); bag.set("sourcePageID", sourcePageID)
        bag.set("frontImage", frontImage); bag.set("backImage", backImage)
        bag.set("frontText", frontText); bag.set("backText", backText)
    }

    func assign(_ r: SyncRecord, fields: Set<String>) {
        if fields.contains("notebookID") { notebookID = r.uuid("notebookID") ?? notebookID }
        if fields.contains("deck") { deck = r.string("deck") ?? "" }
        if fields.contains("sourcePageID") { sourcePageID = r.uuid("sourcePageID") }
        if fields.contains("frontImage") { frontImage = r.bytes("frontImage") ?? Data() }
        if fields.contains("backImage") { backImage = r.bytes("backImage") ?? Data() }
        if fields.contains("frontText") { frontText = r.string("frontText") }
        if fields.contains("backText") { backText = r.string("backText") }
    }

    static func blank(id: UUID) -> Flashcard {
        Flashcard(id: id, notebookID: UUID(), deck: "", frontImage: Data(), backImage: Data())
    }
}

extension StudyState: SyncCodable {
    static var domainFields: [String] {
        ["flashcardID", "ease", "intervalDays", "repetitions", "lapses", "dueAt", "lastReviewedAt"]
    }
    static var requiredFields: [String] { ["flashcardID"] }

    func encodeDomain(into bag: inout FieldBag) {
        bag.set("flashcardID", flashcardID); bag.set("ease", ease); bag.set("intervalDays", intervalDays)
        bag.set("repetitions", repetitions); bag.set("lapses", lapses); bag.set("dueAt", dueAt)
        bag.set("lastReviewedAt", lastReviewedAt)
    }

    func assign(_ r: SyncRecord, fields: Set<String>) {
        if fields.contains("flashcardID") { flashcardID = r.uuid("flashcardID") ?? flashcardID }
        if fields.contains("ease") { ease = r.double("ease") ?? 2.5 }
        if fields.contains("intervalDays") { intervalDays = r.int("intervalDays") ?? 0 }
        if fields.contains("repetitions") { repetitions = r.int("repetitions") ?? 0 }
        if fields.contains("lapses") { lapses = r.int("lapses") ?? 0 }
        if fields.contains("dueAt") { dueAt = r.date("dueAt") ?? dueAt }
        if fields.contains("lastReviewedAt") { lastReviewedAt = r.date("lastReviewedAt") }
    }

    static func blank(id: UUID) -> StudyState { StudyState(id: id, flashcardID: UUID()) }
}

extension SavedElement: SyncCodable {
    static var domainFields: [String] { ["name", "category", "width", "height", "inkData", "elements", "thumbnail"] }

    func encodeDomain(into bag: inout FieldBag) {
        bag.set("name", name); bag.set("category", category); bag.set("width", width); bag.set("height", height)
        bag.set("inkData", inkData); bag.set("elements", elements); bag.set("thumbnail", thumbnail)
    }

    func assign(_ r: SyncRecord, fields: Set<String>) {
        if fields.contains("name") { name = r.string("name") ?? "" }
        if fields.contains("category") { category = r.string("category") ?? "" }
        if fields.contains("width") { width = r.double("width") ?? 0 }
        if fields.contains("height") { height = r.double("height") ?? 0 }
        if fields.contains("inkData") { inkData = r.bytes("inkData") }
        if fields.contains("elements") { elements = r.bytes("elements") ?? Data() }
        if fields.contains("thumbnail") { thumbnail = r.bytes("thumbnail") ?? Data() }
    }

    static func blank(id: UUID) -> SavedElement {
        SavedElement(id: id, name: "", category: "", width: 0, height: 0, inkData: nil, elements: Data(), thumbnail: Data())
    }
}

extension AppSetting: SyncCodable {
    static var domainFields: [String] { ["key", "valueJSON"] }
    static var requiredFields: [String] { ["key"] }

    func encodeDomain(into bag: inout FieldBag) { bag.set("key", key); bag.set("valueJSON", valueJSON) }

    func assign(_ r: SyncRecord, fields: Set<String>) {
        if fields.contains("key") { key = r.string("key") ?? key }
        if fields.contains("valueJSON") { valueJSON = r.bytes("valueJSON") ?? Data() }
    }

    static func blank(id: UUID) -> AppSetting { AppSetting(id: id, key: "", valueJSON: Data()) }
}
