import XCTest
@testable import LabelCore

final class BoundedDeliveryTests: XCTestCase {
    func testCompleteJobBindsExactOrderedBytesBeforeAnySinkEffect() throws {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 19)
        let outputs = [ResolvedOutputLabel(sourcePage: 2, regionID: "first"),
                       ResolvedOutputLabel(sourcePage: 1, regionID: "second")]
        let encoder = try ZPLPreparedLabelEncoder()
        let labels = try zip(outputs, [UInt8(0x80), UInt8(0x40)]).map { output, pixel in
            PreparedOutputLabel(output: output, prepared: try encoder.prepare(
                bitmap: MonochromeBitmap(width: 8, height: 1, bytes: [pixel]), profile: profile))
        }
        let job = try PreparedJobPayload(labels: labels, expectedOutputLabels: outputs,
            monochromeConversion: .textAndBarcodeThreshold(cutoff: 128))
        var tracker = try DeliveryTracker(preparedJob: job)
        try tracker.prepared()
        try tracker.waiting()
        var sink = RecordingSink()
        let substituted = labels[1].prepared.bytes + labels[0].prepared.bytes
        XCTAssertEqual(substituted.count, job.bytes.count)
        XCTAssertThrowsError(try BoundedDelivery.write(substituted, to: &sink, tracker: &tracker)) {
            XCTAssertEqual($0 as? DeliveryStateError, .payloadBindingMismatch)
        }
        XCTAssertEqual(sink.largestOffer, 0)
        XCTAssertTrue(sink.collected.isEmpty)
        XCTAssertEqual(tracker.receipt.state, .waiting)
        try BoundedDelivery.write(job.bytes, to: &sink, tracker: &tracker)
        XCTAssertEqual(sink.collected, job.bytes)
        XCTAssertEqual(tracker.receipt.profileSnapshot, job.profileSnapshot)
        XCTAssertEqual(tracker.receipt.state, .transmitted(bytesAccepted: job.bytes.count))
        XCTAssertFalse(tracker.receipt.mayRetryAutomatically)
    }

    struct RecordingSink: DeliveryByteSink {
        var collected = Data()
        var largestOffer = 0
        var failAfterFirstWrite = false
        mutating func write(_ bytes: Data) throws -> Int {
            largestOffer = max(largestOffer, bytes.count)
            if failAfterFirstWrite, !collected.isEmpty { throw TestFailure.stopped }
            let count = min(bytes.count, 49_153)
            collected.append(bytes.prefix(count))
            return count
        }
    }
    enum TestFailure: Error { case stopped }

    func testLargeBoundPayloadShortWritesUseBoundedBuffersWithoutReordering() throws {
        let payload = Data((0..<(1024 * 1024 + 7)).map { UInt8($0 % 251) })
        let profile = try PrinterProfile.gc420dUSBReference(revision: 7)
        let prepared = PreparedLabel(bytes: payload, profileSnapshot: JobProfileSnapshot(profile: profile),
            resolvedControls: try profile.resolveControls(job: .init()))
        var value = try DeliveryTracker(preparedLabel: prepared)
        try value.prepared()
        try value.waiting()
        var sink = RecordingSink()
        try BoundedDelivery.write(payload, to: &sink, tracker: &value)
        XCTAssertLessThanOrEqual(sink.largestOffer, 64 * 1024, "Short writes must not copy the remaining whole job")
        XCTAssertEqual(sink.collected, payload)
        XCTAssertEqual(value.receipt.state, .transmitted(bytesAccepted: payload.count))
        XCTAssertEqual(value.receipt.profileSnapshot, prepared.profileSnapshot)
        XCTAssertFalse(value.receipt.mayRetryAutomatically)

        var failed = try DeliveryTracker(preparedLabel: prepared)
        try failed.prepared()
        try failed.waiting()
        var failingSink = RecordingSink(failAfterFirstWrite: true)
        XCTAssertThrowsError(try BoundedDelivery.write(payload, to: &failingSink, tracker: &failed))
        XCTAssertLessThanOrEqual(failingSink.largestOffer, 64 * 1024)
        XCTAssertEqual(failingSink.collected, payload.prefix(49_153))
        XCTAssertEqual(failed.receipt.state, .uncertain(bytesAccepted: 49_153))
        XCTAssertFalse(failed.receipt.mayRetryAutomatically)
    }

    func testWriteCountCannotExceedOfferedWindowEvenWhenJobHasMoreBytes() throws {
        struct InvalidSink: DeliveryByteSink {
            mutating func write(_ bytes: Data) throws -> Int { bytes.count + 1 }
        }
        let payload = Data(repeating: 0, count: 128 * 1024)
        var value = try DeliveryTracker(expectedBytes: payload.count, profileRevision: 1)
        try value.prepared()
        try value.waiting()
        var sink = InvalidSink()
        XCTAssertThrowsError(try BoundedDelivery.write(payload, to: &sink, tracker: &value))
        XCTAssertEqual(value.receipt.state, .uncertain(bytesAccepted: 0), "Invalid accounting cannot prove that the transport wrote nothing")
        XCTAssertFalse(value.receipt.mayRetryAutomatically)
    }

    func testInvalidAccountingBeforeAndAfterKnownPrefixNeverAuthorizesReplay() throws {
        for answers in [[-1], [6], [2, -1], [2, 4]] {
            var value = try tracker()
            var sink = Sink(answers: answers)
            XCTAssertThrowsError(try BoundedDelivery.write(Data([1, 2, 3, 4, 5]), to: &sink, tracker: &value)) {
                XCTAssertEqual($0 as? BoundedDeliveryError, .invalidWriteCount)
            }
            XCTAssertEqual(value.receipt.state, .uncertain(bytesAccepted: answers.count == 1 ? 0 : 2))
            XCTAssertFalse(value.receipt.mayRetryAutomatically)
        }
    }

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
