import XCTest
@testable import LabelCore

final class ProbeOptionsTests: XCTestCase {
    func testAllowedOnly() throws {
        XCTAssertEqual(try ProbeOptions.parse("ProbeSpeed=3 SecretAddress=private"),["ProbeSpeed":"3"])
    }
    func testQuotedKnownValue() throws {
        XCTAssertEqual(try ProbeOptions.parse("ProbeSpeed='3' ProbeWorkflow=\"Letter\""),["ProbeSpeed":"3","ProbeWorkflow":"Letter"])
    }
    func testUnknownQuotedWordsAreNotOptions() throws {
        XCTAssertEqual(try ProbeOptions.parse("Unknown='ProbeSpeed=4'"),[:])
    }
    func testRejectsUnsupportedValue() { XCTAssertThrowsError(try ProbeOptions.parse("ProbeSpeed=5")) }
    func testRejectsDuplicate() { XCTAssertThrowsError(try ProbeOptions.parse("ProbeSpeed=2 ProbeSpeed=3")) }
    func testRejectsMalformedQuotesAndEscape() {
        for text in ["ProbeSpeed='3", "ProbeSpeed=3\\", "ProbeSpeed=3\n", "Unknown='hidden\nvalue'"] { XCTAssertThrowsError(try ProbeOptions.parse(text)) }
    }
    func testRejectsOversized() { XCTAssertThrowsError(try ProbeOptions.parse(String(repeating: "a",count: 16385))) }
    func testEmptyOptions() throws { XCTAssertEqual(try ProbeOptions.parse(""),[:]) }
}
