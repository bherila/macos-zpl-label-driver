import XCTest
@testable import LabelCore

final class DeliveryStateTests: XCTestCase {
    func testSuccessfulTransmissionIsNotPhysicalConfirmation() throws {
        var tracker = try DeliveryTracker(expectedBytes: 10, profileRevision: 3)
        try tracker.prepared(); try tracker.waiting(); try tracker.acceptedByTransport(byteCount: 10); try tracker.transportFinished()
        XCTAssertEqual(tracker.receipt.state, .transmitted(bytesAccepted: 10))
        XCTAssertFalse(tracker.receipt.mayRetryAutomatically)
        try tracker.deviceConfirmed()
        XCTAssertEqual(tracker.receipt.state, .deviceConfirmed)
    }

    func testPartialFailureIsUncertainAndCannotAutoRetry() throws {
        var tracker = try DeliveryTracker(expectedBytes: 10, profileRevision: 3)
        try tracker.prepared(); try tracker.waiting(); try tracker.acceptedByTransport(byteCount: 4); try tracker.transportBecameAmbiguous()
        XCTAssertEqual(tracker.receipt.state, .uncertain(bytesAccepted: 4))
        XCTAssertThrowsError(try tracker.requireExplicitRetryReview())
    }

    func testOnlyPreTransmissionFailureMayAutoRetry() throws {
        var tracker = try DeliveryTracker(expectedBytes: 10, profileRevision: 3)
        try tracker.prepared(); try tracker.waiting(); try tracker.failedOrCancelledBeforeTransmission(cancelled: false)
        XCTAssertTrue(tracker.receipt.mayRetryAutomatically)
        XCTAssertNoThrow(try tracker.requireExplicitRetryReview())
    }

    func testInvalidTransitionsAndByteCountsFail() throws {
        var tracker = try DeliveryTracker(expectedBytes: 10, profileRevision: 3)
        XCTAssertThrowsError(try tracker.waiting())
        try tracker.prepared(); try tracker.waiting()
        XCTAssertThrowsError(try tracker.acceptedByTransport(byteCount: 11))
        XCTAssertThrowsError(try tracker.transportFinished())
    }
}
