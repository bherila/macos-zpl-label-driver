import XCTest
@testable import LabelCore

final class PhysicalGeometryTests: XCTestCase {
    func testGC420dPhysicalPitchOracle() throws {
        let stock = PhysicalSize(width: try .inches(4), height: try .inches(6))
        let canvas = try DotCanvas(
            physicalSize: stock,
            resolution: DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8)
        )
        XCTAssertEqual(canvas.width, 813)
        XCTAssertEqual(canvas.height, 1_219)
        XCTAssertEqual(canvas.bitmapLayout.bytesPerRow, 102)
        XCTAssertEqual(canvas.bitmapLayout.byteCount, 124_338)
        XCTAssertEqual(canvas.bitmapLayout.bytesPerRow * 8 - canvas.width, 3)
    }

    func testHalfDotsRoundAwayFromZero() throws {
        let resolution = try DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8)
        XCTAssertEqual(try resolution.roundedDots(for: Millimeters(0.0625), horizontal: true), 1)
        XCTAssertEqual(try resolution.roundedDots(for: Millimeters(0.1875), horizontal: false), 2)
    }

    func testSupportsNonSquareResolution() throws {
        let size = PhysicalSize(width: try Millimeters(10), height: try Millimeters(10))
        let canvas = try DotCanvas(
            physicalSize: size,
            resolution: DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 12)
        )
        XCTAssertEqual(canvas.width, 80)
        XCTAssertEqual(canvas.height, 120)
    }

    func testRejectsInvalidPhysicalInputs() {
        XCTAssertThrowsError(try Millimeters(.infinity)) { XCTAssertEqual($0 as? PhysicalGeometryError, .nonFiniteLength) }
        XCTAssertThrowsError(try Millimeters(0)) { XCTAssertEqual($0 as? PhysicalGeometryError, .nonPositiveLength) }
        XCTAssertThrowsError(try DotResolution(xDotsPerMillimeter: .nan, yDotsPerMillimeter: 8)) { XCTAssertEqual($0 as? PhysicalGeometryError, .nonFiniteResolution) }
        XCTAssertThrowsError(try DotResolution(xDotsPerMillimeter: 0, yDotsPerMillimeter: 8)) { XCTAssertEqual($0 as? PhysicalGeometryError, .nonPositiveResolution) }
    }

    func testRejectsDotAndByteLimits() throws {
        let stock = PhysicalSize(width: try Millimeters(10), height: try Millimeters(10))
        let resolution = try DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8)
        XCTAssertThrowsError(try DotCanvas(physicalSize: stock, resolution: resolution, maximumWidth: 79)) {
            XCTAssertEqual($0 as? PhysicalGeometryError, .exceedsDotLimit(actual: 80, limit: 79))
        }
        XCTAssertThrowsError(try DotCanvas(physicalSize: stock, resolution: resolution, maximumHeight: 79)) {
            XCTAssertEqual($0 as? PhysicalGeometryError, .exceedsDotLimit(actual: 80, limit: 79))
        }
    }
}
