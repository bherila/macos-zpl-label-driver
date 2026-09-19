import Foundation
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

    /// Issue #103: the finishing mapping had a literal restated at every
    /// emitting site. These bytes are pinned here, in the package that executes
    /// on every host, so the production LabelMac route is covered by an executed
    /// test even where LabelMac itself cannot build.
    func testFinishingLiteralTableIsAuthoritativeForEveryEmittingRoute() {
        XCTAssertEqual(ZPLFinishingControlLiteral.allCases.map(\.rawValue),
            ["^MMT", "^MMC", "^MMD", "^MMP", "^MMP,N", "^MMR", "~JK"])
        for literal in ZPLFinishingControlLiteral.allCases {
            XCTAssertEqual(literal.line, Data((literal.rawValue + "\n").utf8))
            XCTAssertFalse(literal.rawValue.contains("\n"))
        }
        // Bounded offline inspection: ^MMC without scheduling authority, and no
        // trigger. It must never reach the delayed-cut route's literals.
        let offline: [(FinishingMode, String)] = [
            (.tearOff, "^MMT\n"), (.cut, "^MMC\n"), (.peel, "^MMP\n"), (.rewind, "^MMR\n")]
        for (mode, text) in offline {
            let literal = ZPLFinishingControlLiteral.offlineInspection(of: mode)
            XCTAssertEqual(literal.line, Data(text.utf8))
            XCTAssertNotEqual(literal, .delayedCut)
            XCTAssertNotEqual(literal, .delayedCutTrigger)
            XCTAssertNotEqual(literal, .peelExplicitNoPrepeel)
            XCTAssertTrue(ZPLFinishingControlLiteral.documented(of: mode).contains(literal))
        }
        // Production framed output, including the separate trigger file. The
        // cut route is the delayed-cut mode, never ^MMC.
        let framed: [(FinishingOutputQualification.ModePolicy, FinishingMode, String)] = [
            (.tearOff, .tearOff, "^MMT\n"), (.rewind, .rewind, "^MMR\n"),
            (.peelExplicitNoPrepeel, .peel, "^MMP,N\n"), (.peelPrepeelNotApplicable, .peel, "^MMP\n"),
            (.delayedCutSeparateFiles, .cut, "^MMD\n")]
        for (policy, mode, text) in framed {
            let literal = ZPLFinishingControlLiteral.framedMode(of: policy)
            XCTAssertEqual(literal.line, Data(text.utf8))
            XCTAssertNotEqual(literal, .immediateCut)
            XCTAssertTrue(ZPLFinishingControlLiteral.documented(of: mode).contains(literal))
        }
        XCTAssertEqual(ZPLFinishingControlLiteral.delayedCutTrigger.line, Data("~JK\n".utf8))
        // Every literal is reachable from the documented mapping, and every
        // coverage row restates none of them.
        var documented: Set<ZPLFinishingControlLiteral> = []
        for (mode, row) in ZPLControlProtocol.qualifiedFinishingControls {
            XCTAssertEqual(row.command, ZPLFinishingControlLiteral.documentedCommand(of: mode))
            documented.formUnion(ZPLFinishingControlLiteral.documented(of: mode))
        }
        XCTAssertEqual(documented, Set(ZPLFinishingControlLiteral.allCases))
        XCTAssertEqual(ZPLFinishingControlLiteral.documentedCommand(of: .cut), "^MMC/^MMD/~JK")
        XCTAssertEqual(ZPLFinishingControlLiteral.documentedCommand(of: .peel), "^MMP,N/^MMP")
    }

    /// A derived call site can be replaced by a restated literal without any
    /// byte-level test noticing until the two routes disagree, which is how the
    /// drift in issue #103 survived. This reads the emitting sources and fails
    /// on a re-hardcoded finishing literal, including the LabelMac source that
    /// does not build on this host.
    func testNoEmittingSourceRestatesAFinishingLiteral() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let emitters = [
            "Packages/LabelMac/Sources/LabelMac/FinishingFramedOutput.swift",
            "Packages/LabelCore/Sources/LabelCore/FinishingControlQualification.swift",
            "Packages/LabelCore/Sources/LabelCore/FinishingOutputQualification.swift",
            "Packages/LabelCore/Sources/LabelCore/ZPLControlEncoder.swift",
            "Packages/LabelCore/Sources/LabelCore/ZPLDocumentedControlEncoder.swift"]
        // A missing emitter is a failure, not a quiet skip.
        for path in emitters {
            let url = root.appendingPathComponent(path)
            let source = try String(decoding: Data(contentsOf: url), as: UTF8.self)
            for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                // Prose may cite a command; only code may not restate one.
                let code = line.components(separatedBy: "//").first ?? ""
                for literal in ZPLFinishingControlLiteral.allCases where code.contains(literal.rawValue) {
                    XCTFail("\(path):\(number + 1) restates \(literal.rawValue); "
                        + "derive it from ZPLFinishingControlLiteral instead")
                }
            }
        }
        // The table itself is the one place the literals are written down.
        let table = root.appendingPathComponent(
            "Packages/LabelCore/Sources/LabelCore/ZPLControlProtocolCoverage.swift")
        let text = try String(decoding: Data(contentsOf: table), as: UTF8.self)
        for literal in ZPLFinishingControlLiteral.allCases {
            XCTAssertTrue(text.contains("\"\(literal.rawValue)\""), "\(literal.rawValue) missing from the table")
        }
    }
}
