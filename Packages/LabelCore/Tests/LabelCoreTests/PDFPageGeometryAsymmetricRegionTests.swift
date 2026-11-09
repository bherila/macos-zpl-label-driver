import XCTest
@testable import LabelCore

/// An off-origin, non-square region through every page rotation.
///
/// The existing rotation tests use a region at (0, 0) or the whole page, so a mapping that swapped
/// the region's x and y axes (or its width and height) is invisible to them: x == y == 0. This
/// region has x != y and width != height, so each axis and each extent has its own value.
///
/// The expected rectangles are derived by hand from the geometry below, not by running the code:
///
/// Unrotated page: origin (10, 20), width W = 100, height H = 200, PDF y pointing up. The upright
/// (displayed) page is that page rotated clockwise by `rotation`. The region is normalized in the
/// upright page: u to the right, v downward, with u0 = 0.125, v0 = 0.25, width 0.5, height 0.25.
/// Every fraction is a power of two, so every product below is exact in binary floating point.
///
/// - 0°:   u runs along x, v runs down, so PDF y from the bottom is 1 - (v0 + h).
///         x = 10 + 0.125 * 100 = 22.5   y = 20 + (1 - 0.5) * 200 = 120   w = 50   h = 50
/// - 90°:  the displayed left edge is the unrotated bottom edge, the displayed top edge is the
///         unrotated left edge. u runs up the unrotated y axis, v runs along its x axis.
///         x = 10 + 0.25 * 100 = 35      y = 20 + 0.125 * 200 = 45    w = 0.25 * 100 = 25   h = 0.5 * 200 = 100
/// - 180°: both axes are reversed. x = 10 + (1 - 0.625) * 100 = 47.5   y = 20 + 0.25 * 200 = 70   w = 50   h = 50
/// - 270°: the displayed left edge is the unrotated top edge, the displayed top edge is the
///         unrotated right edge. x = 10 + (1 - 0.5) * 100 = 60   y = 20 + (1 - 0.625) * 200 = 95
///         w = 0.25 * 100 = 25   h = 0.5 * 200 = 100
final class PDFPageGeometryAsymmetricRegionTests: XCTestCase {
    private func box(rotation: Int) throws -> PDFPageBox {
        try PDFPageBox(originX: 10, originY: 20, width: 100, height: 200, rotationDegreesClockwise: rotation)
    }

    func testAnOffOriginNonSquareRegionMapsCorrectlyThroughEveryRotation() throws {
        let region = try NormalizedRect(x: 0.125, y: 0.25, width: 0.5, height: 0.25)
        XCTAssertEqual(try box(rotation: 0).sourceRect(for: region),
                       PDFSourceRect(x: 22.5, y: 120, width: 50, height: 50))
        XCTAssertEqual(try box(rotation: 90).sourceRect(for: region),
                       PDFSourceRect(x: 35, y: 45, width: 25, height: 100))
        XCTAssertEqual(try box(rotation: 180).sourceRect(for: region),
                       PDFSourceRect(x: 47.5, y: 70, width: 50, height: 50))
        XCTAssertEqual(try box(rotation: 270).sourceRect(for: region),
                       PDFSourceRect(x: 60, y: 95, width: 25, height: 100))
    }
}
