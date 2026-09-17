import XCTest
@testable import LabelCore

final class ZPLDocumentedControlEncoderTests: XCTestCase {
    private let limits = ZPLDocumentedControlLimits(
        printSpeedChoicesIps: [2, 3, 4], feedSpeedChoicesIps: [2, 4],
        backfeedSpeedChoicesIps: [2, 3], blackMarkOffsetDots: -50...50,
        maximumPrintWidthDots: 832, labelTopDots: -100...100)
    private var qualified: [ZPLDocumentedControl.Kind: CapabilityState] {
        Dictionary(uniqueKeysWithValues: ZPLDocumentedControl.Kind.allCases.map { ($0, .supported) })
    }

    func testExactExplicitSettingsAndOrder() throws {
        let controls: [ZPLDocumentedControl] = [
            .printRate(printIps: 3, feedIps: 4, backfeedIps: 2), .absoluteDarkness(7),
            .thermalMethod(.directThermal), .blackMarkTracking(offsetDots: -12),
            .printWidth(dots: 813), .labelHome(xDots: 9, yDots: 17),
            .labelShiftLeft(dots: -23), .labelTop(dots: 31), .tearOff]
        let bytes = try ZPLDocumentedControlEncoder().encode(controls, qualification: qualified, limits: limits)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self),
            "^PR3,4,2\n^MD0\n~SD07\n^MTD\n^MNM,-12\n^PW813\n^LH9,17\n^LS-23\n^LT31\n^MMT\n")
    }

    func testEveryKindRequiresExplicitSupport() throws {
        let controls: [ZPLDocumentedControl] = [
            .printRate(printIps: 3, feedIps: 4, backfeedIps: 2), .absoluteDarkness(0),
            .thermalMethod(.directThermal), .thermalMethod(.thermalTransfer), .gapTracking,
            .blackMarkTracking(offsetDots: 0), .labelHome(xDots: 0, yDots: 0),
            .labelShiftLeft(dots: 0), .labelTop(dots: 0), .printWidth(dots: 2), .tearOff]
        XCTAssertEqual(Set(controls.map(\.kind)), Set(ZPLDocumentedControl.Kind.allCases))
        for control in controls {
            for state in [CapabilityState.unknown, .unsupported] {
                XCTAssertThrowsError(try ZPLDocumentedControlEncoder().encode(
                    [control], qualification: [control.kind: state], limits: limits)) {
                    XCTAssertEqual($0 as? ZPLDocumentedControlEncoder.Error, .unavailable(control.kind))
                }
            }
            XCTAssertThrowsError(try ZPLDocumentedControlEncoder().encode([control], limits: limits))
        }
    }

    func testModelBoundsAndProtocolBoundsBothApply() throws {
        let controls: [ZPLDocumentedControl] = [
            .printRate(printIps: 3, feedIps: 3, backfeedIps: 2),
            .printRate(printIps: 3, feedIps: 4, backfeedIps: 4),
            .printRate(printIps: 5, feedIps: 4, backfeedIps: 2),
            .blackMarkTracking(offsetDots: 51), .labelTop(dots: -101), .printWidth(dots: 833),
            .absoluteDarkness(-1), .absoluteDarkness(31), .labelHome(xDots: -1, yDots: 0),
            .labelHome(xDots: 0, yDots: 32_001), .labelShiftLeft(dots: Int.min),
            .printWidth(dots: Int.max)]
        for control in controls {
            XCTAssertThrowsError(try ZPLDocumentedControlEncoder().encode(
                [control], qualification: qualified, limits: limits)) {
                XCTAssertEqual($0 as? ZPLDocumentedControlEncoder.Error, .invalidValue(control.kind))
            }
        }
        for control in [ZPLDocumentedControl.blackMarkTracking(offsetDots: 0),
                        .printWidth(dots: 2), .labelTop(dots: 0),
                        .printRate(printIps: 3, feedIps: 4, backfeedIps: 2)] {
            XCTAssertThrowsError(try ZPLDocumentedControlEncoder().encode([control], qualification: qualified))
        }
        let overbroad = ZPLDocumentedControlLimits(printSpeedChoicesIps: [14],
            feedSpeedChoicesIps: [14], backfeedSpeedChoicesIps: [14],
            blackMarkOffsetDots: Int.min...Int.max, labelTopDots: Int.min...Int.max)
        for control in [ZPLDocumentedControl.printRate(printIps: 14, feedIps: 14, backfeedIps: 14),
                        .blackMarkTracking(offsetDots: -76), .labelTop(dots: 121)] {
            XCTAssertThrowsError(try ZPLDocumentedControlEncoder().encode(
                [control], qualification: qualified, limits: overbroad))
        }
    }

    func testConflictsDuplicatesAndLimitsFailWithoutReturnedFragment() throws {
        let encoder = try ZPLDocumentedControlEncoder()
        for controls in [[ZPLDocumentedControl.tearOff, .tearOff],
                         [.thermalMethod(.directThermal), .thermalMethod(.thermalTransfer)],
                         [.gapTracking, .blackMarkTracking(offsetDots: 0)]] {
            XCTAssertThrowsError(try encoder.encode(controls, qualification: qualified, limits: limits))
        }
        XCTAssertThrowsError(try encoder.encode(Array(repeating: .tearOff, count: 12), qualification: qualified))
        XCTAssertThrowsError(try ZPLDocumentedControlEncoder(maximumOutputBytes: 0))
        XCTAssertThrowsError(try ZPLDocumentedControlEncoder(maximumOutputBytes: 65_537))
        XCTAssertThrowsError(try ZPLDocumentedControlEncoder(maximumOutputBytes: 4).encode(
            [.tearOff], qualification: qualified))
        XCTAssertEqual(try ZPLDocumentedControlEncoder(maximumOutputBytes: 5).encode(
            [.tearOff], qualification: qualified), Data("^MMT\n".utf8))
        XCTAssertEqual(try encoder.encode([]), Data())
    }

    func testAlternateDarknessAndThermalMappingHaveNoPersistentOrCopyCommands() throws {
        for value in [0, 9, 10, 30] {
            let bytes = try ZPLDocumentedControlEncoder().encode(
                [.absoluteDarkness(value), .thermalMethod(.thermalTransfer), .gapTracking], qualification: qualified)
            let text = String(decoding: bytes, as: UTF8.self)
            XCTAssertEqual(text, "^MD0\n~SD\(value < 10 ? "0" : "")\(value)\n^MTT\n^MNY\n")
            for forbidden in ["^JU", "~JC", "~JA", "^PQ", "^MMC", "^MMP", "^MNA", "^MNV"] {
                XCTAssertFalse(text.contains(forbidden))
            }
        }
        let ordinary = try PrinterProfile.gc420dUSBReference()
        XCTAssertThrowsError(try ordinary.resolveControls(job: .init(darkness: 7)))
        XCTAssertThrowsError(try ordinary.resolveControls(job: .init(tracking: .gap)))
        XCTAssertThrowsError(try ordinary.resolveControls(job: .init(thermalMethod: .thermalTransfer)))
    }
}
