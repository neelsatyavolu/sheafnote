import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

@Suite("Study tape")
struct StudyTapeTests {
    private let page = UUID()

    private func tape(revealed: Bool, color: String = "#FF0000") -> ElementValue {
        ElementValue(pageID: page, kind: .tape, frame: CGRect(x: 0, y: 0, width: 100, height: 20),
                     payload: PayloadCodec.encode(TapePayload(colorHex: color, isRevealed: revealed)))
    }

    private func revealed(_ e: ElementValue) -> Bool? {
        PayloadCodec.decode(TapePayload.self, from: e.payload)?.isRevealed
    }

    @Test func toggleFlipsAndKeepsOtherFields() {
        let p = TapePayload(colorHex: "#123456", isRevealed: false, style: .washi)
        let t = StudyTape.toggled(p)
        #expect(t.isRevealed)
        #expect(t.colorHex == "#123456" && t.style == .washi)
        #expect(StudyTape.toggled(t) == p)
    }

    @Test func coveringHonorsForceHide() {
        let shown = TapePayload(colorHex: "#000000", isRevealed: true)
        #expect(!StudyTape.isCovering(shown, forceHide: false))
        #expect(StudyTape.isCovering(shown, forceHide: true))
        #expect(StudyTape.isCovering(TapePayload(colorHex: "#000000", isRevealed: false), forceHide: false))
    }

    @Test func settingRevealedReturnsOnlyChangedTapes() {
        let a = tape(revealed: false), b = tape(revealed: true)
        let image = ElementValue(pageID: page, kind: .image, frame: .zero)
        let changed = StudyTape.settingRevealed(true, in: [a, b, image])
        #expect(changed.map(\.id) == [a.id])
        #expect(revealed(changed[0]) == true)
        #expect(StudyTape.settingRevealed(false, in: [a]).isEmpty)
    }

    @Test func settingRevealedSkipsBrokenPayloads() {
        let broken = ElementValue(pageID: page, kind: .tape, frame: .zero, payload: Data("nope".utf8))
        #expect(StudyTape.settingRevealed(true, in: [broken]).isEmpty)
    }

    @Test func allCoveringDecidesNextBulkAction() {
        #expect(StudyTape.allCovering(in: [tape(revealed: false), tape(revealed: false)]))
        #expect(!StudyTape.allCovering(in: [tape(revealed: false), tape(revealed: true)]))
        #expect(!StudyTape.allCovering(in: []))
    }

    @Test func dragMakesNormalizedRect() throws {
        let r = try #require(StudyTape.rect(from: CGPoint(x: 200, y: 120), to: CGPoint(x: 80, y: 90), pageSize: CGSize(width: 600, height: 800)))
        #expect(r == CGRect(x: 80, y: 90, width: 120, height: 30))
    }

    @Test func thinDragGetsMinimumThickness() throws {
        let r = try #require(StudyTape.rect(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 250, y: 102), pageSize: CGSize(width: 600, height: 800)))
        #expect(r.height == StudyTape.minimumThickness)
        #expect(abs(r.midY - 101) < 0.001)
        #expect(r.width == 200)
    }

    @Test func tapMakesNoTape() {
        #expect(StudyTape.rect(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 9, y: 8), pageSize: CGSize(width: 600, height: 800)) == nil)
    }

    @Test func rectIsClampedToPage() throws {
        let r = try #require(StudyTape.rect(from: CGPoint(x: 500, y: 700), to: CGPoint(x: 900, y: 760), pageSize: CGSize(width: 600, height: 800)))
        #expect(r.maxX == 600)
    }

    @Test func dragCompletelyOffPageMakesNothing() {
        #expect(StudyTape.rect(from: CGPoint(x: 700, y: 10), to: CGPoint(x: 900, y: 50), pageSize: CGSize(width: 600, height: 800)) == nil)
    }

    @Test func newElementStartsCovering() throws {
        let swatch = StudyTape.swatches[0]
        let e = StudyTape.element(pageID: page, rect: CGRect(x: 1, y: 2, width: 50, height: 20), swatch: swatch, zIndex: 4)
        #expect(e.kind == .tape && e.zIndex == 4)
        let payload = try #require(PayloadCodec.decode(TapePayload.self, from: e.payload))
        #expect(!payload.isRevealed && payload.colorHex == swatch.hex && payload.style == swatch.style)
    }

    @Test func swatchesAreValid() {
        #expect(Set(StudyTape.swatches.map(\.id)).count == StudyTape.swatches.count)
        #expect(StudyTape.swatches.allSatisfy { RGBAColor(hex: $0.hex) != nil })
    }
}
