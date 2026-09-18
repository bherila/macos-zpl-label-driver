import Foundation
import XCTest
@testable import LabelCore

final class AcceptedJobStateTests: XCTestCase {
    private let hashA = String(repeating: "a", count: 64)
    private let hashB = String(repeating: "b", count: 64)

    private func next(
        _ state: AcceptedJobStateRecord, _ phase: AcceptedJobPhase
    ) throws -> AcceptedJobStateRecord {
        try state.advanced(to: phase, previousStateSHA256: hashB)
    }

    func testCompleteLifecycleRetainsPayloadAndDistinguishesConfirmation() throws {
        var state = try AcceptedJobStateRecord.accepted(acceptanceID: "job-1")
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
        var state = try AcceptedJobStateRecord.accepted(acceptanceID: "job-2")
        state = try next(state, .prepared(payloadSHA256: hashA, byteCount: 10))
        state = try next(state, .waiting(payloadSHA256: hashA, byteCount: 10))
        state = try next(state, .transmitting(payloadSHA256: hashA, byteCount: 10, bytesAccepted: 8))
        XCTAssertThrowsError(try next(state, .transmitting(payloadSHA256: hashA, byteCount: 10, bytesAccepted: 2)))
        XCTAssertThrowsError(try next(state, .uncertain(payloadSHA256: hashB, byteCount: 10, bytesAccepted: 8)))
        XCTAssertThrowsError(try next(state, .transmitted(payloadSHA256: hashA, byteCount: 10)))
    }

    func testAmbiguityBeforeKnownBytesAndAfterTransmissionIsTerminal() throws {
        var waiting = try AcceptedJobStateRecord.accepted(acceptanceID: "job-3")
        waiting = try next(waiting, .prepared(payloadSHA256: hashA, byteCount: 10))
        waiting = try next(waiting, .waiting(payloadSHA256: hashA, byteCount: 10))
        let uncertain = try next(waiting, .uncertain(payloadSHA256: hashA, byteCount: 10, bytesAccepted: 0))
        XCTAssertThrowsError(try next(uncertain, .waiting(payloadSHA256: hashA, byteCount: 10)))
        XCTAssertThrowsError(try next(waiting, .uncertain(payloadSHA256: hashA, byteCount: 10, bytesAccepted: 1)))
    }

    func testPreTransmissionStagesCanFailOrCancel() throws {
        let accepted = try AcceptedJobStateRecord.accepted(acceptanceID: "job-4")
        XCTAssertEqual(try next(accepted, .cancelledBeforeTransmission).phase, .cancelledBeforeTransmission)
        var waiting = try next(accepted, .prepared(payloadSHA256: hashA, byteCount: 10))
        XCTAssertEqual(try next(waiting, .failedBeforeTransmission).phase, .failedBeforeTransmission)
        waiting = try next(waiting, .waiting(payloadSHA256: hashA, byteCount: 10))
        XCTAssertEqual(try next(waiting, .cancelledBeforeTransmission).phase, .cancelledBeforeTransmission)
        XCTAssertEqual(try next(waiting, .failedBeforeTransmission).phase, .failedBeforeTransmission)
    }

    func testCanonicalJSONRoundTripAndHistory() throws {
        var state = try AcceptedJobStateRecord.accepted(acceptanceID: "job-5")
        state = try next(state, .prepared(payloadSHA256: hashA, byteCount: 123))
        let bytes = try AcceptedJobStateJSON.encode(state)
        XCTAssertEqual(try AcceptedJobStateJSON.decode(bytes), state)
        XCTAssertEqual(try AcceptedJobStateJSON.encode(AcceptedJobStateJSON.decode(bytes)), bytes)
        XCTAssertEqual(state.previousStateSHA256, hashB)
    }

    func testMalformedUnknownOversizedAndNoncanonicalValuesFail() throws {
        let state = try AcceptedJobStateRecord.accepted(acceptanceID: "job-6")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: AcceptedJobStateJSON.encode(state)) as? [String: Any])
        object["extra"] = "no"
        XCTAssertThrowsError(try AcceptedJobStateJSON.decode(JSONSerialization.data(withJSONObject: object)))
        XCTAssertThrowsError(try AcceptedJobStateJSON.decode(Data(repeating: 0, count: AcceptedJobStateJSON.maximumBytes + 1)))
        XCTAssertThrowsError(try AcceptedJobStateRecord(acceptanceID: "../job", generation: 1, previousStateSHA256: nil, phase: .accepted))
        XCTAssertThrowsError(try AcceptedJobStateRecord(acceptanceID: "job", generation: 1, previousStateSHA256: hashA, phase: .accepted))
        XCTAssertThrowsError(try AcceptedJobStateRecord(acceptanceID: "job", generation: 2, previousStateSHA256: hashA, phase: .accepted))
    }
}
