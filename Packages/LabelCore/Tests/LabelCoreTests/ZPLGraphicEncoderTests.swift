import XCTest
@testable import LabelCore

final class ZPLGraphicEncoderTests: XCTestCase {
    func bitmap(_ bytes: [UInt8] = [0xA5,0x80], width: Int = 9, height: Int = 1) throws -> MonochromeBitmap {
        try MonochromeBitmap(width: width, height: height, bytes: bytes)
    }
    func testFixedGoldenVector() throws {
        let out = try ZPLGraphicEncoder().diagnosticFormat(bitmap())
        XCTAssertEqual(String(decoding: out, as: UTF8.self), "^XA\n^FO0,0^GFA,2,2,2,A580^FS\n^XZ\n")
    }
    func testReferenceBands() throws {
        let bands = try ZPLGraphicEncoder().bands(for: BitmapLayout(width: 813, height: 1219))
        XCTAssertEqual(bands.map(\.rowCount), [321,321,321,256])
        XCTAssertEqual(bands.map(\.y), [0,321,642,963])
        XCTAssertEqual(bands.map(\.byteOffset), [0,32742,65484,98226])
        XCTAssertEqual(bands.map(\.byteCount).reduce(0,+), 124338)
    }
    func testBandExactBoundary() throws {
        XCTAssertEqual(try ZPLGraphicEncoder(maxDecodedBandBytes: 4).bands(for: BitmapLayout(width: 16,height: 4)).map(\.rowCount), [2,2])
    }
    func testRejectsInvalidLimits() {
        for cap in [0,-1,100000] { XCTAssertThrowsError(try ZPLGraphicEncoder(maxDecodedBandBytes: cap)) }
        XCTAssertThrowsError(try ZPLGraphicEncoder(maxOutputBytes: 0))
        XCTAssertThrowsError(try ZPLGraphicEncoder(maxDimensionDots: 32001))
    }
    func testRejectsRowLargerThanCap() {
        XCTAssertThrowsError(try ZPLGraphicEncoder(maxDecodedBandBytes: 1).bands(for: BitmapLayout(width: 9,height: 1)))
    }
    func testRejectsCoordinateLimit() {
        XCTAssertThrowsError(try ZPLGraphicEncoder(maxDimensionDots: 8).bands(for: BitmapLayout(width: 9,height: 1)))
    }
    func testBudgetFailureBeforeSink() throws {
        var calls = 0
        XCTAssertThrowsError(try ZPLGraphicEncoder(maxOutputBytes: 1).writeGraphicFields(bitmap()) { _ in calls += 1 })
        XCTAssertEqual(calls, 0)
    }
    func testExactBudgetBoundary() throws {
        let b = try bitmap(), data = try ZPLGraphicEncoder().diagnosticFormat(b)
        XCTAssertEqual(try ZPLGraphicEncoder(maxOutputBytes: data.count).diagnosticFormat(b), data)
        XCTAssertThrowsError(try ZPLGraphicEncoder(maxOutputBytes: data.count - 1).diagnosticFormat(b))
    }
    func testSinkFailurePropagatedWithoutFurtherCalls() throws {
        enum Stop: Error { case now }
        var calls = 0
        XCTAssertThrowsError(try ZPLGraphicEncoder().writeGraphicFields(bitmap()) { _ in
            calls += 1; throw Stop.now
        })
        XCTAssertEqual(calls, 1)
    }
    func testNoCopiesOrPersistentControlsAndSingleEnvelope() throws {
        let b = try bitmap([255,255,255,255], width: 8, height: 4)
        let out = String(decoding: try ZPLGraphicEncoder(maxDecodedBandBytes: 1).diagnosticFormat(b), as: UTF8.self)
        XCTAssertEqual(out.components(separatedBy: "^XA").count - 1, 1)
        XCTAssertEqual(out.components(separatedBy: "^XZ").count - 1, 1)
        XCTAssertEqual(out.components(separatedBy: "^GF").count - 1, 4)
        for command in ["~", "^PQ", "^JU", "^MM", "^PR", "^LL", "^PW"] { XCTAssertFalse(out.contains(command)) }
    }
    func testChunkBoundIsFinite() throws {
        let layout = try BitmapLayout(width: 813,height: 1219)
        let b = try MonochromeBitmap(width: 813,height: 1219,bytes: [UInt8](repeating: 0,count: layout.byteCount))
        var largest = 0
        try ZPLGraphicEncoder().writeGraphicFields(b) { largest = max(largest,$0.count) }
        XCTAssertLessThanOrEqual(largest, 8192)
    }
    func testBlankTrailingRowsPreserved() throws {
        let out = String(decoding: try ZPLGraphicEncoder(maxDecodedBandBytes: 2).diagnosticFormat(bitmap([128,0,0],width: 1,height: 3)),as: UTF8.self)
        XCTAssertTrue(out.contains("^FO0,2^GFA,1,1,1,00^FS"))
    }
}
