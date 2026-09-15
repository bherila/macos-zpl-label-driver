import XCTest
@testable import LabelCore

final class MonochromeBitmapTests: XCTestCase {
    func testExactCount() { XCTAssertThrowsError(try MonochromeBitmap(width: 9, height: 2, bytes: [0])) }
    func testRejectsNonzeroPadding() {
        XCTAssertThrowsError(try MonochromeBitmap(width: 9, height: 1, bytes: [0, 1])) {
            XCTAssertEqual($0 as? MonochromeBitmap.ValidationError, .nonzeroPadding(row: 0))
        }
    }
    func testAcceptsHighBitTail() throws {
        XCTAssertEqual(try MonochromeBitmap(width: 9, height: 1, bytes: [255, 128]).bytes, [255, 128])
    }
    func testAllPaddingWidths() throws {
        for width in 1...32 {
            let stride = (width + 7) / 8
            var bytes = [UInt8](repeating: 255, count: stride)
            if width % 8 != 0 { bytes[stride - 1] = UInt8(0xFF << (8 - width % 8) & 255) }
            _ = try MonochromeBitmap(width: width, height: 1, bytes: bytes)
        }
    }
    func testThresholdAndBitOrder() throws {
        let b = try MonochromeBitmap.threshold(width: 9, height: 1,
                  grayscale: [0,127,128,255,0,255,0,255,0], stride: 9)
        XCTAssertEqual(b.bytes, [0b11001010, 0b10000000])
    }
    func testGrayscaleRowPaddingIsIgnored() throws {
        let b = try MonochromeBitmap.threshold(width: 1, height: 2,
                  grayscale: [0,0,0,255,0,0], stride: 3)
        XCTAssertEqual(b.bytes, [128,0])
    }
    func testZeroThresholdIsWhite() throws {
        XCTAssertEqual(try MonochromeBitmap.threshold(width: 2, height: 1, grayscale: [0,255],
                                                     stride: 2, threshold: 0).bytes, [0])
    }
    func testRejectsShortGrayscaleStride() {
        XCTAssertThrowsError(try MonochromeBitmap.threshold(width: 9, height: 1, grayscale: [0], stride: 1))
    }
    func testRejectsWrongGrayscaleLengthAndOverflow() {
        XCTAssertThrowsError(try MonochromeBitmap.threshold(width: 1, height: 2, grayscale: [0], stride: 1))
        XCTAssertThrowsError(try MonochromeBitmap.threshold(width: 1, height: 2, grayscale: [], stride: Int.max))
    }
    func testPackedLimitBeforeAllocation() {
        XCTAssertThrowsError(try MonochromeBitmap.threshold(width: 100, height: 100,
                                                          grayscale: [], stride: 100, maxByteCount: 1))
    }
    func testPBMIsExactPayload() throws {
        let b = try MonochromeBitmap(width: 9, height: 1, bytes: [0xA5,0x80])
        XCTAssertEqual(b.pbmData(), Data("P4\n9 1\n".utf8) + Data([0xA5,0x80]))
    }
    func testGrayscalePreviewExpandsExactBitsWithoutTailPadding() throws {
        let b = try MonochromeBitmap(width: 9, height: 2, bytes: [0b1010_0001, 0b1000_0000, 0b0101_1110, 0])
        let preview = b.grayscalePreview()
        XCTAssertEqual(preview.width, 9)
        XCTAssertEqual(preview.height, 2)
        XCTAssertEqual(preview.bytesPerRow, 9)
        XCTAssertEqual(preview.pixels, [0,255,0,255,255,255,255,0,0, 255,0,255,0,0,0,0,255,255])
    }
}
