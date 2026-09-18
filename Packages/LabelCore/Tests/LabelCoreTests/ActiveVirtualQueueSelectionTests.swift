import Foundation
import XCTest
@testable import LabelCore

final class ActiveVirtualQueueSelectionTests: XCTestCase {
    func testExactIntegerIdentityAcrossLargeQueueReferences() throws {
        for value in [9_007_199_254_740_993, Int.max] {
            let expected = try ActiveVirtualQueueSelection(generation: 1,
                queue: reference(revision: value), previousQueueSHA256: nil)
            XCTAssertEqual(try ActiveVirtualQueueJSON.decode(ActiveVirtualQueueJSON.encode(expected)), expected)
        }
    }

    private let firstDigest = String(repeating: "a", count: 64)
    private let secondDigest = String(repeating: "b", count: 64)

    private func reference(revision: Int = 1, digest: String? = nil) throws -> ImmutableProfileReference {
        try ImmutableProfileReference(
            id: "shipping-native", revision: revision, sha256: digest ?? firstDigest
        )
    }

    func testInitialAndUpdatedSelectionsRoundTripExactly() throws {
        let initial = try ActiveVirtualQueueSelection(
            generation: 1, queue: reference(), previousQueueSHA256: nil
        )
        let updated = try ActiveVirtualQueueSelection(
            generation: 2, queue: reference(revision: 2, digest: secondDigest),
            previousQueueSHA256: firstDigest
        )
        for value in [initial, updated] {
            let encoded = try ActiveVirtualQueueJSON.encode(value)
            XCTAssertEqual(try ActiveVirtualQueueJSON.decode(encoded), value)
            XCTAssertEqual(try ActiveVirtualQueueJSON.encode(ActiveVirtualQueueJSON.decode(encoded)), encoded)
        }
    }

    func testGenerationAndHistoryInvariantsFailClosed() throws {
        XCTAssertThrowsError(try ActiveVirtualQueueSelection(
            generation: 0, queue: reference(), previousQueueSHA256: nil
        )) { XCTAssertEqual($0 as? ActiveVirtualQueueError, .invalidGeneration) }
        XCTAssertThrowsError(try ActiveVirtualQueueSelection(
            generation: 1, queue: reference(), previousQueueSHA256: secondDigest
        )) { XCTAssertEqual($0 as? ActiveVirtualQueueError, .invalidHistory) }
        XCTAssertThrowsError(try ActiveVirtualQueueSelection(
            generation: 2, queue: reference(), previousQueueSHA256: nil
        )) { XCTAssertEqual($0 as? ActiveVirtualQueueError, .invalidHistory) }
        XCTAssertThrowsError(try ActiveVirtualQueueSelection(
            generation: 2, queue: reference(), previousQueueSHA256: firstDigest
        )) { XCTAssertEqual($0 as? ActiveVirtualQueueError, .invalidHistory) }
    }

    func testUnknownFieldsCannotCarryPathsCommandsOrDocuments() throws {
        let value = try ActiveVirtualQueueSelection(
            generation: 1, queue: reference(), previousQueueSHA256: nil
        )
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: ActiveVirtualQueueJSON.encode(value)
        ) as? [String: Any])
        for (key, payload) in [
            ("path", "/tmp/filter"), ("command", "raw-printer-command"),
            ("document", "private label"),
        ] {
            root[key] = payload
            XCTAssertThrowsError(try ActiveVirtualQueueJSON.decode(
                JSONSerialization.data(withJSONObject: root)
            )) { XCTAssertEqual($0 as? ActiveVirtualQueueJSONError, .unknownField) }
            root.removeValue(forKey: key)
        }
    }

    func testWireBoundsApplyBeforeParsingAndAfterEncoding() throws {
        XCTAssertThrowsError(try ActiveVirtualQueueJSON.decode(
            Data(repeating: 0x20, count: ActiveVirtualQueueJSON.maximumBytes + 1)
        )) { XCTAssertEqual($0 as? ActiveVirtualQueueJSONError, .inputTooLarge) }
        let value = try ActiveVirtualQueueSelection(
            generation: 1, queue: reference(), previousQueueSHA256: nil
        )
        XCTAssertThrowsError(try ActiveVirtualQueueJSON.encode(value, maximumBytes: 1)) {
            XCTAssertEqual($0 as? ActiveVirtualQueueJSONError, .outputTooLarge)
        }
    }
}
