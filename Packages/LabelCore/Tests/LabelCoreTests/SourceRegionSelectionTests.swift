import XCTest
@testable import LabelCore

final class SourceRegionSelectionTests: XCTestCase {
    func testZoomAndReverseDirectionPreserveCanonicalBounds() throws {
        let expected = try NormalizedRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4)
        for scale in [1.0, 2.0, 4.0] {
            for reversed in [false, true] {
                let result = try SourceRegionSelection.rectangle(viewportWidth: 200 * scale,
                    viewportHeight: 400 * scale, startX: (reversed ? 100 : 20) * scale,
                    startY: (reversed ? 200 : 40) * scale, endX: (reversed ? 20 : 100) * scale,
                    endY: (reversed ? 40 : 200) * scale)
                XCTAssertEqual(result, expected)
            }
        }
    }

    func testEndpointConstraintsNeverAdoptOffPageStartOrEmptyDrag() throws {
        let edge = try SourceRegionSelection.rectangle(viewportWidth: 200, viewportHeight: 400,
            startX: 20, startY: 40, endX: .greatestFiniteMagnitude, endY: .greatestFiniteMagnitude)
        XCTAssertEqual(edge, try NormalizedRect(x: 0.1, y: 0.1, width: 0.9, height: 0.9))
        for values in [(Double.nan, 400.0, 20.0, 40.0, 100.0, 200.0),
                       (200, 0, 20, 40, 100, 200), (200, 400, -1, 40, 100, 200),
                       (200, 400, 20, 40, Double.infinity, 200), (200, 400, 20, 40, 20, 200)] {
            XCTAssertThrowsError(try SourceRegionSelection.rectangle(viewportWidth: values.0,
                viewportHeight: values.1, startX: values.2, startY: values.3,
                endX: values.4, endY: values.5))
        }
    }

    /// An off-page drag origin is refused as `invalidDrag` by the origin rule
    /// itself. Without that rule the clamped endpoint still yields a rectangle
    /// outside the unit square, so `NormalizedRect` refuses it a step later
    /// with `PageGeometryError.invalidNormalizedRegion` — a different rule
    /// producing a different refusal, which a bare throws-assertion accepts.
    func testOffPageDragOriginIsRefusedAsInvalidDragNotAsAnInvalidRegion() {
        let width = 200.0
        let height = 400.0
        for start in [(-1.0, 40.0), (width.nextUp, 40.0), (width + 1, 40.0),
                      (20.0, -1.0), (20.0, height.nextUp), (20.0, height + 1),
                      (-0.5, -0.5)] {
            XCTAssertThrowsError(try SourceRegionSelection.rectangle(
                viewportWidth: width, viewportHeight: height,
                startX: start.0, startY: start.1, endX: 100, endY: 200
            ), "\(start)") {
                XCTAssertEqual($0 as? SourceRegionSelection.Error, .invalidDrag, "\(start)")
            }
        }
    }

    /// The accepted side of the same bound: both closed edges of the viewport
    /// are legal drag origins. Expectations are fixed literals, not values
    /// recomputed from the viewport the way the call under test computes them.
    func testViewportEdgesRemainLegalDragOrigins() throws {
        XCTAssertEqual(
            try SourceRegionSelection.rectangle(viewportWidth: 200, viewportHeight: 400,
                startX: 0, startY: 0, endX: 100, endY: 200),
            try NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        )
        XCTAssertEqual(
            try SourceRegionSelection.rectangle(viewportWidth: 200, viewportHeight: 400,
                startX: 200, startY: 400, endX: 100, endY: 200),
            try NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        )
    }
}
