import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import SheafnoteCore

@Suite("Export planning")
struct ExportPlannerTests {
    private let pages = (1...12).map { ExportPageRef(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))!, number: $0, size: CGSize(width: 595, height: 842)) }

    @Test func wholeNotebookKeepsEveryPageInOrder() {
        #expect(ExportPlanner.select(.wholeNotebook, from: pages) == pages)
    }

    @Test func selectedPagesComeOutInNotebookOrder() {
        let chosen: Set<UUID> = [pages[7].id, pages[1].id, pages[4].id]
        #expect(ExportPlanner.select(.pages(chosen), from: pages).map(\.number) == [2, 5, 8])
    }

    @Test func typedNumbersSelectPages() {
        #expect(ExportPlanner.select(.numbers([3, 1, 99]), from: pages).map(\.number) == [1, 3])
        #expect(ExportPlanner.select(.numbers([]), from: pages).isEmpty)
    }

    @Test func rangesParseAndRejectNonsense() {
        #expect(PageRangeParser.parse("1-3, 5 ,8-9", pageCount: 12) == [1, 2, 3, 5, 8, 9])
        #expect(PageRangeParser.parse("4", pageCount: 4) == [4])
        #expect(PageRangeParser.parse("3,1,2,2-3", pageCount: 5) == [1, 2, 3])
        for bad in ["", " ", "0", "5-3", "1-13", "13", "a", "1-", "-2", "1,,2", "1-2-3", "1;"] {
            #expect(PageRangeParser.parse(bad, pageCount: 12) == nil, "\(bad) should be rejected")
        }
    }

    @Test func fileNamesAreSafeAndPadded() {
        #expect(ExportPlanner.fileName(title: "Biology", format: .pdf) == "Biology.pdf")
        #expect(ExportPlanner.fileName(title: "a/b:c?", format: .pdf) == "a-b-c-.pdf")
        #expect(ExportPlanner.fileName(title: "   ", format: .pdf) == "Notebook.pdf")
        #expect(ExportPlanner.fileName(title: "...hidden", format: .pdf) == "hidden.pdf")
        #expect(ExportPlanner.sanitized(String(repeating: "x", count: 300)).count == 80)
        let names = ExportPlanner.imageFileNames(title: "Bio", pages: [pages[0], pages[11]], notebookPageCount: 12, format: .jpeg)
        #expect(names == ["Bio-p01.jpg", "Bio-p12.jpg"])
        let big = ExportPlanner.imageFileNames(title: "Bio", pages: [pages[0]], notebookPageCount: 1200, format: .png)
        #expect(big == ["Bio-p0001.png"])
        #expect(Set(ExportPlanner.imageFileNames(title: "Bio", pages: pages, notebookPageCount: 12, format: .png)).count == 12)
    }

    @Test func imageScaleIsCappedForHugePages() {
        #expect(ExportPlanner.imageScale(requested: 2, pageSize: CGSize(width: 595, height: 842)) == 2)
        #expect(ExportPlanner.imageScale(requested: 4, pageSize: CGSize(width: 5000, height: 2000)) == CGFloat(8192) / 5000)
        #expect(ExportPlanner.imageScale(requested: 2, pageSize: .zero) == 1)
    }
}

@MainActor
@Suite("PDF export writer")
struct PDFExportWriterTests {
    private func temp() -> URL { FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString).pdf") }

    @Test func writesOnePagePerSizeAndCallsDrawInOrder() async throws {
        let url = temp()
        defer { try? FileManager.default.removeItem(at: url) }
        let sizes = [CGSize(width: 300, height: 400), CGSize(width: 500, height: 200)]
        var drawn: [Int] = []
        var fractions: [Double] = []
        try await PDFExportWriter.write(sizes: sizes, to: url, title: "Notes", progress: { fractions.append($0) }) { index, ctx, box in
            drawn.append(index)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
            #expect(box.size == sizes[index])
        }
        #expect(drawn == [0, 1] && fractions == [0.5, 1])
        let doc = try #require(PDFDocument(url: url))
        #expect(doc.pageCount == 2)
        #expect(doc.page(at: 0)?.bounds(for: .mediaBox).size == sizes[0])
        #expect(doc.page(at: 1)?.bounds(for: .mediaBox).size == sizes[1])
        #expect(doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Notes")
    }

    @Test func aFailingPageRemovesThePartialFile() async throws {
        let url = temp()
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await PDFExportWriter.write(sizes: [CGSize(width: 100, height: 100), CGSize(width: 100, height: 100)], to: url, title: nil) { index, _, _ in
                if index == 1 { throw Boom() }
            }
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func noPagesIsAnError() async throws {
        await #expect(throws: ExportError.noPages) {
            try await PDFExportWriter.write(sizes: [], to: temp(), title: nil) { _, _, _ in }
        }
    }

    @Test func cancellationStopsAndCleansUp() async throws {
        let url = temp()
        let task = Task { @MainActor in
            try await PDFExportWriter.write(sizes: Array(repeating: CGSize(width: 100, height: 100), count: 50), to: url, title: nil) { index, _, _ in
                if index == 2 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

@Suite("Image encoder")
struct ImageEncoderTests {
    private func image(alpha: Bool) throws -> CGImage {
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if !alpha { ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }
        return try #require(ctx.makeImage())
    }

    @Test func encodesPNGAndJPEGThatReadBack() throws {
        let png = try ImageEncoder.encode(image(alpha: false), as: .png)
        let jpg = try ImageEncoder.encode(image(alpha: false), as: .jpeg)
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(jpg.starts(with: [0xFF, 0xD8]))
        let source = try #require(CGImageSourceCreateWithData(jpg as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 1)
    }

    @Test func transparentPagesFlattenToWhiteInJPEG() throws {
        let jpg = try ImageEncoder.encode(image(alpha: true), as: .jpeg)
        let source = try #require(CGImageSourceCreateWithData(jpg as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let ctx = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(decoded, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        let bytes = try #require(ctx.data).bindMemory(to: UInt8.self, capacity: 4)
        #expect(bytes[0] > 240 && bytes[1] > 240 && bytes[2] > 240)
    }

    @Test func pdfIsNotAnImageFormat() throws {
        #expect(throws: ExportError.encodeFailed) { try ImageEncoder.encode(image(alpha: false), as: .pdf) }
    }
}
