import XCTest
@testable import LabelCore

final class ExactJSONIntegerTests: XCTestCase {
    func testExactSignedEdgesAndIntegralDecimalExponentForms() {
        let cases: [(String, Int)] = [("0", 0), ("-0", 0), ("7.0", 7),
            ("7e0", 7), ("700e-2", 7), ("-7.00E+0", -7),
            ("9007199254740993", 9_007_199_254_740_993),
            ("9007199254740993.0", 9_007_199_254_740_993),
            ("9223372036854775807", Int.max), ("-9223372036854775808", Int.min),
            ("922337203685477580700e-2", Int.max),
            ("0e999999999999999999999999999999999", 0)]
        for (token, value) in cases { XCTAssertEqual(ExactJSONInteger.parse(token), value, token) }
    }

    func testFractionOverflowAndMalformedTokensRejectWithoutRounding() {
        for token in ["9007199254740993.5", "7.000000000000000000000000001",
            "9223372036854775808", "-9223372036854775809", "1e999999999999999999999",
            "1e-999999999999999999999", "0.1", "10e-2", "true", "NaN", "",
            "+1", "01", "-01", ".1", "1.", "1e", "1e+", "1 0", " 1", "1\n"] {
            XCTAssertNil(ExactJSONInteger.parse(token), token)
        }
    }

    func testTokenBudgetAndLongZeroCoefficientStayBounded() {
        let boundary = "0." + String(repeating: "0", count: ExactJSONInteger.maximumTokenBytes - 2)
        XCTAssertEqual(ExactJSONInteger.parse(boundary), 0)
        XCTAssertNil(ExactJSONInteger.parse(boundary + "0"))
        XCTAssertEqual(ExactJSONInteger.parse("1000e-3"), 1)
        XCTAssertNil(ExactJSONInteger.parse("1001e-3"))
    }
}
