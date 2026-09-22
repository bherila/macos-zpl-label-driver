import Foundation
import XCTest
import LabelCore
@testable import LabelMac

/// Schema-v3 worker ticket emission, and the adversarial boundary coverage of
/// `OfflineConversionTicket.init(jsonData:)` that issues #93 and #101 record as
/// missing.
///
/// Two things live here, for one reason: the emitted ticket and the admitting
/// parser are the two ends of the same process boundary, and the ticket JSON is
/// attacker-influenceable input to the render worker's parent.
///
/// **Part A** closes #93 gap 1 at the byte level. `OfflineExtractionWorkerTests`
/// already asserts the *decoded* shape of both branches -- v2 keeps no margin
/// key, v3 carries four edges, and the emitted ticket round-trips its margins.
/// What was never asserted is that the zero-margin bytes are unchanged from the
/// established v2 form, which is the actual compatibility claim: a decoded
/// comparison passes even if key order, numeric spelling or an added field
/// changed the bytes a running worker would receive.
///
/// **Part B** is the boundary coverage #93 gap 2 and #101 ask for. It is
/// explicitly *not* a substitute for the human security review those issues
/// request; it records, as executable assertions, what this parser actually
/// does at its edges, including three places where what it does is wider than
/// what the issue text describes. Those are written down as findings, not
/// quietly fixed here -- widening or narrowing admission is not this slice's
/// job.
///
/// `OfflineConversionTicketErrorSurfaceTests` (#141) pins a different property:
/// that nothing but `TicketError` escapes, and that component domains keep
/// their own cases. This file assumes that property and probes the admission
/// decisions themselves.
final class WorkerTicketSchemaV3Tests: XCTestCase {

    // MARK: - Fixtures

    /// 20 mm x 10 mm stock at 1 dot/mm keeps every emitted number exact in
    /// binary, so a byte comparison tests the wire form and not float printing.
    private var stock: PhysicalSize {
        get throws { PhysicalSize(width: try Millimeters(20), height: try Millimeters(10)) }
    }

    private func canvas(_ size: PhysicalSize) throws -> DotCanvas {
        try DotCanvas(physicalSize: size,
            resolution: DotResolution(xDotsPerMillimeter: 1, yDotsPerMillimeter: 1))
    }

    /// Deliberately a second copy of the planner fixture rather than a shared
    /// helper: `OfflineExtractionWorkerTests` is cited by a live evidence
    /// record, and a byte change there would rebind that record for a reason
    /// that has nothing to do with the evidence it carries.
    private func plannedLabel(outputMargins: OutputMargins) throws -> PlannedExtractionLabel {
        let box = try PDFPageBox(originX: 0, originY: 0, width: 20, height: 10)
        let profile = try WorkflowProfile(
            schemaVersion: outputMargins == .zero ? 2 : 3, id: "worker-ticket-v3", revision: 4,
            outputStockID: "test-stock", outputStock: try stock, outputMargins: outputMargins,
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(uprightPhysicalSize: try box.effectivePhysicalSize()),
                disposition: .extract([try ExtractionRegion(
                    id: "selected", normalizedRect: try NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                    rotation: .degrees0, outputOrder: 0
                )])
            )]
        )
        return try ExtractionPlanner.plan(sourcePages: [box], profile: profile).outputLabels[0]
    }

    private func emitted(
        margins: OutputMargins,
        conversion: MonochromeConversion = .textAndBarcodeThreshold(cutoff: 128)
    ) throws -> Data {
        try OfflineExtractionWorker.ticketJSON(
            label: try plannedLabel(outputMargins: margins),
            canvas: try canvas(try stock), conversion: conversion)
    }

    // MARK: - Part A: what the worker puts on the wire (#93 gap 1)

    /// The v2 wire document as it shipped, byte for byte.
    ///
    /// This constant is the *historical* form, not a re-derivation of it. An
    /// expectation built by calling `JSONSerialization` with the same options
    /// the emitter uses would move with the emitter: a change in Foundation's
    /// floating-point spelling, key ordering or separators would shift both
    /// sides identically and the comparison would stay green while the bytes a
    /// running worker receives had changed. That is precisely the compatibility
    /// claim this pair of tests exists to make, so the constant has to be
    /// independent of the serializer under test.
    ///
    /// **If a test fails against this constant, the wire form changed.** Do not
    /// update the constant to match the emitter; that converts a detected
    /// regression into a silent one. Every value here is an integral `Double`
    /// or an `Int`, the one case every JSON serializer spells identically, so a
    /// failure means content or ordering moved rather than number printing.
    ///
    /// Fixture: 20 mm x 10 mm stock at 1 dot/mm, page 1, the whole page as one
    /// unrotated region, threshold 128.
    private static let goldenVersionTwo = """
    {"conversion":{"cutoff":128,"mode":"textAndBarcodeThreshold"},\
    "extraction":{"expectedSourceRect":{"height":10,"width":20,"x":0,"y":0},\
    "region":{"height":1,"width":1,"x":0,"y":0},"rotation":0},\
    "pageNumber":1,"physicalSize":{"heightMillimeters":10,"widthMillimeters":20},\
    "placementPolicy":"fit","resolution":{"xDotsPerMillimeter":1,"yDotsPerMillimeter":1},\
    "schemaVersion":2}
    """

    /// The same fixture with margins of 1 / 2 / 3 / 0.5 mm, also fixed bytes.
    /// `0.5` is exactly representable, so it too spells identically everywhere.
    private static let goldenVersionThree = """
    {"conversion":{"cutoff":128,"mode":"textAndBarcodeThreshold"},\
    "extraction":{"expectedSourceRect":{"height":10,"width":20,"x":0,"y":0},\
    "region":{"height":1,"width":1,"x":0,"y":0},"rotation":0},\
    "outputMargins":{"bottom":0.5,"left":1,"right":3,"top":2},\
    "pageNumber":1,"physicalSize":{"heightMillimeters":10,"widthMillimeters":20},\
    "placementPolicy":"fit","resolution":{"xDotsPerMillimeter":1,"yDotsPerMillimeter":1},\
    "schemaVersion":3}
    """

    /// A zero-margin plan emits the historical v2 bytes, unchanged.
    func testZeroMarginTicketIsTheByteIdenticalVersionTwoDocument() throws {
        let actual = try emitted(margins: .zero)
        let text = String(decoding: actual, as: UTF8.self)
        XCTAssertEqual(text, Self.goldenVersionTwo,
                       "the v2 wire form changed; do not edit the golden to match it")
        XCTAssertEqual(actual, Data(Self.goldenVersionTwo.utf8))
        XCTAssertFalse(text.contains("outputMargins"), "a zero-margin ticket must carry no margin key")
    }

    /// A non-zero margin emits the historical v3 bytes, which are the v2 bytes
    /// with the margin object inserted at its sorted position and the version
    /// bumped -- and nothing else moved. The relation is asserted between the
    /// two constants as well as against the emitter, so "nothing else moved" is
    /// stated explicitly rather than inherited from a shared serializer call.
    func testVersionThreeTicketIsTheVersionTwoBytesPlusTheMarginObject() throws {
        let margins = try OutputMargins(left: 1, top: 2, right: 3, bottom: 0.5)
        let text = String(decoding: try emitted(margins: margins), as: UTF8.self)
        XCTAssertEqual(text, Self.goldenVersionThree,
                       "the v3 wire form changed; do not edit the golden to match it")

        let inserted = Self.goldenVersionTwo
            .replacingOccurrences(
                of: ",\"pageNumber\":",
                with: ",\"outputMargins\":{\"bottom\":0.5,\"left\":1,\"right\":3,\"top\":2},\"pageNumber\":")
            .replacingOccurrences(of: "\"schemaVersion\":2", with: "\"schemaVersion\":3")
        XCTAssertEqual(Self.goldenVersionThree, inserted,
                       "the two goldens differ by more than the margin object and the version")
        XCTAssertEqual(text.utf8.count,
                       Self.goldenVersionTwo.utf8.count + 1 + "\"outputMargins\":".utf8.count
                           + "{\"bottom\":0.5,\"left\":1,\"right\":3,\"top\":2}".utf8.count)
    }

    /// The configured margins reach the wire as themselves. A value that is not
    /// exactly representable in binary is included so the assertion covers the
    /// emitted spelling round-tripping back to the same `Double`, not just the
    /// tidy cases.
    func testVersionThreeTicketCarriesTheConfiguredMarginsExactly() throws {
        let margins = try OutputMargins(left: 0.1, top: 2, right: 3, bottom: 0.5)
        let wire = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try emitted(margins: margins)) as? [String: Any])
        XCTAssertEqual(wire["schemaVersion"] as? Int, 3)
        let edges = try XCTUnwrap(wire["outputMargins"] as? [String: Double])
        XCTAssertEqual(edges["left"], 0.1)
        XCTAssertEqual(edges["top"], 2)
        XCTAssertEqual(edges["right"], 3)
        XCTAssertEqual(edges["bottom"], 0.5)
        XCTAssertEqual(Set(edges.keys), ["left", "top", "right", "bottom"])
    }

    /// Every field of the emitted v3 document survives the parser that admits
    /// it, not only the margins. The two ends of the process boundary are
    /// checked against each other across the whole ticket, both conversions and
    /// both schema branches.
    func testEmittedTicketRoundTripsEveryFieldThroughTheAdmittingParser() throws {
        let cases: [(OutputMargins, MonochromeConversion, OfflineConversionTicket.Conversion, Int)] = [
            (.zero, .textAndBarcodeThreshold(cutoff: 128), .textAndBarcodeThreshold(cutoff: 128), 2),
            (.zero, .photographicOrderedDither4x4, .photographicOrderedDither4x4, 2),
            (try OutputMargins(left: 0.1, top: 2, right: 3, bottom: 0.5),
             .textAndBarcodeThreshold(cutoff: 0), .textAndBarcodeThreshold(cutoff: 0), 3),
            (try OutputMargins(left: 0, top: 0, right: 0, bottom: 1),
             .photographicOrderedDither4x4, .photographicOrderedDither4x4, 3),
        ]
        for (margins, coreConversion, ticketConversion, version) in cases {
            let label = try plannedLabel(outputMargins: margins)
            let data = try emitted(margins: margins, conversion: coreConversion)
            let admitted = try OfflineConversionTicket(jsonData: data)
            XCTAssertEqual(admitted.schemaVersion, version)
            XCTAssertEqual(admitted.pageNumber, label.sourcePage)
            XCTAssertEqual(admitted.physicalSize, try stock)
            XCTAssertEqual(admitted.resolution,
                           try DotResolution(xDotsPerMillimeter: 1, yDotsPerMillimeter: 1))
            XCTAssertEqual(admitted.conversion, ticketConversion)
            XCTAssertEqual(admitted.placementPolicy, .fit)
            XCTAssertEqual(admitted.outputMargins, margins)
            XCTAssertEqual(admitted.sourceRegion, label.normalizedRect)
            XCTAssertEqual(admitted.expectedSourceRect, label.sourceRect)
            XCTAssertEqual(admitted.regionRotation, label.rotation)
        }
    }

    // MARK: - Part B: the admitting parser's edges (#93 gap 2, #101)

    /// A v3 document that parses, as the base every hostile sample below is
    /// mutated from. Written as text rather than built by the emitter so a
    /// sample can differ from it by exact bytes -- a duplicate key or a raw
    /// numeric literal cannot be expressed through `JSONSerialization` at all.
    /// Keys are in sorted order, matching what the worker emits.
    private static let baseVersionThree = """
    {"conversion":{"cutoff":128,"mode":"textAndBarcodeThreshold"},\
    "extraction":{"expectedSourceRect":{"height":100,"width":100,"x":0,"y":0},\
    "region":{"height":1,"width":1,"x":0,"y":0},"rotation":0},\
    "outputMargins":{"bottom":1,"left":1,"right":1,"top":1},\
    "pageNumber":1,"physicalSize":{"heightMillimeters":10,"widthMillimeters":20},\
    "placementPolicy":"fit","resolution":{"xDotsPerMillimeter":8,"yDotsPerMillimeter":8},\
    "schemaVersion":3}
    """

    private static let marginObject = "{\"bottom\":1,\"left\":1,\"right\":1,\"top\":1}"

    /// A full-page v1 document that parses. Version 1 forbids an extraction
    /// region, so this is not the v3 base with its version rewritten -- a v1
    /// ticket still carrying `extraction` is refused by the schema-v1 rule
    /// whatever the margin guard does, which would let a margin-guard
    /// regression pass unnoticed. Here the margin object is the only thing that
    /// can be added to make it invalid.
    private static let baseVersionOne = """
    {"conversion":{"cutoff":128,"mode":"textAndBarcodeThreshold"},\
    "pageNumber":1,"physicalSize":{"heightMillimeters":10,"widthMillimeters":20},\
    "placementPolicy":"fit","resolution":{"xDotsPerMillimeter":8,"yDotsPerMillimeter":8},\
    "schemaVersion":1}
    """

    private func sample(_ find: String, _ replacement: String) -> Data {
        XCTAssertTrue(Self.baseVersionThree.contains(find), "sample base lost: \(find)")
        return Data(Self.baseVersionThree
            .replacingOccurrences(of: find, with: replacement).utf8)
    }

    private func refusal(_ data: Data, _ name: String,
                         file: StaticString = #filePath, line: UInt = #line)
        -> OfflineConversionTicket.TicketError? {
        var thrown: OfflineConversionTicket.TicketError?
        XCTAssertThrowsError(try OfflineConversionTicket(jsonData: data), name,
                             file: file, line: line) { error in
            guard let ticketError = error as? OfflineConversionTicket.TicketError else {
                return XCTFail("\(name): \(type(of: error)) crossed the boundary: \(error)",
                               file: file, line: line)
            }
            if case let .unclassifiedComponentFailure(domain) = ticketError {
                XCTFail("\(name): unmapped component domain \(domain)", file: file, line: line)
            }
            thrown = ticketError
        }
        return thrown
    }

    func testTheSampleBaseIsAdmitted() throws {
        let admitted = try OfflineConversionTicket(jsonData: Data(Self.baseVersionThree.utf8))
        XCTAssertEqual(admitted.schemaVersion, 3)
        XCTAssertEqual(admitted.outputMargins, try OutputMargins(left: 1, top: 1, right: 1, bottom: 1))
        XCTAssertEqual(admitted.pageNumber, 1)
    }

    /// Margins that leave no printable area are refused on either axis, at the
    /// exact boundary as well as beyond it: the guard is `> 0`, so consuming
    /// the stock exactly is already a refusal.
    func testMarginsThatConsumeThePrintableAreaAreRefusedOnBothAxes() {
        let cases = [
            ("width consumed exactly", "{\"bottom\":0,\"left\":10,\"right\":10,\"top\":0}"),
            ("height consumed exactly", "{\"bottom\":5,\"left\":0,\"right\":0,\"top\":5}"),
            ("width exceeded", "{\"bottom\":0,\"left\":20,\"right\":20,\"top\":0}"),
            ("height exceeded", "{\"bottom\":40,\"left\":0,\"right\":0,\"top\":40}"),
            ("one edge alone consumes the width", "{\"bottom\":0,\"left\":20,\"right\":0,\"top\":0}"),
        ]
        for (name, object) in cases {
            XCTAssertEqual(refusal(sample(Self.marginObject, object), name), .malformedJSON, name)
        }
    }

    /// FINDING for the #93 / #101 human pass, recorded rather than fixed.
    ///
    /// "Must leave a positive printable area" is enforced in millimeters, not
    /// in dots. On this 20 mm stock at 8 dots/mm, margins of 9.99 mm a side
    /// leave 0.02 mm -- about a sixth of one dot -- and the ticket is admitted.
    /// Whether the renderer downstream refuses such a region is a separate
    /// question this test does not answer, and cannot answer here, because
    /// `QuartzPDFRenderer` needs Core Graphics.
    ///
    /// This is the same class of gap as #101's `c2dd232` ("margins round to
    /// dots independently and can inset the whole canvas"), which was fixed in
    /// the editor's admission path. The ticket boundary does not carry that
    /// check. Asserted as-is so the behaviour is visible and any deliberate
    /// change to it is a visible test change.
    func testSubDotPrintableRemainderIsAdmittedBecauseTheGuardIsInMillimeters() throws {
        let admitted = try OfflineConversionTicket(
            jsonData: sample(Self.marginObject, "{\"bottom\":0,\"left\":9.99,\"right\":9.99,\"top\":0}"))
        let remainder = admitted.physicalSize.width.value
            - admitted.outputMargins.left - admitted.outputMargins.right
        XCTAssertGreaterThan(remainder, 0)
        XCTAssertLessThan(remainder * admitted.resolution.xDotsPerMillimeter, 1,
                          "fixture no longer leaves a sub-dot remainder")
    }

    /// Every edge is checked for sign, not just the first one, and a negative
    /// edge is refused by the geometry type rather than clamped to zero.
    func testANegativeValueOnAnyEdgeIsRefusedWithTheGeometryCause() {
        for edge in ["left", "top", "right", "bottom"] {
            let object = Self.marginObject.replacingOccurrences(of: "\"\(edge)\":1", with: "\"\(edge)\":-0.5")
            XCTAssertEqual(refusal(sample(Self.marginObject, object), "negative \(edge)"),
                           .invalidPagePlacement(.invalidMargins), edge)
        }
    }

    /// Recorded behaviour, not a defect: `-0.0` is finite and `>= 0`, and
    /// compares equal to `0.0`, so a v3 ticket spelled with negative zeroes is
    /// admitted and is the zero-margin ticket. Pinned because "negative margins
    /// are rejected" could otherwise be read as covering this spelling.
    func testNegativeZeroMarginsAreAdmittedAndEqualTheZeroMargins() throws {
        let admitted = try OfflineConversionTicket(jsonData: sample(
            Self.marginObject, "{\"bottom\":-0.0,\"left\":-0.0,\"right\":-0.0,\"top\":-0.0}"))
        XCTAssertEqual(admitted.outputMargins, .zero)
    }

    /// The margin object's key set is exact. This is the only place in the
    /// ticket where an unknown key is refused (see the unknown-field test
    /// below), so the strictness is worth pinning where it exists.
    func testTheMarginObjectShapeIsStrict() {
        let cases = [
            ("extra key", Self.marginObject.replacingOccurrences(
                of: "{\"bottom\":1", with: "{\"bottom\":1,\"extra\":0")),
            ("renamed key", Self.marginObject.replacingOccurrences(
                of: "\"left\"", with: "\"lft\"")),
            ("missing key", "{\"bottom\":1,\"left\":1,\"right\":1}"),
            ("object as array", "[1,1,1,1]"),
            ("object as null", "null"),
            ("edge as string", "{\"bottom\":1,\"left\":\"1\",\"right\":1,\"top\":1}"),
            ("edge as bool", "{\"bottom\":1,\"left\":true,\"right\":1,\"top\":1}"),
            ("duplicate edge", "{\"bottom\":1,\"left\":1,\"left\":2,\"right\":1,\"top\":1}"),
        ]
        for (name, object) in cases {
            XCTAssertEqual(refusal(sample(Self.marginObject, object), name), .malformedJSON, name)
        }
    }

    /// A margin on a v2 profile is refused on both routes into the type: the
    /// JSON initializer refuses the field's presence, and the designated
    /// initializer refuses a non-zero value the JSON path cannot express.
    func testNonZeroMarginsOnAVersionTwoTicketAreRefusedOnBothRoutes() throws {
        XCTAssertEqual(refusal(sample("\"schemaVersion\":3", "\"schemaVersion\":2"), "v2 with margins"),
                       .malformedJSON)

        // The v1 route needs a document whose *only* fault is the margin
        // object. Rewriting the v3 base's version leaves its `extraction`
        // object in place, and a v1 ticket carrying an extraction region is
        // refused by the schema-v1 rule on its own -- so that sample stays
        // green with the margin guard deleted and proves nothing. These two
        // assertions differ by exactly the margin object.
        let versionOne = try OfflineConversionTicket(jsonData: Data(Self.baseVersionOne.utf8))
        XCTAssertEqual(versionOne.schemaVersion, 1)
        XCTAssertEqual(versionOne.outputMargins, .zero)
        XCTAssertNil(versionOne.sourceRegion)
        let versionOneWithMargins = Data(Self.baseVersionOne.replacingOccurrences(
            of: "\"pageNumber\":1,",
            with: "\"outputMargins\":\(Self.marginObject),\"pageNumber\":1,").utf8)
        XCTAssertEqual(refusal(versionOneWithMargins, "v1 whose only fault is the margin object"),
                       .malformedJSON)
        // The direct route: no JSON document produces this, so it needs the
        // designated initializer to be covered at all.
        XCTAssertThrowsError(try OfflineConversionTicket(
            schemaVersion: 2, pageNumber: 1, physicalSize: try stock,
            resolution: try DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8),
            conversion: .textAndBarcodeThreshold(cutoff: 128), placementPolicy: .fit,
            outputMargins: try OutputMargins(left: 1, top: 0, right: 0, bottom: 0),
            sourceRegion: try NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            expectedSourceRect: try PDFSourceRect.validated(x: 0, y: 0, width: 100, height: 100),
            regionRotation: .degrees0)) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError, .malformedJSON)
        }
        // A v3 document that drops the field is refused rather than defaulted,
        // so a stripped margin object cannot silently become a zero margin.
        XCTAssertEqual(refusal(sample("\"outputMargins\":\(Self.marginObject),", ""), "v3 without margins"),
                       .malformedJSON)
    }

    /// An unknown or future schema version is refused carrying its own value,
    /// so a caller can tell "version I do not know" from "document I cannot
    /// parse". Both ends of the accepted range are covered.
    func testUnsupportedSchemaVersionsAreRefusedCarryingTheirValue() {
        for version in [0, -1, 4, 97] {
            XCTAssertEqual(
                refusal(sample("\"schemaVersion\":3", "\"schemaVersion\":\(version)"), "version \(version)"),
                .unsupportedSchemaVersion(version), "version \(version)")
        }
    }

    /// Integer fields are admitted from the exact token, before Foundation
    /// numeric coercion, so a spelling that is not an exact integer is refused
    /// rather than rounded into range. Each of these is decided by
    /// `TokenPreservingJSON` and `ExactJSONInteger` in `LabelCore`, ahead of
    /// any `Decodable` work.
    func testIntegerFieldsRefuseInexactAndOutOfRangeSpellings() {
        let cases = [
            ("fractional page", "\"pageNumber\":1", "\"pageNumber\":1.5"),
            ("leading zero page", "\"pageNumber\":1", "\"pageNumber\":01"),
            ("page past Int64", "\"pageNumber\":1", "\"pageNumber\":9223372036854775808"),
            ("page exponent past Int64", "\"pageNumber\":1", "\"pageNumber\":1e1000"),
            ("fractional version", "\"schemaVersion\":3", "\"schemaVersion\":3.5"),
            ("version exponent past Int64", "\"schemaVersion\":3", "\"schemaVersion\":1e1000"),
            ("fractional cutoff", "\"cutoff\":128", "\"cutoff\":128.5"),
            ("fractional rotation", "\"rotation\":0", "\"rotation\":0.5"),
        ]
        for (name, find, replacement) in cases {
            XCTAssertEqual(refusal(sample(find, replacement), name), .malformedJSON, name)
        }
    }

    /// The other half of exact-integer admission: a spelling that *is* exactly
    /// an integer either arrives as that integer or is refused outright. What
    /// must never happen is a third outcome -- a different integer, reached by
    /// truncation or floating-point rounding.
    ///
    /// Written as a disjunction on purpose. Whether Foundation's decoder admits
    /// `1e3` into an `Int` is a Foundation detail, and this suite compiles on a
    /// macOS the assertion was not observed on; the property under test is the
    /// absence of a silently different value, not which of the two routes runs.
    func testExactIntegerSpellingsNeverBecomeADifferentInteger() {
        let cases: [(String, String, String, Int)] = [
            ("page as 1.0", "\"pageNumber\":1", "\"pageNumber\":1.0", 1),
            ("page as 1e3", "\"pageNumber\":1", "\"pageNumber\":1e3", 1000),
            ("page as 10e2", "\"pageNumber\":1", "\"pageNumber\":10e2", 1000),
        ]
        for (name, find, replacement, expected) in cases {
            do {
                let admitted = try OfflineConversionTicket(jsonData: sample(find, replacement))
                XCTAssertEqual(admitted.pageNumber, expected, name)
            } catch let error as OfflineConversionTicket.TicketError {
                XCTAssertEqual(error, .malformedJSON, name)
            } catch {
                XCTFail("\(name): \(type(of: error)) crossed the boundary: \(error)")
            }
        }
        // The same property on the threshold, where the admitted range matters.
        do {
            let admitted = try OfflineConversionTicket(
                jsonData: sample("\"cutoff\":128", "\"cutoff\":1.28e2"))
            XCTAssertEqual(admitted.conversion, .textAndBarcodeThreshold(cutoff: 128))
        } catch let error as OfflineConversionTicket.TicketError {
            XCTAssertEqual(error, .malformedJSON)
        } catch {
            XCTFail("cutoff 1.28e2: \(type(of: error)) crossed the boundary: \(error)")
        }
    }

    /// Missing, null and wrong-typed fields are refused, each with the case the
    /// initializer specifies for that field rather than a single catch-all.
    func testMissingNullAndWrongTypedFieldsAreRefusedWithTheirOwnCase() {
        let cases: [(String, Data, OfflineConversionTicket.TicketError)] = [
            ("version missing", sample(",\"schemaVersion\":3", ""), .malformedJSON),
            ("version null", sample("\"schemaVersion\":3", "\"schemaVersion\":null"), .malformedJSON),
            ("version as string", sample("\"schemaVersion\":3", "\"schemaVersion\":\"3\""), .malformedJSON),
            ("page missing", sample("\"pageNumber\":1,", ""), .malformedJSON),
            ("page null", sample("\"pageNumber\":1", "\"pageNumber\":null"), .malformedJSON),
            ("page as string", sample("\"pageNumber\":1", "\"pageNumber\":\"1\""), .malformedJSON),
            ("page zero", sample("\"pageNumber\":1", "\"pageNumber\":0"), .invalidPageNumber),
            ("page negative", sample("\"pageNumber\":1", "\"pageNumber\":-1"), .invalidPageNumber),
            ("size missing",
             sample(",\"physicalSize\":{\"heightMillimeters\":10,\"widthMillimeters\":20}", ""),
             .malformedJSON),
            ("width as string",
             sample("\"widthMillimeters\":20", "\"widthMillimeters\":\"20\""), .malformedJSON),
            ("width zero",
             sample("\"widthMillimeters\":20", "\"widthMillimeters\":0"),
             .invalidPhysicalGeometry(.nonPositiveLength)),
            ("resolution missing",
             sample(",\"resolution\":{\"xDotsPerMillimeter\":8,\"yDotsPerMillimeter\":8}", ""),
             .malformedJSON),
            ("resolution zero",
             sample("\"xDotsPerMillimeter\":8", "\"xDotsPerMillimeter\":0"),
             .invalidPhysicalGeometry(.nonPositiveResolution)),
            ("conversion missing",
             sample("\"conversion\":{\"cutoff\":128,\"mode\":\"textAndBarcodeThreshold\"},", ""),
             .malformedJSON),
            ("mode unknown", sample("\"mode\":\"textAndBarcodeThreshold\"", "\"mode\":\"whatever\""),
             .malformedJSON),
            ("cutoff null", sample("\"cutoff\":128", "\"cutoff\":null"), .invalidThreshold),
            ("cutoff above range", sample("\"cutoff\":128", "\"cutoff\":256"), .invalidThreshold),
            ("cutoff below range", sample("\"cutoff\":128", "\"cutoff\":-1"), .invalidThreshold),
            ("dither carrying a cutoff",
             sample("\"mode\":\"textAndBarcodeThreshold\"", "\"mode\":\"photographicOrderedDither4x4\""),
             .malformedJSON),
            ("placement unknown", sample("\"placementPolicy\":\"fit\"", "\"placementPolicy\":\"stretch\""),
             .malformedJSON),
            ("placement actualSize at v3",
             sample("\"placementPolicy\":\"fit\"", "\"placementPolicy\":\"actualSize\""), .malformedJSON),
            ("extraction missing",
             sample("\"extraction\":{\"expectedSourceRect\":{\"height\":100,\"width\":100,\"x\":0,\"y\":0},"
                    + "\"region\":{\"height\":1,\"width\":1,\"x\":0,\"y\":0},\"rotation\":0},", ""),
             .malformedJSON),
            ("rotation not on the dial", sample("\"rotation\":0", "\"rotation\":1"), .malformedJSON),
            ("rotation negative", sample("\"rotation\":0", "\"rotation\":-90"), .malformedJSON),
            ("rotation full turn", sample("\"rotation\":0", "\"rotation\":360"), .malformedJSON),
            ("region outside the page",
             sample("\"region\":{\"height\":1,\"width\":1,\"x\":0,\"y\":0}",
                    "\"region\":{\"height\":1,\"width\":1,\"x\":0.5,\"y\":0}"),
             .invalidPageGeometry(.invalidNormalizedRegion)),
            ("source rect empty",
             sample("\"expectedSourceRect\":{\"height\":100,\"width\":100,\"x\":0,\"y\":0}",
                    "\"expectedSourceRect\":{\"height\":100,\"width\":0,\"x\":0,\"y\":0}"),
             .invalidPageGeometry(.nonPositiveBox)),
        ]
        for (name, data, expected) in cases {
            XCTAssertEqual(refusal(data, name), expected, name)
        }
    }

    /// A duplicated key is refused, not resolved last-wins.
    ///
    /// This is the parser differential the token-preserving pass closes:
    /// `JSONSerialization`, which this initializer also consults, accepts a
    /// duplicated key and keeps one of the two values. Because the token pass
    /// runs first and refuses the document outright, the two parsers cannot be
    /// made to disagree about which value a field has.
    func testDuplicatedKeysAreRefusedBeforeEitherParserPicksAWinner() {
        let cases = [
            ("duplicate page number", "\"pageNumber\":1,", "\"pageNumber\":1,\"pageNumber\":2,"),
            ("duplicate schema version", "\"schemaVersion\":3", "\"schemaVersion\":3,\"schemaVersion\":2"),
            ("duplicate margin object",
             "\"outputMargins\":\(Self.marginObject),",
             "\"outputMargins\":\(Self.marginObject),\"outputMargins\":"
                + "{\"bottom\":0,\"left\":0,\"right\":0,\"top\":0},"),
        ]
        for (name, find, replacement) in cases {
            XCTAssertEqual(refusal(sample(find, replacement), name), .malformedJSON, name)
        }
    }

    /// Each declared cap is bracketed: admitted at the limit, refused one step
    /// past it. An oversized sample alone cannot pin a limit -- a 200-level
    /// document is refused by a guard set anywhere from 1 to 199, and would
    /// also be refused by a parser with a nesting limit of its own, so it
    /// cannot say whose refusal it saw. The bracket says exactly where the
    /// boundary is, and that the parser admits everything up to it.
    ///
    /// The caps come from `TokenPreservingJSON` and are restated here on
    /// purpose: they are internal to `LabelCore`, and a test that read them
    /// from the implementation would follow a change to them rather than
    /// detect it. 4 MiB of input, 64 levels of nesting, 100,000 nodes.
    ///
    /// Neither Foundation parser is doing this work: measured on Linux with
    /// swift-foundation 6.1.3, `JSONSerialization` and `JSONDecoder` both
    /// accept the 65- and 200-level documents that the token guard refuses
    /// (they refuse somewhere between 200 and 600). The 65-level refusal below
    /// is therefore the repo's guard, and deleting that guard makes this test
    /// fail rather than falling through to a Foundation limit.
    func testDeclaredResourceCapsAreBracketedNotMerelyExceeded() throws {
        // Byte cap: a document padded to exactly 4 MiB parses; one byte more
        // is refused, and the extra byte is whitespace, so nothing but the
        // count distinguishes them.
        func padded(to total: Int) -> Data {
            let padding = total - Self.baseVersionThree.utf8.count
            return Data(("{" + String(repeating: " ", count: padding)
                + Self.baseVersionThree.dropFirst()).utf8)
        }
        let byteCap = 4 * 1024 * 1024
        XCTAssertEqual(try OfflineConversionTicket(jsonData: padded(to: byteCap)).schemaVersion, 3)
        XCTAssertEqual(refusal(padded(to: byteCap + 1), "one byte over 4 MiB"), .malformedJSON)

        // Nesting cap: an unknown field nested to exactly 64 levels parses; 65
        // is refused. The array is empty at the bottom, so the two documents
        // differ by one level of nesting and nothing else.
        func nested(_ levels: Int) -> Data {
            let payload = "\"deep\":" + String(repeating: "[", count: levels)
                + String(repeating: "]", count: levels) + ","
            return sample("\"pageNumber\":1,", payload + "\"pageNumber\":1,")
        }
        XCTAssertEqual(try OfflineConversionTicket(jsonData: nested(64)).schemaVersion, 3)
        XCTAssertEqual(refusal(nested(65), "65 levels of nesting"), .malformedJSON)

        // Node cap: the cap counts every value in the document, and the base
        // spends 30 of them, plus one for the array itself -- so 99,969
        // elements is the last admitted array and 99,970 is one too many. If
        // the base document gains or loses a value, these two numbers move
        // together and this test says so rather than drifting quietly.
        func wide(_ count: Int) -> Data {
            let payload = "\"wide\":[" + Array(repeating: "0", count: count).joined(separator: ",") + "],"
            return sample("\"pageNumber\":1,", payload + "\"pageNumber\":1,")
        }
        let nodeCap = 100_000
        let spent = 31
        XCTAssertEqual(try OfflineConversionTicket(jsonData: wide(nodeCap - spent)).schemaVersion, 3,
                       "the base document no longer spends \(spent) of the \(nodeCap) nodes")
        XCTAssertEqual(refusal(wide(nodeCap - spent + 1), "one node over the cap"), .malformedJSON)
    }

    /// The finding this test recorded for the #93 / #101 human pass is fixed,
    /// and the test is now its regression.
    ///
    /// Unknown fields are ignored: the strict key-set check applies to the
    /// margin object alone, so an unrelated key rides along into the worker's
    /// parent unexamined. That is ordinary `Decodable` behaviour and is not by
    /// itself a defect.
    ///
    /// What it exposed was: the initializer parses the same bytes twice, once
    /// through `WorkerProtocolJSON` (whose failure is mapped to
    /// `malformedJSON`) and once through `JSONSerialization`, whose `try` was
    /// bare. A numeric literal in an *ignored* field can be accepted by the
    /// first and refused by the second -- `1e400` is one -- and the resulting
    /// `NSError` left the initializer untyped, contradicting the closed surface
    /// `OfflineConversionTicketErrorSurfaceTests` documents. Observed on
    /// Linux/swift-foundation 6.1.3 against a faithful replica of this
    /// initializer: `NSCocoaErrorDomain` 3840, "Number 1e400 is not
    /// representable in Swift"; never observed on macOS, where LabelMac's first
    /// real compile is hosted CI.
    ///
    /// `OfflineConversionTicket.rootObject(from:)` now owns that second parse
    /// and maps both of its failure modes to `malformedJSON`, so an untyped
    /// escape is a failure here rather than a tolerated outcome. Which of the
    /// two *admitted* outcomes occurs still depends on the Foundation build --
    /// the document either parses to the honest ticket or is refused -- so both
    /// of those remain accepted.
    func testUnknownFieldsAreIgnoredAndAnOverflowingLiteralCannotEscapeUntyped() throws {
        let ignorable = try OfflineConversionTicket(
            jsonData: sample("\"pageNumber\":1,", "\"unknown\":true,\"pageNumber\":1,"))
        XCTAssertEqual(ignorable, try OfflineConversionTicket(jsonData: Data(Self.baseVersionThree.utf8)),
                       "an ignored field changed an admitted field")

        let honest = try OfflineConversionTicket(jsonData: Data(Self.baseVersionThree.utf8))
        let overflowing = sample("\"pageNumber\":1,", "\"unused\":1e400,\"pageNumber\":1,")
        do {
            // The `try` has to sit outside the assertion: XCTAssertEqual turns a
            // thrown error into its own failure, which would swallow the very
            // error this test exists to classify.
            let admitted = try OfflineConversionTicket(jsonData: overflowing)
            XCTAssertEqual(admitted, honest)
        } catch let error as OfflineConversionTicket.TicketError {
            XCTAssertEqual(error, .malformedJSON)
        } catch {
            XCTFail("untyped escape from the ticket initializer: "
                    + "\(type(of: error)) crossed the boundary: \(error)")
        }
    }

    /// FINDING for the #93 / #101 human pass, recorded rather than fixed.
    ///
    /// The worker emits UTF-8 and nothing else, but the parser accepts a BOM
    /// and, through `TokenPreservingJSON`'s encoding normalization, UTF-16 as
    /// well. So the admitted input surface is wider than the emitted one. Both
    /// outcomes are accepted here because which one occurs depends on
    /// Foundation; what is asserted is that an alternate encoding cannot
    /// produce a ticket that differs from the UTF-8 one.
    func testAlternateEncodingsEitherParseIdenticallyOrAreRefused() throws {
        let honest = try OfflineConversionTicket(jsonData: Data(Self.baseVersionThree.utf8))
        var encodings: [(String, Data)] = [
            ("utf-8 with BOM", Data([0xEF, 0xBB, 0xBF]) + Data(Self.baseVersionThree.utf8)),
        ]
        if let utf16 = Self.baseVersionThree.data(using: .utf16LittleEndian) {
            encodings.append(("utf-16le with BOM", Data([0xFF, 0xFE]) + utf16))
        }
        for (name, data) in encodings {
            do {
                // The whole ticket, not a few of its fields: a decoding
                // regression in resolution, conversion, placement policy,
                // region, source rect or rotation has to fail this too. The
                // `try` stays outside the assertion so a thrown error reaches
                // the catch clauses instead of becoming XCTest's own failure.
                let admitted = try OfflineConversionTicket(jsonData: data)
                XCTAssertEqual(admitted, honest, name)
            } catch let error as OfflineConversionTicket.TicketError {
                XCTAssertEqual(error, .malformedJSON, name)
            } catch {
                XCTFail("\(name): \(type(of: error)) crossed the boundary: \(error)")
            }
        }
    }

    /// A document that is not a JSON object at all is refused, including the
    /// shapes a stream framing error would produce.
    func testNonObjectDocumentsAreRefused() {
        for (name, text) in [("truncated", "{"), ("array root", "[1,2,3]"), ("empty", ""),
                             ("bare number", "3"), ("trailing bytes", Self.baseVersionThree + " x"),
                             ("two documents", Self.baseVersionThree + Self.baseVersionThree)] {
            XCTAssertEqual(refusal(Data(text.utf8), name), .malformedJSON, name)
        }
    }

    /// The ticket bounds geometry for validity, not for a device. A stock a
    /// printer could never image is admitted by the ticket and refused where
    /// the dot bound actually lives, in `DotCanvas`. Pinned so the division is
    /// deliberate rather than assumed: the ticket is not the dot-limit check.
    func testTheTicketAdmitsGeometryThatTheDotCanvasStillRefuses() throws {
        let admitted = try OfflineConversionTicket(
            jsonData: sample("\"widthMillimeters\":20", "\"widthMillimeters\":1e308"))
        XCTAssertEqual(admitted.physicalSize.width.value, 1e308)
        XCTAssertThrowsError(try DotCanvas(physicalSize: admitted.physicalSize,
                                           resolution: admitted.resolution)) {
            XCTAssertEqual($0 as? PhysicalGeometryError, .dotCountOverflow)
        }
    }

    /// A non-finite length spelled as a raw literal cannot reach a `Millimeters`
    /// value. Either the decoder refuses the token or the geometry type refuses
    /// the infinity; both are typed, and the set is written as two because two
    /// routes exist, exactly as for the margin case in
    /// `OfflineExtractionWorkerTests`.
    func testNonFiniteLengthsAndResolutionsAreRefusedByOneRouteOrTheOther() {
        let cases: [(String, String, String, [OfflineConversionTicket.TicketError])] = [
            ("width 1e400", "\"widthMillimeters\":20", "\"widthMillimeters\":1e400",
             [.malformedJSON, .invalidPhysicalGeometry(.nonFiniteLength)]),
            ("height -1e400", "\"heightMillimeters\":10", "\"heightMillimeters\":-1e400",
             [.malformedJSON, .invalidPhysicalGeometry(.nonFiniteLength),
              .invalidPhysicalGeometry(.nonPositiveLength)]),
            ("resolution 1e400", "\"xDotsPerMillimeter\":8", "\"xDotsPerMillimeter\":1e400",
             [.malformedJSON, .invalidPhysicalGeometry(.nonFiniteResolution)]),
        ]
        for (name, find, replacement, admissible) in cases {
            guard let thrown = refusal(sample(find, replacement), name) else { continue }
            XCTAssertTrue(admissible.contains(thrown), "\(name): unexpected refusal \(thrown)")
        }
    }
}
