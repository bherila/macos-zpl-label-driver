import XCTest
@testable import LabelCore

final class BitmapLayoutTests: XCTestCase {
    func testNominal203DPIExample() throws {
        let layout = try BitmapLayout(width: 812, height: 1_218)
        XCTAssertEqual(layout.bytesPerRow, 102)
        XCTAssertEqual(layout.byteCount, 124_236)
    }

    /// Derived reference layout, not a measured imageable region or renderer test.
    /// GC420d is documented at 8 dots/mm: nearest-dot 4x6 face is 813x1219.
    func testGC420dReferenceLayout() throws {
        let layout = try BitmapLayout(width: 813, height: 1_219)
        XCTAssertEqual(layout.bytesPerRow, 102)
        XCTAssertEqual(layout.byteCount, 124_338)
        XCTAssertEqual(layout.bytesPerRow * 8 - layout.width, 3)
    }

    func testNonByteAlignedWidths() throws {
        for (width, expected) in [(1, 1), (7, 1), (8, 1), (9, 2), (811, 102), (812, 102), (813, 102)] {
            let layout = try BitmapLayout(width: width, height: 3)
            XCTAssertEqual(layout.bytesPerRow, expected)
            XCTAssertEqual(layout.byteCount, expected * 3)
        }
    }

    func testRejectsInvalidDimensions() {
        for (width, height) in [(0, 1), (1, 0), (-1, 1), (1, -1)] {
            XCTAssertThrowsError(try BitmapLayout(width: width, height: height)) {
                XCTAssertEqual($0 as? BitmapLayout.ValidationError, .invalidDimensions)
            }
        }
    }

    func testRejectsInvalidLimit() {
        XCTAssertThrowsError(try BitmapLayout(width: 8, height: 1, maxByteCount: 0)) {
            XCTAssertEqual($0 as? BitmapLayout.ValidationError, .invalidLimit)
        }
    }

    func testRejectsMultiplicationOverflow() {
        XCTAssertThrowsError(try BitmapLayout(width: Int.max, height: Int.max, maxByteCount: Int.max)) {
            XCTAssertEqual($0 as? BitmapLayout.ValidationError, .sizeOverflow)
        }
    }

    func testLimitBoundary() throws {
        XCTAssertEqual(try BitmapLayout(width: 9, height: 3, maxByteCount: 6).byteCount, 6)
        XCTAssertThrowsError(try BitmapLayout(width: 9, height: 3, maxByteCount: 5)) {
            XCTAssertEqual($0 as? BitmapLayout.ValidationError, .exceedsLimit(actual: 6, limit: 5))
        }
    }

    func testCeilingDivisionDoesNotAddSevenToWidth() throws {
        // Arithmetic only; no allocation. Model/render limits are separate contracts.
        let layout = try BitmapLayout(width: Int.max, height: 1, maxByteCount: Int.max)
        XCTAssertEqual(layout.bytesPerRow, Int.max / 8 + 1)
    }
}
