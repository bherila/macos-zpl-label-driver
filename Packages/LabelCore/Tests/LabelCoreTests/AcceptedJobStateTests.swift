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

    /// A generation-2 record whose only questionable field is the progress
    /// count, so `invalidPayload` can only come from the payload bound.
    private func progressRecord(_ phase: AcceptedJobPhase) throws -> AcceptedJobStateRecord {
        try AcceptedJobStateRecord(
            acceptanceID: "bounded-job", acceptedTicketSHA256: hashA,
            generation: 2, previousStateSHA256: hashB, phase: phase
        )
    }

    /// Brackets `0...byteCount` from both sides. The transition rules in
    /// `allows` never see these values: construction is direct, so a refusal
    /// here is the payload bound and nothing else.
    func testAcceptedProgressBytesAreBracketedByTheDeclaredPayloadLength() throws {
        for accepted in [0, 1, 9, 10] {
            for phase in [
                AcceptedJobPhase.transmitting(payloadSHA256: hashA, byteCount: 10, bytesAccepted: accepted),
                .uncertain(payloadSHA256: hashA, byteCount: 10, bytesAccepted: accepted),
            ] {
                XCTAssertEqual(try progressRecord(phase).phase, phase)
            }
        }
        for accepted in [-1, 11, Int.min, Int.max] {
            for phase in [
                AcceptedJobPhase.transmitting(payloadSHA256: hashA, byteCount: 10, bytesAccepted: accepted),
                .uncertain(payloadSHA256: hashA, byteCount: 10, bytesAccepted: accepted),
            ] {
                XCTAssertThrowsError(try progressRecord(phase), "\(accepted)") {
                    XCTAssertEqual($0 as? AcceptedJobStateError, .invalidPayload, "\(accepted)")
                }
            }
        }
    }

    /// Canonical schema-2 bytes as a persisted store would hold them. Field
    /// order matches `JSONSerialization` with `.sortedKeys`.
    private func persistedTransmitting(bytesAccepted token: String) -> Data {
        Data("""
        {"acceptanceID":"persisted-job","acceptedTicketSHA256":"\(hashA)","generation":2,\
        "phase":{"byteCount":10,"bytesAccepted":\(token),"kind":"transmitting",\
        "payloadSHA256":"\(hashA)"},"previousStateSHA256":"\(hashB)","schemaVersion":2}
        """.utf8)
    }

    /// The persisted path is the one that matters: a state file on disk is
    /// untrusted input, so a progress count outside the payload must be
    /// refused by the decoder and not merely by a typed caller.
    func testPersistedProgressBytesOutsideThePayloadAreRefusedByTheDecoder() throws {
        for accepted in [0, 10] {
            XCTAssertEqual(
                try AcceptedJobStateJSON.decode(persistedTransmitting(bytesAccepted: "\(accepted)")).phase,
                .transmitting(payloadSHA256: hashA, byteCount: 10, bytesAccepted: accepted)
            )
        }
        for token in ["-1", "11", "-9223372036854775808", "9223372036854775807"] {
            XCTAssertThrowsError(try AcceptedJobStateJSON.decode(persistedTransmitting(bytesAccepted: token)), token) {
                XCTAssertEqual($0 as? AcceptedJobStateJSONError, .invalidValue, token)
            }
        }
    }

    /// The same bound on the legacy migration path, which reads schema-1
    /// bytes a previous release may already have written to disk.
    func testLegacyMigrationRefusesProgressBytesOutsideThePayload() throws {
        func legacy(_ token: String) -> Data {
            Data("""
            {"acceptanceID":"legacy-job","generation":4,"phase":{"byteCount":10,\
            "bytesAccepted":\(token),"kind":"transmitting","payloadSHA256":"\(hashA)"},\
            "previousStateSHA256":"\(hashB)","schemaVersion":1}
            """.utf8)
        }
        XCTAssertEqual(
            try AcceptedJobStateJSON.migrateLegacyV1(legacy("10"), acceptedTicketSHA256: hashB).phase,
            .transmitting(payloadSHA256: hashA, byteCount: 10, bytesAccepted: 10)
        )
        for token in ["-1", "11"] {
            XCTAssertThrowsError(try AcceptedJobStateJSON.migrateLegacyV1(
                legacy(token), acceptedTicketSHA256: hashB
            ), token) {
                XCTAssertEqual($0 as? AcceptedJobStateJSONError, .invalidValue, token)
            }
        }
    }
}
