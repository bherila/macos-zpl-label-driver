import XCTest
@testable import LabelMac

final class CoreGraphicsSmokeCheckTests: XCTestCase {
    func testWhitePixel() throws {
        XCTAssertEqual(try CoreGraphicsSmokeCheck.run(), 255)
    }
}
