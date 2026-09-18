import Foundation
import XCTest
@testable import LabelCore

final class LegacyHostStatusTests: XCTestCase {
    func response(first: String = "000,0,0,0123,007,0,0,0,000,0,0,0",
                  second: String = "000,0,0,0,0,2,0,0,00000042,1,003", opaque: String = "P@55") -> Data {
        Data(([first, second, opaque + ",1"].map { "\u{2}" + $0 + "\u{3}\r\n" }).joined().utf8)
    }

    func testExactDocumentedGrammarPreservesTypedObservationsAndDropsOpaqueData() throws {
        let value = try XCTUnwrap(snapshot(try LegacyHostStatusDecoder.decode(response(), support: .supported)))
        XCTAssertEqual(value.labelLengthDots, 123)
        XCTAssertEqual(value.formatsBuffered, 7)
        XCTAssertEqual(value.labelsRemainingInBatch, 42)
        XCTAssertEqual(value.graphicsStored, 3)
        XCTAssertEqual(value.reportedPrintMode, 50)
        XCTAssertTrue(value.staticRAMReportedPresent)
        XCTAssertTrue(value.flags.isEmpty)
        var text = ""
        dump([value], to: &text)
        XCTAssertFalse(text.contains("P@55"))
        XCTAssertTrue(Mirror(reflecting: value).children.isEmpty)
        XCTAssertEqual(String(describing: value), "LegacyHostStatusSnapshot(redacted)")
    }

    func testUnknownUnsupportedAndAbsentNeverManufactureZeroOrHealthy() throws {
        XCTAssertEqual(try LegacyHostStatusDecoder.decode(response()), .unavailable(.unverifiedSupport))
        XCTAssertEqual(try LegacyHostStatusDecoder.decode(response(), support: .unsupported), .unavailable(.unsupported))
        for missing: Data? in [nil, Data()] {
            XCTAssertEqual(try LegacyHostStatusDecoder.decode(missing, support: .supported), .unavailable(.missingResponse))
        }
        let oversized = Data(repeating: 0, count: 65537)
        XCTAssertEqual(try LegacyHostStatusDecoder.decode(oversized), .unavailable(.unverifiedSupport))
        XCTAssertThrowsError(try LegacyHostStatusDecoder.decode(oversized, support: .supported)) {
            XCTAssertEqual($0 as? LegacyHostStatusDecoder.Error, .responseTooLarge)
        }
    }

    func testEveryFlagMapsIndependentlyWithoutChangingInstalledCapabilities() throws {
        let all = response(first: "000,1,1,0123,007,1,1,1,000,1,1,1",
            second: "000,0,1,1,1,2,0,1,00000042,1,003")
        let value = try XCTUnwrap(snapshot(try LegacyHostStatusDecoder.decode(all, support: .supported)))
        XCTAssertEqual(value.flags.rawValue, 4095)
        let mappings: [(Int, Int, LegacyHostStatusFlags)] = [(0,1,.paperOut),(0,2,.paused),
            (0,5,.bufferFull),(0,6,.diagnosticMode),(0,7,.partialFormat),(0,9,.configurationRAMLost),
            (0,10,.underTemperature),(0,11,.overTemperature),(1,2,.headOpen),(1,3,.ribbonOut),
            (1,4,.thermalTransferSelected),(1,7,.peelLabelWaiting)]
        for (row, column, flag) in mappings {
            var fields = ["000,0,0,0123,007,0,0,0,000,0,0,0".components(separatedBy: ","),
                "000,0,0,0,0,2,0,0,00000042,1,003".components(separatedBy: ",")]
            fields[row][column] = "1"
            let single = try XCTUnwrap(snapshot(try LegacyHostStatusDecoder.decode(
                response(first: fields[0].joined(separator: ","), second: fields[1].joined(separator: ",")), support: .supported)))
            XCTAssertEqual(single.flags, flag)
        }
        let profile = try PrinterProfile.gc420dUSBReference()
        XCTAssertEqual(profile.capabilities.thermalTransfer.state, .unsupported)
        XCTAssertThrowsError(try profile.resolveControls(job: .init(thermalMethod: .thermalTransfer)))
    }

    func testEveryTruncationAndTrailingFrameFailsWithoutPartialSnapshot() throws {
        let bytes = response()
        XCTAssertEqual(bytes.count, 82)
        for length in 1..<bytes.count {
            XCTAssertThrowsError(try LegacyHostStatusDecoder.decode(bytes.prefix(length), support: .supported))
        }
        XCTAssertThrowsError(try LegacyHostStatusDecoder.decode(bytes + bytes, support: .supported))
        XCTAssertThrowsError(try LegacyHostStatusDecoder.decode(bytes + Data([0]), support: .supported))
    }

    func testFramingDigitsFlagsReservedValuesAndOpaqueControlsReject() throws {
        var variants: [Data] = []
        for index in [0,4,33,34,35,36,69,70,71,72,79,80,81] {
            var bytes = response()
            bytes[index] = 255
            variants.append(bytes)
        }
        variants += [response(first: "000,2,0,0123,007,0,0,0,000,0,0,0"),
            response(first: "000,0,0,0123,007,0,0,0,001,0,0,0"),
            response(second: "000,0,0,0,0,2,0,0,00000042,0,003"),
            response(second: "000,0,0,0,0,^,0,0,00000042,1,003"), response(opaque: "P\u{2}55")]
        for bytes in variants { XCTAssertThrowsError(try LegacyHostStatusDecoder.decode(bytes, support: .supported)) }
    }

    func testDiscardedFunctionSettingsStillRequireAnEightBitValue() throws {
        for settings in ["000", "255"] {
            XCTAssertNotNil(snapshot(try LegacyHostStatusDecoder.decode(
                response(second: settings + ",0,0,0,0,2,0,0,00000042,1,003"),
                support: .supported)))
        }
        for settings in ["256", "511", "999"] {
            XCTAssertThrowsError(try LegacyHostStatusDecoder.decode(
                response(second: settings + ",0,0,0,0,2,0,0,00000042,1,003"),
                support: .supported)) {
                XCTAssertEqual($0 as? LegacyHostStatusDecoder.Error, .malformedResponse)
            }
        }
    }

    func testZeroBatchObservationNeverConfirmsATransmittedJob() throws {
        var tracker = try DeliveryTracker(expectedBytes: 4, profileRevision: 1)
        try tracker.prepared(); try tracker.waiting()
        try tracker.acceptedByTransport(byteCount: 4); try tracker.transportFinished()
        let receipt = tracker.receipt
        let value = try XCTUnwrap(snapshot(try LegacyHostStatusDecoder.decode(
            response(second: "000,0,0,0,0,2,0,0,00000000,1,000"), support: .supported)))
        XCTAssertEqual(value.labelsRemainingInBatch, 0)
        XCTAssertEqual(tracker.receipt, receipt)
        XCTAssertEqual(tracker.receipt.state, .transmitted(bytesAccepted: 4))
        XCTAssertFalse(tracker.receipt.mayRetryAutomatically)
    }

    func snapshot(_ value: LegacyHostStatusObservation) -> LegacyHostStatusSnapshot? {
        if case let .observed(snapshot) = value { return snapshot }
        return nil
    }
}
