import XCTest
@testable import LabelCore

final class BoundedDeliveryTests: XCTestCase {
    struct Sink: DeliveryByteSink {
        var answers: [Int]
        mutating func write(_ bytes: Data) throws -> Int { answers.removeFirst() }
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
}
