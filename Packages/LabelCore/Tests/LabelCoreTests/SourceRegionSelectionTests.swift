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
}
