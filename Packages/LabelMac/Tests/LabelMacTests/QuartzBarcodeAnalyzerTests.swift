import CoreGraphics
import Foundation
import LabelCore
import XCTest
@testable import LabelMac

final class QuartzBarcodeAnalyzerTests: XCTestCase {
    func testLowerLeftLocationsBecomeCanonicalTopLeftWithoutClamping() throws {
        let rect = try QuartzBarcodeAnalyzer.canonicalRectangle(
            visionLowerLeft: CGRect(x: 0.2, y: 0.1, width: 0.3, height: 0.25))
        XCTAssertEqual(rect.x, 0.2)
        XCTAssertEqual(rect.y, 0.65, accuracy: 1e-12)
        XCTAssertEqual(rect.width, 0.3)
        XCTAssertEqual(rect.height, 0.25)
        XCTAssertEqual(try QuartzBarcodeAnalyzer.canonicalRectangle(
            visionLowerLeft: CGRect(x: 0, y: 0.9, width: 1, height: 0.1)).y, 0)
        for invalid in [CGRect(x: -0.01, y: 0, width: 0.1, height: 0.1),
                        CGRect(x: 0, y: 0.9, width: 0.1, height: 0.2),
                        CGRect(x: 0, y: 0, width: 0, height: 0.1),
                        CGRect(x: .infinity, y: 0, width: 0.1, height: 0.1),
                        CGRect(x: 0, y: .nan, width: 0.1, height: 0.1)] {
            XCTAssertThrowsError(try QuartzBarcodeAnalyzer.canonicalRectangle(visionLowerLeft: invalid)) {
                XCTAssertEqual($0 as? QuartzBarcodeAnalyzer.Error, .invalidObservation)
            }
        }
        XCTAssertEqual(OfflineRenderWorkerProcess.classifyFailure(
            QuartzBarcodeAnalyzer.Error.detectorUnavailable).code, .layoutDetectorUnavailable)
        XCTAssertEqual(OfflineRenderWorkerProcess.classifyFailure(
            QuartzBarcodeAnalyzer.Error.observationLimitExceeded).code, .limitExceeded)
    }
}
