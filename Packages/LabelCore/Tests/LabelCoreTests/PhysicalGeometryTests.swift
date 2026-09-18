import XCTest
@testable import LabelCore

final class PhysicalGeometryTests: XCTestCase {
    func testStockReplacementRetainsIndependentPitchAndAdmissionBudgets() throws {
        func size(_ width: Double, _ height: Double) throws -> PhysicalSize {
            PhysicalSize(width: try Millimeters(width), height: try Millimeters(height))
        }
        let original = try DotCanvas(
            physicalSize: size(10, 10),
            resolution: DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 12),
            maximumWidth: 96, maximumHeight: 144, maximumByteCount: 1_500
        )
        let unrestricted = try DotCanvas(physicalSize: size(10, 10), resolution: original.resolution)
        XCTAssertEqual(original, unrestricted)
        XCTAssertNoThrow(try unrestricted.replacingPhysicalSize(size(12, 12)))
        let smaller = try original.replacingPhysicalSize(size(5, 5))
        XCTAssertEqual(smaller.width, 40)
        XCTAssertEqual(smaller.height, 60)
        XCTAssertEqual(smaller.resolution, original.resolution)
        XCTAssertEqual(try smaller.replacingPhysicalSize(size(10, 10)), original)
        XCTAssertThrowsError(try smaller.replacingPhysicalSize(size(13, 5))) {
            XCTAssertEqual($0 as? PhysicalGeometryError, .exceedsDotLimit(actual: 104, limit: 96))
        }
        XCTAssertThrowsError(try smaller.replacingPhysicalSize(size(5, 13))) {
            XCTAssertEqual($0 as? PhysicalGeometryError, .exceedsDotLimit(actual: 156, limit: 144))
        }
        // Both dimensions fit their limits; their combination exceeds the byte budget.
        XCTAssertThrowsError(try smaller.replacingPhysicalSize(size(12, 12))) {
            XCTAssertEqual($0 as? BitmapLayout.ValidationError, .exceedsLimit(actual: 1_728, limit: 1_500))
        }
        XCTAssertEqual(original.width, 80)
        XCTAssertEqual(original.height, 120)
    }

    func testOutputMarginsPreservePhysicalFitAndActualSizeClippingWithIndependentPitch() throws {
        let canvas = try DotCanvas(physicalSize: PhysicalSize(width: Millimeters(20), height: Millimeters(10)),
            resolution: DotResolution(xDotsPerMillimeter: 4, yDotsPerMillimeter: 8))
        let source = PhysicalSize(width: try Millimeters(10), height: try Millimeters(10))
        let margins = try OutputMargins(left: 2, top: 1, right: 4, bottom: 3)
        let fit = try PagePlacementPlanner.plan(source: source, canvas: canvas, policy: .fit, margins: margins)
        XCTAssertEqual(fit.target, DotRect(x: 24, y: 8, width: 24, height: 48))
        XCTAssertEqual(fit.visible, fit.target)
        XCTAssertEqual(Double(fit.target.width) / 4, Double(fit.target.height) / 8)
        let actual = try PagePlacementPlanner.plan(source: source, canvas: canvas, policy: .actualSize, margins: margins)
        XCTAssertEqual(actual.target, DotRect(x: 16, y: -8, width: 40, height: 80))
        XCTAssertEqual(actual.visible, DotRect(x: 16, y: 8, width: 40, height: 48))
        for policy in [PagePlacementPolicy.fit, .actualSize] {
            XCTAssertEqual(try PagePlacementPlanner.plan(source: source, canvas: canvas, policy: policy),
                try PagePlacementPlanner.plan(source: source, canvas: canvas, policy: policy, margins: .zero))
        }
    }

    func testOutputMarginsRejectInvalidEmptyQuantizedAndOverflowingAreas() throws {
        for value in [-1, Double.infinity, Double.nan] {
            for index in 0..<4 {
                var values = [0.0, 0, 0, 0]; values[index] = value
                XCTAssertThrowsError(try OutputMargins(left: values[0], top: values[1], right: values[2], bottom: values[3]))
            }
        }
        let size = PhysicalSize(width: try Millimeters(1), height: try Millimeters(1))
        let canvas = try DotCanvas(physicalSize: size, resolution: DotResolution(xDotsPerMillimeter: 1, yDotsPerMillimeter: 1))
        for policy in [PagePlacementPolicy.fit, .actualSize] {
            for margins in [try OutputMargins(left: 1, top: 0, right: 0, bottom: 0),
                            try OutputMargins(left: 0, top: 0.5, right: 0, bottom: 0.49)] {
                XCTAssertThrowsError(try PagePlacementPlanner.plan(source: size, canvas: canvas, policy: policy, margins: margins)) {
                    XCTAssertEqual($0 as? PagePlacementError, .invalidMargins)
                }
            }
        }
        // Geometry-only arithmetic: no bitmap allocation despite permissive caller budgets.
        let huge = PhysicalSize(width: try Millimeters(8e18), height: try Millimeters(1))
        let hugeCanvas = try DotCanvas(physicalSize: huge, resolution: DotResolution(xDotsPerMillimeter: 1, yDotsPerMillimeter: 1),
            maximumWidth: Int.max, maximumHeight: 1, maximumByteCount: Int.max)
        XCTAssertThrowsError(try PagePlacementPlanner.plan(source: huge, canvas: hugeCanvas, policy: .actualSize,
            margins: OutputMargins(left: 7e18, top: 0, right: 0, bottom: 0), maximumPlacementDimension: Int.max)) {
            XCTAssertEqual($0 as? PagePlacementError, .placementExceedsLimit)
        }
    }

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

    func testPhysicalFitAccountsForNonSquareDotPitch() throws {
        let canvas = try DotCanvas(
            physicalSize: PhysicalSize(width: try Millimeters(200), height: try Millimeters(100)),
            resolution: DotResolution(xDotsPerMillimeter: 4, yDotsPerMillimeter: 8)
        )
        let placement = try PagePlacementPlanner.plan(
            source: PhysicalSize(width: try Millimeters(100), height: try Millimeters(100)),
            canvas: canvas,
            policy: .fit
        )
        XCTAssertEqual(placement.target, DotRect(x: 200, y: 0, width: 400, height: 800))
        XCTAssertEqual(placement.visible, placement.target)
        XCTAssertEqual(Double(placement.target.width) / canvas.resolution.xDotsPerMillimeter, 100, accuracy: 0.000_001)
        XCTAssertEqual(Double(placement.target.height) / canvas.resolution.yDotsPerMillimeter, 100, accuracy: 0.000_001)
    }

    func testActualSizePreservesPhysicalExtentAndReportsClipping() throws {
        let canvas = try DotCanvas(
            physicalSize: PhysicalSize(width: try .inches(4), height: try .inches(6)),
            resolution: DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8)
        )
        let placement = try PagePlacementPlanner.plan(
            source: PhysicalSize(width: try Millimeters(215.9), height: try Millimeters(279.4)),
            canvas: canvas,
            policy: .actualSize
        )
        XCTAssertEqual(placement.target, DotRect(x: -457, y: -508, width: 1_727, height: 2_235))
        XCTAssertEqual(placement.visible, DotRect(x: 0, y: 0, width: 813, height: 1_219))
        XCTAssertLessThanOrEqual(abs(Double(placement.target.width) - 215.9 * 8), 0.5)
        XCTAssertLessThanOrEqual(abs(Double(placement.target.height) - 279.4 * 8), 0.5)
    }

    func testPlacementRejectsInvalidAndExcessiveLimits() throws {
        let size = PhysicalSize(width: try Millimeters(10), height: try Millimeters(10))
        let canvas = try DotCanvas(physicalSize: size, resolution: DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8))
        XCTAssertThrowsError(try PagePlacementPlanner.plan(source: size, canvas: canvas, policy: .fit, maximumPlacementDimension: 0)) {
            XCTAssertEqual($0 as? PagePlacementError, .invalidLimit)
        }
        XCTAssertThrowsError(try PagePlacementPlanner.plan(source: size, canvas: canvas, policy: .actualSize, maximumPlacementDimension: 79)) {
            XCTAssertEqual($0 as? PagePlacementError, .placementExceedsLimit)
        }
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
