import XCTest
@testable import LabelCore

/// Coverage for the one-dot fit clip in `PagePlacementPlanner.plan`.
///
/// The planner computes the fit scale in millimetres and then rounds each
/// placed edge to dots independently. When a margin's own rounding takes more
/// dots than the physical margin costs, the rounded placement can land one dot
/// outside the inset area even though the physical extent fits. The planner
/// clips that single quantization dot rather than rescaling a second time.
///
/// This lives in its own file because `PhysicalGeometry.swift` and
/// `PhysicalGeometryTests.swift` are both cited by a live evidence record, and
/// a slice that changes a byte of a cited path is refused by preflight.
///
/// Every expectation below is a fixed literal derived by hand from the stated
/// geometry, never a value recomputed the way the planner computes it.
final class PagePlacementFitQuantizationTests: XCTestCase {
    /// 4x6in nominal stock at the model-documented 8 dots/mm pitch:
    /// 101.6mm -> 813 dots across, 152.4mm -> 1219 dots down.
    private func stockCanvas() throws -> DotCanvas {
        try DotCanvas(
            physicalSize: PhysicalSize(
                width: try Millimeters(101.6), height: try Millimeters(152.4)
            ),
            resolution: DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8)
        )
    }

    /// 1.0625mm is exactly 8.5 dots at 8 dots/mm, and the project rounding
    /// policy is nearest-away-from-zero, so each such margin costs 9 dots.
    private static let halfDotMargin = 1.0625

    func testCanvasDotExtentMatchesTheStatedPitch() throws {
        let canvas = try stockCanvas()
        XCTAssertEqual(canvas.width, 813)
        XCTAssertEqual(canvas.height, 1_219)
    }

    /// Two 1.0625mm side margins cost 18 dots, leaving an inset area of 795
    /// dots, while the surviving 99.475mm of stock rounds to 796 dots. The
    /// clip removes exactly that one dot; without it the target is 796 wide.
    func testFitClipsTheOneDotWidthOvershootIntroducedByMarginRounding() throws {
        let canvas = try stockCanvas()
        let margins = try OutputMargins(
            left: Self.halfDotMargin, top: 0, right: Self.halfDotMargin, bottom: 0
        )
        let placement = try PagePlacementPlanner.plan(
            source: PhysicalSize(width: try Millimeters(99.475), height: try Millimeters(10)),
            canvas: canvas,
            policy: .fit,
            margins: margins
        )
        XCTAssertEqual(placement.target, DotRect(x: 9, y: 569, width: 795, height: 80))
        XCTAssertEqual(placement.visible, DotRect(x: 9, y: 569, width: 795, height: 80))
    }

    /// The same overshoot on the vertical axis: 18 dots of top and bottom
    /// margin leave 1201 dots, and the surviving 150.275mm rounds to 1202.
    func testFitClipsTheOneDotHeightOvershootIntroducedByMarginRounding() throws {
        let canvas = try stockCanvas()
        let margins = try OutputMargins(
            left: 0, top: Self.halfDotMargin, right: 0, bottom: Self.halfDotMargin
        )
        let placement = try PagePlacementPlanner.plan(
            source: PhysicalSize(width: try Millimeters(10), height: try Millimeters(150.275)),
            canvas: canvas,
            policy: .fit,
            margins: margins
        )
        XCTAssertEqual(placement.target, DotRect(x: 366, y: 9, width: 80, height: 1_201))
        XCTAssertEqual(placement.visible, DotRect(x: 366, y: 9, width: 80, height: 1_201))
    }

    /// The accepted side of the same bound. Whole-dot margins cost 16 dots,
    /// the inset area is 797 dots, and the surviving 99.6mm rounds to exactly
    /// 797. A placement that already fits must pass through untouched, so the
    /// clip is a quantization correction and not a general shrink.
    func testFitLeavesAPlacementThatAlreadyFillsTheInsetAreaUnchanged() throws {
        let canvas = try stockCanvas()
        let margins = try OutputMargins(left: 1, top: 0, right: 1, bottom: 0)
        let placement = try PagePlacementPlanner.plan(
            source: PhysicalSize(width: try Millimeters(99.6), height: try Millimeters(10)),
            canvas: canvas,
            policy: .fit,
            margins: margins
        )
        XCTAssertEqual(placement.target, DotRect(x: 8, y: 569, width: 797, height: 80))
        XCTAssertEqual(placement.visible, DotRect(x: 8, y: 569, width: 797, height: 80))
    }

    /// The clip belongs to `.fit` alone. `actualSize` preserves the physical
    /// extent and reports the overflow through `visible`, so the identical
    /// geometry keeps its 796-dot target and reports 795 visible dots.
    func testActualSizeKeepsTheUnclippedTargetAndReportsTheClippedVisibleArea() throws {
        let canvas = try stockCanvas()
        let margins = try OutputMargins(
            left: Self.halfDotMargin, top: 0, right: Self.halfDotMargin, bottom: 0
        )
        let placement = try PagePlacementPlanner.plan(
            source: PhysicalSize(width: try Millimeters(99.475), height: try Millimeters(10)),
            canvas: canvas,
            policy: .actualSize,
            margins: margins
        )
        XCTAssertEqual(placement.target, DotRect(x: 9, y: 569, width: 796, height: 80))
        XCTAssertEqual(placement.visible, DotRect(x: 9, y: 569, width: 795, height: 80))
    }
}
