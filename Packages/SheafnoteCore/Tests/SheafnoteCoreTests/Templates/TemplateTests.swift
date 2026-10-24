import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct TemplateTests {
    let a4 = PaperSize.a4.portraitSize

    func layout(_ kind: TemplateKind, _ size: CGSize? = nil) -> TemplateLayout {
        TemplateLayoutBuilder.layout(for: TemplateSpec(kind: kind), size: size ?? a4)
    }

    @Test func blankHasNothing() {
        #expect(layout(.blank).primitives.isEmpty)
    }

    @Test(arguments: [(TemplateKind.ruledNarrow, 18.0), (.ruledCollege, 22.0), (.ruledWide, 28.0)])
    func ruledSpacingAndRange(kind: TemplateKind, spacing: Double) {
        let ys = layout(kind).horizontalLines.map(\.start.y).sorted()
        #expect(ys.first == TemplateMetrics.ruledTop)
        for (a, b) in zip(ys, ys.dropFirst()) { #expect(abs(Double(b - a) - spacing) < 0.001) }
        #expect(ys.last! <= a4.height - TemplateMetrics.ruledBottom)
        #expect(ys.last! + CGFloat(spacing) > a4.height - TemplateMetrics.ruledBottom)
    }

    @Test func narrowHasMoreLinesThanWide() {
        #expect(layout(.ruledNarrow).horizontalLines.count > layout(.ruledCollege).horizontalLines.count)
        #expect(layout(.ruledCollege).horizontalLines.count > layout(.ruledWide).horizontalLines.count)
    }

    @Test func onlyCollegeHasMarginLine() {
        #expect(layout(.ruledCollege).verticalLines.count == 1)
        #expect(layout(.ruledCollege).verticalLines[0].start.x == TemplateMetrics.collegeMarginX)
        #expect(layout(.ruledNarrow).verticalLines.isEmpty)
        #expect(layout(.ruledWide).verticalLines.isEmpty)
    }

    @Test(arguments: [(TemplateKind.gridSmall, 14.0), (.gridMedium, 20.0), (.gridLarge, 28.0)])
    func gridIsCenteredWithSpacing(kind: TemplateKind, spacing: Double) {
        let l = layout(kind)
        let xs = l.verticalLines.map(\.start.x).sorted()
        let n = Int((a4.width / CGFloat(spacing)).rounded(.down))
        #expect(xs.count == n + 1)
        for (a, b) in zip(xs, xs.dropFirst()) { #expect(abs(Double(b - a) - spacing) < 0.001) }
        #expect(abs((xs.first!) - (a4.width - xs.last!)) < 0.001)
        #expect(l.horizontalLines.count == Int((a4.height / CGFloat(spacing)).rounded(.down)) + 1)
    }

    @Test func dottedDotsOnGrid() {
        let l = layout(.dotted)
        let cols = Int((a4.width / TemplateMetrics.dotSpacing).rounded(.down)) + 1
        let rows = Int((a4.height / TemplateMetrics.dotSpacing).rounded(.down)) + 1
        #expect(l.dots.count == cols * rows)
        #expect(l.lines.isEmpty)
    }

    @Test func cornellStructure() {
        let l = layout(.cornell)
        let heavy = l.lines.filter { $0.role == .accent }
        #expect(heavy.count == 3)
        #expect(l.verticalLines.count == 1)
        let cueX = l.verticalLines[0].start.x
        #expect(abs(cueX - a4.width * TemplateMetrics.cornellCueFraction) < 0.001)
        let summaryY = a4.height * TemplateMetrics.cornellSummaryFraction
        #expect(l.horizontalLines.allSatisfy { $0.start.y <= summaryY })
    }

    @Test func staffGroupsOfFiveLines() {
        let l = layout(.musicStaff)
        let staffLines = l.horizontalLines
        #expect(staffLines.count % 5 == 0)
        #expect(staffLines.count >= 10 * 5 - 5)
        let ys = staffLines.map(\.start.y).sorted()
        #expect(ys[1] - ys[0] == TemplateMetrics.staffLineGap)
        #expect(ys[5] - ys[0] == TemplateMetrics.staffPitch)
        #expect(ys.last! <= a4.height - TemplateMetrics.staffBottom)
        #expect(l.verticalLines.count == staffLines.count / 5)
    }

    @Test func dailyPlanner() {
        let l = layout(.plannerDaily)
        let hourLabels = l.labels.filter { Int($0.text) != nil }
        #expect(hourLabels.count == TemplateMetrics.plannerHourCount)
        #expect(l.labels.contains { $0.text == "Priorities" })
        #expect(l.boxes.count == 3)
    }

    @Test func weeklyPlannerHasSevenDaysAndNotes() {
        let l = layout(.plannerWeekly)
        #expect(l.boxes.count == 8)
        for d in TemplateStrings.english.weekdays { #expect(l.labels.contains { $0.text == d }) }
        for b in l.boxes { #expect(b.rect.maxX <= a4.width && b.rect.maxY <= a4.height) }
    }

    @Test func monthlyPlannerHas42Cells() {
        let l = layout(.plannerMonthly)
        #expect(l.boxes.count == 42)
        #expect(l.labels.filter { TemplateStrings.english.weekdays.contains($0.text) }.count == 7)
    }

    @Test func todoPlannerRows() {
        let l = layout(.plannerTodo)
        #expect(l.boxes.count > 15)
        #expect(l.boxes.allSatisfy { $0.rect.width == TemplateMetrics.todoBox })
    }

    @Test func localizedStringsAreUsed() {
        var s = TemplateStrings.english
        s.weekdays = ["L", "M", "X", "J", "V", "S", "D"]
        let l = TemplateLayoutBuilder.layout(for: TemplateSpec(kind: .plannerWeekly), size: a4, strings: s)
        #expect(l.labels.contains { $0.text == "X" })
    }

    @Test(arguments: TemplateKind.allCases, PaperSize.allCases)
    func everyCombinationStaysInsidePage(kind: TemplateKind, paper: PaperSize) {
        for orientation in PageOrientation.allCases {
            let size = paper.size(orientation: orientation)
            let l = TemplateLayoutBuilder.layout(for: TemplateSpec(kind: kind), size: size)
            let page = CGRect(origin: .zero, size: size).insetBy(dx: -0.01, dy: -0.01)
            for line in l.lines { #expect(page.contains(line.start) && page.contains(line.end)) }
            for box in l.boxes { #expect(page.contains(box.rect)) }
            for dot in l.dots { #expect(page.contains(dot.center)) }
        }
    }

    @Test func landscapeUsesWidth() {
        let size = PaperSize.a4.size(orientation: .landscape)
        let l = TemplateLayoutBuilder.layout(for: TemplateSpec(kind: .ruledCollege), size: size)
        #expect(l.horizontalLines.count < layout(.ruledCollege).horizontalLines.count)
        #expect(l.horizontalLines.allSatisfy { $0.end.x == size.width - TemplateMetrics.sideInset })
    }

    @Test(arguments: TemplateKind.allCases, PaperColor.allCases)
    func everyTemplateRendersDistinctFromBlank(kind: TemplateKind, color: PaperColor) throws {
        let size = CGSize(width: 300, height: 420)
        let img = try #require(TemplateRenderer.renderImage(TemplateSpec(kind: kind), size: size, paper: color))
        let blank = try #require(TemplateRenderer.renderImage(.blank, size: size, paper: color))
        #expect(img.width == 300 && img.height == 420)
        if kind != .blank { #expect(ImageHash.pixels(img) != ImageHash.pixels(blank)) }
    }

    @Test func paperColorsAreDistinct() throws {
        let hashes = try PaperColor.allCases.map {
            ImageHash.pixels(try #require(TemplateRenderer.renderImage(.blank, size: CGSize(width: 10, height: 10), paper: $0)))
        }
        #expect(Set(hashes).count == 3)
    }

    @Test func specCodableRoundTrip() throws {
        let spec = TemplateSpec(kind: .cornell)
        let data = JSONCoding.encode(spec)
        #expect(JSONCoding.decode(TemplateSpec.self, from: data) == spec)
    }

    @Test func categoriesCoverAllKinds() {
        let all = TemplateCategory.allCases.flatMap(\.kinds)
        #expect(Set(all) == Set(TemplateKind.allCases))
    }

    @Test func paperSizes() {
        #expect(PaperSize.a4.size(orientation: .landscape) == CGSize(width: 842, height: 595))
        #expect(PaperSize.square.size(orientation: .landscape) == PaperSize.square.portraitSize)
        #expect(PaperSize.letter.portraitSize == CGSize(width: 612, height: 792))
    }

    @Test func colorHexParsing() {
        #expect(RGBAColor(hex: "#FF0000")?.r == 1)
        #expect(RGBAColor(hex: "00FF0080")?.a ?? 0 > 0.49)
        #expect(RGBAColor(hex: "nope") == nil)
        #expect(RGBAColor(hex: "#12345") == nil)
    }
}
