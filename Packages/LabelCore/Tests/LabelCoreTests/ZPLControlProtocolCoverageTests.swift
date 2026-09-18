import XCTest
@testable import LabelCore

final class ZPLControlProtocolCoverageTests: XCTestCase {
    func testEveryDocumentedKindHasCitedRangeAndIndependentModelLimits() {
        let rows = ZPLControlProtocol.documentedControls
        XCTAssertEqual(Set(rows.keys), Set(ZPLDocumentedControl.Kind.allCases))
        let commands: [ZPLDocumentedControl.Kind: String] = [
            .printRate: "^PRp,s,b", .absoluteDarkness: "^MD0/~SD", .directThermal: "^MTD/^MTT",
            .thermalTransfer: "^MTD/^MTT", .gapTracking: "^MNY", .continuousTracking: "^MNN/^LL",
            .blackMarkTracking: "^MNM,offset", .printWidth: "^PW", .labelHome: "^LHx,y",
            .labelShiftLeft: "^LS", .labelTop: "^LT", .tearOff: "^MMT"]
        for kind in ZPLDocumentedControl.Kind.allCases {
            XCTAssertEqual(rows[kind]?.command, commands[kind])
            XCTAssertTrue(["R45", "R46"].contains(rows[kind]?.sourceID ?? ""))
            XCTAssertFalse(rows[kind]?.implementedRange.isEmpty ?? true)
            XCTAssertFalse(rows[kind]?.modelLimits.isEmpty ?? true)
            XCTAssertFalse(rows[kind]?.notes.isEmpty ?? true)
        }
        XCTAssertEqual(rows[.printWidth]?.implementedRange, "2...32000 dots")
        XCTAssertTrue(rows[.printWidth]?.notes.contains("implementation subset") ?? false)
    }

    func testAccessoryRowsDoNotWidenReferenceOrClaimVerifiedPersistence() {
        let rows = ZPLControlProtocol.qualifiedFinishingControls
        XCTAssertEqual(Set(rows.keys), Set([FinishingMode.tearOff, .cut, .peel, .rewind]))
        XCTAssertEqual(rows[.cut]?.command, "^MMC/^MMD/~JK")
        XCTAssertEqual(rows[.peel]?.command, "^MMP,N/^MMP")
        for row in rows.values { XCTAssertEqual(row.lifetime, .modelSpecificOrUnverified) }
        XCTAssertEqual(ZPLControlProtocol.gc420dBaseline.map(\.command), ["^PRp", "^MMT"])
        XCTAssertEqual(ZPLControlProtocol.gc420dBaseline.first?.implementedRange, "2/3/4 ips")
    }
}
