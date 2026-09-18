import Foundation
import XCTest
@testable import LabelCore

final class AcceptedJobStateTests: XCTestCase {
    func testExactIntegerIdentityAcrossLargeStateGenerations() throws {
        for value in [9_007_199_254_740_993, Int.max] {
            let expected = try AcceptedJobStateRecord(acceptanceID: "large-generation",
                acceptedTicketSHA256: hashA, generation: value, previousStateSHA256: hashA,
                phase: .prepared(payloadSHA256: hashA, byteCount: 10))
            XCTAssertEqual(try AcceptedJobStateJSON.decode(AcceptedJobStateJSON.encode(expected)), expected)
        }
    }

    private let hashA = String(repeating: "a", count: 64)
    private let hashB = String(repeating: "b", count: 64)

    private func next(
        _ state: AcceptedJobStateRecord, _ phase: AcceptedJobPhase
    ) throws -> AcceptedJobStateRecord {
        try state.advanced(to: phase, previousStateSHA256: hashB)
    }

    func testCompleteLifecycleRetainsPayloadAndDistinguishesConfirmation() throws {
        var state = try AcceptedJobStateRecord.accepted(
            acceptanceID: "job-1", acceptedTicketSHA256: hashA
        )
        state = try next(state, .prepared(payloadSHA256: hashA, byteCount: 10))
        state = try next(state, .waiting(payloadSHA256: hashA, byteCount: 10))
        state = try next(state, .transmitting(payloadSHA256: hashA, byteCount: 10, bytesAccepted: 4))
        state = try next(state, .transmitting(payloadSHA256: hashA, byteCount: 10, bytesAccepted: 10))
        state = try next(state, .transmitted(payloadSHA256: hashA, byteCount: 10))
        XCTAssertNotEqual(state.phase, .deviceConfirmed(payloadSHA256: hashA, byteCount: 10))
        state = try next(state, .deviceConfirmed(payloadSHA256: hashA, byteCount: 10))
        XCTAssertEqual(state.generation, 7)
    }

    func testPartialProgressCannotMoveBackwardOrChangePayload() throws {
        var state = try AcceptedJobStateRecord.accepted(
            acceptanceID: "job-2", acceptedTicketSHA256: hashA
        )
        state = try next(state, .prepared(payloadSHA256: hashA, byteCount: 10))
        state = try next(state, .waiting(payloadSHA256: hashA, byteCount: 10))
        state = try next(state, .transmitting(payloadSHA256: hashA, byteCount: 10, bytesAccepted: 8))
        XCTAssertThrowsError(try next(state, .transmitting(payloadSHA256: hashA, byteCount: 10, bytesAccepted: 2)))
        XCTAssertThrowsError(try next(state, .uncertain(payloadSHA256: hashB, byteCount: 10, bytesAccepted: 8)))
        XCTAssertThrowsError(try next(state, .transmitted(payloadSHA256: hashA, byteCount: 10)))
    }

    func testAmbiguityBeforeKnownBytesAndAfterTransmissionIsTerminal() throws {
        var waiting = try AcceptedJobStateRecord.accepted(
            acceptanceID: "job-3", acceptedTicketSHA256: hashA
        )
        waiting = try next(waiting, .prepared(payloadSHA256: hashA, byteCount: 10))
        waiting = try next(waiting, .waiting(payloadSHA256: hashA, byteCount: 10))
        let uncertain = try next(waiting, .uncertain(payloadSHA256: hashA, byteCount: 10, bytesAccepted: 0))
        XCTAssertThrowsError(try next(uncertain, .waiting(payloadSHA256: hashA, byteCount: 10)))
        XCTAssertThrowsError(try next(waiting, .uncertain(payloadSHA256: hashA, byteCount: 10, bytesAccepted: 1)))
    }

    func testPreTransmissionStagesCanFailOrCancel() throws {
        let accepted = try AcceptedJobStateRecord.accepted(
            acceptanceID: "job-4", acceptedTicketSHA256: hashA
        )
        XCTAssertEqual(try next(accepted, .cancelledBeforeTransmission).phase, .cancelledBeforeTransmission)
        var waiting = try next(accepted, .prepared(payloadSHA256: hashA, byteCount: 10))
        XCTAssertEqual(try next(waiting, .failedBeforeTransmission).phase, .failedBeforeTransmission)
        waiting = try next(waiting, .waiting(payloadSHA256: hashA, byteCount: 10))
        XCTAssertEqual(try next(waiting, .cancelledBeforeTransmission).phase, .cancelledBeforeTransmission)
        XCTAssertEqual(try next(waiting, .failedBeforeTransmission).phase, .failedBeforeTransmission)
    }

    func testCanonicalJSONRoundTripAndHistory() throws {
        var state = try AcceptedJobStateRecord.accepted(
            acceptanceID: "job-5", acceptedTicketSHA256: hashA
        )
        state = try next(state, .prepared(payloadSHA256: hashA, byteCount: 123))
        let bytes = try AcceptedJobStateJSON.encode(state)
        XCTAssertEqual(try AcceptedJobStateJSON.decode(bytes), state)
        XCTAssertEqual(try AcceptedJobStateJSON.encode(AcceptedJobStateJSON.decode(bytes)), bytes)
        XCTAssertEqual(state.previousStateSHA256, hashB)
    }

    func testCanonicalLegacyStateRequiresExplicitTicketBoundMigration() throws {
        let legacy = Data("""
        {"acceptanceID":"legacy-job","generation":4,"phase":{"byteCount":10,"bytesAccepted":3,"kind":"transmitting","payloadSHA256":"\(hashA)"},"previousStateSHA256":"\(hashB)","schemaVersion":1}
        """.utf8)
        XCTAssertThrowsError(try AcceptedJobStateJSON.decode(legacy))
        let migrated = try AcceptedJobStateJSON.migrateLegacyV1(
            legacy, acceptedTicketSHA256: hashB
        )
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.acceptanceID, "legacy-job")
        XCTAssertEqual(migrated.acceptedTicketSHA256, hashB)
        XCTAssertEqual(migrated.generation, 4)
        XCTAssertEqual(migrated.previousStateSHA256, hashB)
        XCTAssertEqual(
            migrated.phase,
            .transmitting(payloadSHA256: hashA, byteCount: 10, bytesAccepted: 3)
        )

        var noncanonical = legacy
        noncanonical.append(0x0a)
        XCTAssertThrowsError(try AcceptedJobStateJSON.migrateLegacyV1(
            noncanonical, acceptedTicketSHA256: hashB
        ))
        XCTAssertThrowsError(try AcceptedJobStateJSON.migrateLegacyV1(
            legacy, acceptedTicketSHA256: "bad"
        ))
    }

    func testMalformedUnknownOversizedAndNoncanonicalValuesFail() throws {
        let state = try AcceptedJobStateRecord.accepted(
            acceptanceID: "job-6", acceptedTicketSHA256: hashA
        )
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: AcceptedJobStateJSON.encode(state)) as? [String: Any])
        object["extra"] = "no"
        XCTAssertThrowsError(try AcceptedJobStateJSON.decode(JSONSerialization.data(withJSONObject: object)))
        XCTAssertThrowsError(try AcceptedJobStateJSON.decode(Data(repeating: 0, count: AcceptedJobStateJSON.maximumBytes + 1)))
        XCTAssertThrowsError(try AcceptedJobStateRecord(acceptanceID: "../job", acceptedTicketSHA256: hashA, generation: 1, previousStateSHA256: nil, phase: .accepted))
        XCTAssertThrowsError(try AcceptedJobStateRecord(acceptanceID: "job", acceptedTicketSHA256: hashA, generation: 1, previousStateSHA256: hashA, phase: .accepted))
        XCTAssertThrowsError(try AcceptedJobStateRecord(acceptanceID: "job", acceptedTicketSHA256: hashA, generation: 2, previousStateSHA256: hashA, phase: .accepted))
        XCTAssertThrowsError(try AcceptedJobStateRecord(acceptanceID: "job", acceptedTicketSHA256: "bad", generation: 1, previousStateSHA256: nil, phase: .accepted))
    }
}
