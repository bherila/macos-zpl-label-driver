import Foundation
import XCTest
@testable import LabelCore

final class TokenPreservingJSONTests: XCTestCase {
    func testNestedNumericTokensRemainExactAndStringsAreNotNumbers() throws {
        let data = Data(#"{"revision":9007199254740993,"values":[9007199254740993.5,7e0,-9223372036854775808],"text":"9007199254740993.5","yes":true,"none":null}"#.utf8)
        let root = try XCTUnwrap(TokenPreservingJSON.decode(data) as? [String: Any])
        let revision = try XCTUnwrap(root["revision"] as? TokenPreservingJSON.Number)
        XCTAssertEqual(ExactJSONInteger.parse(revision.token), 9_007_199_254_740_993)
        let values = try XCTUnwrap(root["values"] as? [TokenPreservingJSON.Number])
        XCTAssertNil(ExactJSONInteger.parse(values[0].token))
        XCTAssertEqual(values[1].token, "7e0")
        XCTAssertEqual(ExactJSONInteger.parse(values[2].token), Int.min)
        XCTAssertEqual(root["text"] as? String, "9007199254740993.5")
        XCTAssertEqual((root["yes"] as? NSNumber)?.boolValue, true)
        XCTAssertTrue(root["none"] is NSNull)
    }

    func testEscapedKeysStringsAndUnicodeUseValidatedStringDecoding() throws {
        let root = try XCTUnwrap(TokenPreservingJSON.decode(Data(#"{"revi\u0073ion":7,"text":"comma, quote\" slash\\ and \uD83D\uDE80"}"#.utf8)) as? [String: Any])
        XCTAssertEqual((root["revision"] as? TokenPreservingJSON.Number)?.token, "7")
        XCTAssertEqual(root["text"] as? String, "comma, quote\" slash\\ and 🚀")
    }

    func testMalformedGrammarAndDuplicateDecodedKeysReject() {
        for text in ["", "7", "{} []", "[01]", "[1.]", "[1e+]", "[+1]", "[truex]",
            "[1,]", "{\"a\":1,}", "{\"a\":1,\"a\":2}", #"{"a":1,"\u0061":2}"#,
            #"["\q"]"#, #"["\uD800"]"#, "[NaN]", "[Infinity]"] {
            XCTAssertThrowsError(try TokenPreservingJSON.decode(Data(text.utf8)), text)
        }
        XCTAssertThrowsError(try TokenPreservingJSON.decode(Data([91,34,255,34,93])))
    }

    func testDepthNodesInputAndNumericTokenBudgetsReject() throws {
        let accepted = String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64)
        XCTAssertNoThrow(try TokenPreservingJSON.decode(Data(accepted.utf8)))
        XCTAssertThrowsError(try TokenPreservingJSON.decode(Data(("[" + accepted + "]").utf8)))
        XCTAssertThrowsError(try TokenPreservingJSON.decode(Data(repeating: 32, count: TokenPreservingJSON.maximumBytes + 1)))
        let nodes = "[" + Array(repeating: "0", count: TokenPreservingJSON.maximumNodes).joined(separator: ",") + "]"
        XCTAssertThrowsError(try TokenPreservingJSON.decode(Data(nodes.utf8)))
        let token = "[1" + String(repeating: "0", count: ExactJSONInteger.maximumTokenBytes) + "]"
        XCTAssertThrowsError(try TokenPreservingJSON.decode(Data(token.utf8)))
    }
}
