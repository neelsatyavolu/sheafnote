import XCTest
@testable import SheafnoteCore

final class LinkTargetCodecTests: XCTestCase {
    func testWebAddressesAreNormalised() throws {
        XCTAssertEqual(try LinkTargetCodec.parseURL("https://example.com/a").get(), .url(URL(string: "https://example.com/a")!))
        XCTAssertEqual(try LinkTargetCodec.parseURL("  example.com/path ").get(), .url(URL(string: "https://example.com/path")!))
        XCTAssertEqual(try LinkTargetCodec.parseURL("mailto:a@b.co").get(), .url(URL(string: "mailto:a@b.co")!))
    }

    func testRejectsEmptyAndUnsafeSchemes() {
        XCTAssertEqual(LinkTargetCodec.parseURL("   ").failureValue, .empty)
        XCTAssertEqual(LinkTargetCodec.parseURL("javascript:alert(1)").failureValue, .unsupportedScheme("javascript"))
        XCTAssertEqual(LinkTargetCodec.parseURL("file:///etc/passwd").failureValue, .unsupportedScheme("file"))
        XCTAssertEqual(LinkTargetCodec.parseURL("not a url").failureValue, .invalid)
    }

    func testInternalLinksRoundTripThroughText() {
        let id = UUID()
        for target in [LinkTarget.page(id), .notebook(id), .url(URL(string: "https://x.org")!)] {
            XCTAssertEqual(LinkTargetCodec.decode(LinkTargetCodec.encode(target)), target)
        }
        XCTAssertEqual(LinkTargetCodec.encode(.page(id)), "sheafnote://page/\(id.uuidString)")
    }

    func testDecodeRejectsGarbage() {
        XCTAssertNil(LinkTargetCodec.decode("sheafnote://page/not-a-uuid"))
        XCTAssertNil(LinkTargetCodec.decode("sheafnote://folder/\(UUID().uuidString)"))
        XCTAssertNil(LinkTargetCodec.decode(""))
    }

    func testPayloadJSONRoundTrip() throws {
        let payload = LinkPayload(target: .page(UUID()), label: "Chapter 2")
        let data = PayloadCodec.encode(payload)
        XCTAssertEqual(PayloadCodec.decode(LinkPayload.self, from: data), payload)
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let e) = self { return e }
        return nil
    }
}
