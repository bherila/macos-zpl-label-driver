import XCTest
@testable import LabelCore

final class ZPLASCIICompressionTests: XCTestCase {
    func testLiteralBoundaryAndAdditiveCountTokensRemainByteExact() {
        let cases: [(Int, String)] = [(1, "AA"), (2, "JA"), (9, "XA"), (10, "gA"),
            (19, "gXA"), (20, "hA"), (199, "yXA"), (200, "zA"),
            (201, "zHA"), (400, "zzA"), (801, "zzzzHA")]
        for (bytes, expected) in cases {
            XCTAssertEqual(String(decoding: ZPLASCIICompression.row(
                [UInt8](repeating: 0xAA, count: bytes)[...]), as: UTF8.self), expected)
        }
        XCTAssertEqual(String(decoding: ZPLASCIICompression.row([0xAA, 0xAB][...]), as: UTF8.self), "IAB")
        XCTAssertEqual(String(decoding: ZPLASCIICompression.row([0xAB, 0xCD][...]), as: UTF8.self), "ABCD")
    }

    func testDocumentedCountsAndLiteralFallback() {
        func encode(_ bytes: [UInt8]) -> String {
            String(decoding: ZPLASCIICompression.row(bytes[...]), as: UTF8.self)
        }
        XCTAssertEqual(encode([0xA5, 0x80]), "A580")
        XCTAssertEqual(encode([UInt8](repeating: 0xBB, count: 20)), "hB")
        XCTAssertEqual(encode([UInt8](repeating: 0x66, count: 3) + [0x60]), "M60")
        XCTAssertEqual(encode([UInt8](repeating: 0xBB, count: 163) + [0xB0]), "vMB0")
        XCTAssertEqual(encode([UInt8](repeating: 0, count: 210)), "zg0")
    }

    func testRepeatRowHistoryResetsAtEveryBandAndPaddingPreserved() throws {
        let bitmap = try MonochromeBitmap(width: 9, height: 4, bytes: [0xFF, 0x80, 0xFF, 0x80, 0xFF, 0x80, 0, 0])
        let output = String(decoding: try ZPLGraphicEncoder(maxDecodedBandBytes: 4).compressedDiagnosticFormat(bitmap), as: UTF8.self)
        XCTAssertEqual(output, "^XA\n^FO0,0^GFA,4,4,2,FF80:^FS\n^FO0,2^GFA,4,4,2,FF80J0^FS\n^XZ\n")
    }

    func testExactCompressedBudgetAndNoSinkOnFailure() throws {
        let bitmap = try MonochromeBitmap(width: 813, height: 1219, bytes: [UInt8](repeating: 0, count: 124338))
        let encoder = try ZPLGraphicEncoder()
        let output = try encoder.compressedDiagnosticFormat(bitmap)
        XCTAssertLessThan(output.count, 1500)
        XCTAssertEqual(try ZPLGraphicEncoder(maxOutputBytes: output.count).compressedDiagnosticFormat(bitmap), output)
        var calls = 0
        XCTAssertThrowsError(try ZPLGraphicEncoder(maxOutputBytes: output.count - 9).writeCompressedGraphicFields(bitmap, support: .supported) { _ in calls += 1 })
        XCTAssertEqual(calls, 0)
    }

    func testUnknownAndUnsupportedNeverReachSink() throws {
        let bitmap = try MonochromeBitmap(width: 8, height: 1, bytes: [0])
        var calls = 0
        for support in [CapabilityState.unknown, .unsupported] {
            XCTAssertThrowsError(try ZPLGraphicEncoder().writeCompressedGraphicFields(bitmap, support: support) { _ in calls += 1 })
        }
        XCTAssertEqual(calls, 0)
    }

    func testSinkFailureStopsAndChunksAreBounded() throws {
        enum Stop: Error { case now }
        let bitmap = try MonochromeBitmap(width: 32000, height: 2, bytes: [UInt8](repeating: 0xA5, count: 8000))
        var calls = 0
        XCTAssertThrowsError(try ZPLGraphicEncoder().writeCompressedGraphicFields(bitmap, support: .supported) { _ in calls += 1; throw Stop.now })
        XCTAssertEqual(calls, 1)
        var largest = 0
        try ZPLGraphicEncoder().writeCompressedGraphicFields(bitmap, support: .supported) { largest = max(largest, $0.count) }
        XCTAssertLessThanOrEqual(largest, 8000)
    }
}
