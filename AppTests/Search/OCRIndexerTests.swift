import Foundation
import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct OCRIndexerTests {
    @Test func readsInkAndStoresTextOnThePage() async throws {
        let f = try SearchFixture()
        let nb = try f.notebook("Lecture")
        let page = try #require(try f.pages(of: nb).first)
        try f.writeInk(on: page)

        let indexer = OCRIndexer(services: f.services)
        indexer.start(force: true)
        await indexer.waitUntilIdle()

        #expect(page.recognizedText == "recognized words")
        #expect(page.ocrInkHash == page.inkHash)
        #expect(f.recognizer.calls == 1)
        #expect(page.dirtyFields.contains("recognizedText"))
    }

    @Test func doesNotReadAnUnchangedPageAgain() async throws {
        let f = try SearchFixture()
        let nb = try f.notebook("Lecture")
        let page = try #require(try f.pages(of: nb).first)
        try f.writeInk(on: page)
        let indexer = OCRIndexer(services: f.services)
        indexer.start(force: true)
        await indexer.waitUntilIdle()
        indexer.start(force: true)
        await indexer.waitUntilIdle()
        #expect(f.recognizer.calls == 1)

        try f.writeInk(on: page, byte: 2)
        indexer.start(force: true)
        await indexer.waitUntilIdle()
        #expect(f.recognizer.calls == 2)
    }

    @Test func skipsPagesAnotherDeviceAlreadyRead() async throws {
        let f = try SearchFixture()
        let nb = try f.notebook("Synced")
        let page = try #require(try f.pages(of: nb).first)
        try f.writeInk(on: page)
        page.recognizedText = "from the other device"
        page.ocrInkHash = page.inkHash
        try f.services.context.save()

        let indexer = OCRIndexer(services: f.services)
        indexer.start(force: true)
        await indexer.waitUntilIdle()
        #expect(f.recognizer.calls == 0)
        #expect(page.recognizedText == "from the other device")
    }

    @Test func leavesPagesStillBeingWrittenOn() async throws {
        let f = try SearchFixture()
        let nb = try f.notebook("Busy")
        let page = try #require(try f.pages(of: nb).first)
        try f.services.pages.saveInk(pageID: page.id, drawingData: Data([1]), strokeIDs: [StrokeID(rawValue: "a")])
        let indexer = OCRIndexer(services: f.services)
        indexer.start()
        await indexer.waitUntilIdle()
        #expect(f.recognizer.calls == 0)
        #expect(indexer.countPending() == 1)
    }

    @Test func aFailingPageIsReportedAndNotRetriedForever() async throws {
        let f = try SearchFixture()
        f.recognizer.failure = SearchTestError()
        let nb = try f.notebook("Broken")
        let page = try #require(try f.pages(of: nb).first)
        try f.writeInk(on: page)
        let indexer = OCRIndexer(services: f.services)
        indexer.start(force: true)
        await indexer.waitUntilIdle()
        #expect(indexer.failedCount == 1)
        #expect(f.recognizer.calls == 1)
        #expect(page.recognizedText.isEmpty)

        indexer.resetFailures()
        f.recognizer.failure = nil
        indexer.start(force: true)
        await indexer.waitUntilIdle()
        #expect(page.recognizedText == "recognized words")
    }

    @Test func clearedPageLosesItsStaleText() async throws {
        let f = try SearchFixture()
        let nb = try f.notebook("Erased")
        let page = try #require(try f.pages(of: nb).first)
        try f.writeInk(on: page)
        let indexer = OCRIndexer(services: f.services)
        indexer.start(force: true)
        await indexer.waitUntilIdle()

        try f.services.pages.saveInk(pageID: page.id, drawingData: Data([9]), strokeIDs: [])
        page.modifiedAt = Date(timeIntervalSinceNow: -120)
        indexer.start(force: true)
        await indexer.waitUntilIdle()
        #expect(page.recognizedText.isEmpty)
        #expect(f.recognizer.calls == 1)
    }

    @Test func lockedNotebooksAreNeverRead() async throws {
        let f = try SearchFixture()
        let nb = try f.notebook("Private")
        nb.isLocked = true
        let page = try #require(try f.pages(of: nb).first)
        try f.writeInk(on: page)
        let indexer = OCRIndexer(services: f.services)
        indexer.start(force: true)
        await indexer.waitUntilIdle()
        #expect(f.recognizer.calls == 0)
    }
}
