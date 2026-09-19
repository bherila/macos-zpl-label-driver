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
    func testDataBackedThresholdPreservesStrideAndThresholdRule() throws {
        let b = try MonochromeBitmap.threshold(
            width: 2,
            height: 2,
            grayscale: Data([0, 128, 99, 99, 127, 255, 99, 99]),
            stride: 4
        )
        XCTAssertEqual(b.bytes, [0b1000_0000, 0b1000_0000])
    }
    func testDataSlicesMatchRebasedInputsForBothPolicies() throws {
        let storage = Data([99, 0, 255])
        let sliced: Data = storage.dropFirst()
        XCTAssertNotEqual(sliced.startIndex, 0)
        let rebased = Data(sliced)
        XCTAssertEqual(
            try MonochromeBitmap.threshold(width: 2, height: 1, grayscale: sliced, stride: 2).bytes,
            try MonochromeBitmap.threshold(width: 2, height: 1, grayscale: rebased, stride: 2).bytes
        )
        XCTAssertEqual(
            try MonochromeConversion.photographicOrderedDither4x4.convert(
                width: 2, height: 1, grayscale: sliced, stride: 2
            ).bytes,
            try MonochromeConversion.photographicOrderedDither4x4.convert(
                width: 2, height: 1, grayscale: rebased, stride: 2
            ).bytes
        )
    }
    func testZeroThresholdIsWhite() throws {
        XCTAssertEqual(try MonochromeBitmap.threshold(width: 2, height: 1, grayscale: [0,255],
                                                     stride: 2, threshold: 0).bytes, [0])
    }
    func testExplicitTextAndBarcodePolicyUsesItsCutoff() throws {
        let bitmap = try MonochromeConversion.textAndBarcodeThreshold(cutoff: 128).convert(
            width: 3, height: 1, grayscale: Data([127, 128, 255]), stride: 3
        )
        XCTAssertEqual(bitmap.bytes, [0b1000_0000])
    }
    func testPhotographicDitherIsDeterministicAndKeepsPureEndpoints() throws {
        let conversion = MonochromeConversion.photographicOrderedDither4x4
        let midGray = Data(repeating: 128, count: 16)
        XCTAssertEqual(
            try conversion.convert(width: 4, height: 4, grayscale: midGray, stride: 4).bytes,
            [0b0101_0000, 0b1010_0000, 0b0101_0000, 0b1010_0000]
        )
        XCTAssertEqual(
            try conversion.convert(width: 4, height: 1, grayscale: Data(repeating: 0, count: 4), stride: 4).bytes,
            [0b1111_0000]
        )
        XCTAssertEqual(
            try conversion.convert(width: 4, height: 1, grayscale: Data(repeating: 255, count: 4), stride: 4).bytes,
            [0]
        )
    }
    func testPhotographicDitherValidatesSourceBeforePacking() {
        XCTAssertThrowsError(try MonochromeConversion.photographicOrderedDither4x4.convert(
            width: 2, height: 1, grayscale: Data([0]), stride: 1
        )) { XCTAssertEqual($0 as? MonochromeBitmap.ValidationError, .invalidGrayscaleStride) }
        XCTAssertThrowsError(try MonochromeConversion.photographicOrderedDither4x4.convert(
            width: 2, height: 2, grayscale: Data([0, 0]), stride: 2
        )) { XCTAssertEqual($0 as? MonochromeBitmap.ValidationError, .invalidGrayscaleLength) }
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

    /// Decodes set bits MSB-first, which is the direction the layout claims, so a
    /// transposed shift in the packer changes the recovered indices instead of
    /// agreeing with a mirrored expectation.
    private func blackColumns(_ bitmap: MonochromeBitmap, row: Int) -> [Int] {
        let bytesPerRow = bitmap.layout.bytesPerRow
        return (0..<bitmap.layout.width).filter { column in
            bitmap.bytes[row * bytesPerRow + column / 8] & (UInt8(0x80) >> UInt8(column % 8)) != 0
        }
    }

    /// M2-AC04 names these widths, and the ordered-dither branch packs rows itself
    /// rather than delegating to `threshold`, so it needs its own vectors. Pure
    /// black is below every Bayer threshold (the lowest is 8) and pure white is
    /// above every one (the highest is 248), which pins stride, MSB-first
    /// placement and the white tail without re-deriving the screen.
    func testPhotographicDitherAdversarialWidths() throws {
        let conversion = MonochromeConversion.photographicOrderedDither4x4
        for width in [1, 7, 8, 9, 811, 812, 813] {
            let bytesPerRow = (width + 7) / 8
            let height = 5  // Exceeds the 4-row screen, so `y & 3` must wrap.

            let allBlack = try conversion.convert(
                width: width, height: height,
                grayscale: Data(repeating: 0, count: width * height), stride: width)
            XCTAssertEqual(allBlack.bytes.count, bytesPerRow * height, "width \(width)")
            for row in 0..<height {
                XCTAssertEqual(blackColumns(allBlack, row: row), Array(0..<width), "width \(width) row \(row)")
            }

            let allWhite = try conversion.convert(
                width: width, height: height,
                grayscale: Data(repeating: 255, count: width * height), stride: width)
            XCTAssertEqual(allWhite.bytes, [UInt8](repeating: 0, count: bytesPerRow * height), "width \(width)")

            // Black only at the first and last column: the recovered indices are
            // mirrored within their byte if the packer shifts from the wrong end.
            var edges = Data(repeating: 255, count: width * height)
            for row in 0..<height {
                edges[row * width] = 0
                edges[row * width + width - 1] = 0
            }
            let edged = try conversion.convert(
                width: width, height: height, grayscale: edges, stride: width)
            let expected = width == 1 ? [0] : [0, width - 1]
            for row in 0..<height {
                XCTAssertEqual(blackColumns(edged, row: row), expected, "width \(width) row \(row)")
            }
        }
    }

    /// Row 0 of the screen ranks columns 0,8,2,10 by `x & 3`, so a uniform mid
    /// gray of 128 is black exactly where the rank is at least 8 — the odd
    /// columns. Checking that across 813 dots pins the phase against the column
    /// index rather than the byte offset.
    func testPhotographicDitherScreenPhaseHoldsAcrossByteBoundaries() throws {
        let width = 813
        let bitmap = try MonochromeConversion.photographicOrderedDither4x4.convert(
            width: width, height: 1, grayscale: Data(repeating: 128, count: width), stride: width)
        XCTAssertEqual(blackColumns(bitmap, row: 0), (0..<width).filter { $0 % 2 == 1 })
    }
}
