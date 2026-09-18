import XCTest
@testable import LabelCore

final class BoundedDeliveryTests: XCTestCase {
    struct Sink: DeliveryByteSink {
        var answers: [Int]
        var calls = 0
        mutating func write(_ bytes: Data) throws -> Int { calls += 1; return answers.removeFirst() }
    }
    func tracker() throws -> DeliveryTracker { var value = try DeliveryTracker(expectedBytes: 5, profileRevision: 1); try value.prepared(); try value.waiting(); return value }
    func testShortWritesBecomeTransmitted() throws {
        var value = try tracker(); var sink = Sink(answers: [2, 2, 1])
        try BoundedDelivery.write(Data([1, 2, 3, 4, 5]), to: &sink, tracker: &value)
        XCTAssertEqual(value.receipt.state, .transmitted(bytesAccepted: 5))
    }
    func testZeroWriteBeforeAnyByteIsRetryableFailure() throws {
        var value = try tracker(); var sink = Sink(answers: [0])
        XCTAssertThrowsError(try BoundedDelivery.write(Data([1, 2, 3, 4, 5]), to: &sink, tracker: &value))
        XCTAssertEqual(value.receipt.state, .failedBeforeTransmission)
    }
    func testZeroWriteAfterPartialByteIsUncertain() throws {
        var value = try tracker(); var sink = Sink(answers: [2, 0])
        XCTAssertThrowsError(try BoundedDelivery.write(Data([1, 2, 3, 4, 5]), to: &sink, tracker: &value))
        XCTAssertEqual(value.receipt.state, .uncertain(bytesAccepted: 2))
    }
    func testInvalidInitialStatesHaveNoSinkSideEffects() throws {
        let payload = Data([1, 2, 3, 4, 5])
        var unprepared = try DeliveryTracker(expectedBytes: 5, profileRevision: 1)
        var firstSink = Sink(answers: [5])
        XCTAssertThrowsError(try BoundedDelivery.write(payload, to: &firstSink, tracker: &unprepared))
        XCTAssertEqual(firstSink.calls, 0)
        XCTAssertEqual(unprepared.receipt.state, .accepted)

        var transmitted = try tracker()
        var successfulSink = Sink(answers: [5])
        try BoundedDelivery.write(payload, to: &successfulSink, tracker: &transmitted)
        var repeatedSink = Sink(answers: [5])
        XCTAssertThrowsError(try BoundedDelivery.write(payload, to: &repeatedSink, tracker: &transmitted))
        XCTAssertEqual(repeatedSink.calls, 0)
        XCTAssertEqual(transmitted.receipt.state, .transmitted(bytesAccepted: 5))
    }

    func testPreparedPayloadBindingIsValidatedBeforeWriting() throws {
        let expected = Data([1, 2, 3, 4, 5])
        let profile = try PrinterProfile.gc420dUSBReference()
        let snapshot = JobProfileSnapshot(profile: profile)
        let prepared = PreparedLabel(
            bytes: expected, profileSnapshot: snapshot,
            resolvedControls: try profile.resolveControls(job: .init())
        )
        var value = try DeliveryTracker(preparedLabel: prepared)
        try value.prepared()
        try value.waiting()
        var sink = Sink(answers: [5])

        XCTAssertThrowsError(
            try BoundedDelivery.write(Data([5, 4, 3, 2, 1]), to: &sink, tracker: &value)
        ) {
            XCTAssertEqual($0 as? DeliveryStateError, .payloadBindingMismatch)
        }
        XCTAssertEqual(sink.calls, 0)
        XCTAssertEqual(value.receipt.state, .waiting)
    }
}
