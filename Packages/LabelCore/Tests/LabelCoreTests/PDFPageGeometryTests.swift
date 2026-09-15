import XCTest
@testable import LabelCore

final class PDFPageGeometryTests: XCTestCase {
    private func makeBox(rotation: Int) throws -> PDFPageBox {
        try PDFPageBox(originX: 10, originY: 20, width: 100, height: 200, rotationDegreesClockwise: rotation)
    }

    func testMapsUprightQuarterIntoOriginalBoxForAllRotations() throws {
        let region = try NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        XCTAssertEqual(try makeBox(rotation: 0).sourceRect(for: region), PDFSourceRect(x: 10, y: 120, width: 50, height: 100))
        XCTAssertEqual(try makeBox(rotation: 90).sourceRect(for: region), PDFSourceRect(x: 10, y: 20, width: 50, height: 100))
        XCTAssertEqual(try makeBox(rotation: 180).sourceRect(for: region), PDFSourceRect(x: 60, y: 20, width: 50, height: 100))
        XCTAssertEqual(try makeBox(rotation: 270).sourceRect(for: region), PDFSourceRect(x: 60, y: 120, width: 50, height: 100))
    }

    func testFullRegionAlwaysMapsToTheOriginalBox() throws {
        let region = try NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        for rotation in [0, 90, 180, 270] {
            XCTAssertEqual(try makeBox(rotation: rotation).sourceRect(for: region), PDFSourceRect(x: 10, y: 20, width: 100, height: 200))
        }
    }

    func testUserUnitAndRotationChangeOnlyEffectivePhysicalSize() throws {
        let box = try PDFPageBox(originX: 0, originY: 0, width: 72, height: 144, rotationDegreesClockwise: 90, userUnit: 2)
        let size = try box.effectivePhysicalSize()
        XCTAssertEqual(size.width.value, 101.6, accuracy: 0.000_000_1)
        XCTAssertEqual(size.height.value, 50.8, accuracy: 0.000_000_1)
    }

    func testActualSizePlacementChangesWhenOnlyUserUnitChanges() throws {
        let canvas = try DotCanvas(
            physicalSize: PhysicalSize(width: try Millimeters(200), height: try Millimeters(200)),
            resolution: DotResolution(xDotsPerMillimeter: 2, yDotsPerMillimeter: 2)
        )
        let unitOne = try PDFPageBox(originX: 0, originY: 0, width: 72, height: 144, userUnit: 1)
        let unitTwo = try PDFPageBox(originX: 0, originY: 0, width: 72, height: 144, userUnit: 2)

        let first = try PagePlacementPlanner.plan(
            source: unitOne.effectivePhysicalSize(), canvas: canvas, policy: .actualSize
        )
        let second = try PagePlacementPlanner.plan(
            source: unitTwo.effectivePhysicalSize(), canvas: canvas, policy: .actualSize
        )

        XCTAssertEqual(first.target.width, 51)
        XCTAssertEqual(first.target.height, 102)
        XCTAssertEqual(second.target.width, 102)
        XCTAssertEqual(second.target.height, 203)
    }

    func testRejectsUnsupportedPageAndRegionValues() {
        XCTAssertThrowsError(try PDFPageBox(originX: 0, originY: 0, width: 0, height: 1)) { XCTAssertEqual($0 as? PageGeometryError, .nonPositiveBox) }
        XCTAssertThrowsError(try PDFPageBox(originX: 0, originY: 0, width: 1, height: 1, rotationDegreesClockwise: 45)) { XCTAssertEqual($0 as? PageGeometryError, .unsupportedRotation) }
        XCTAssertThrowsError(try PDFPageBox(originX: 0, originY: 0, width: 1, height: 1, userUnit: 0.5)) { XCTAssertEqual($0 as? PageGeometryError, .invalidUserUnit) }
        XCTAssertThrowsError(try NormalizedRect(x: 0.5, y: 0.5, width: 0.6, height: 0.5)) { XCTAssertEqual($0 as? PageGeometryError, .invalidNormalizedRegion) }
    }
}
