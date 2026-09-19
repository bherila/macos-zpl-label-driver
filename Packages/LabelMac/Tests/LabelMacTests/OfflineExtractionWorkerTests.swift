import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class OfflineExtractionWorkerTests: XCTestCase {
    func testReturnedBitmapRequiresExactCanvasPaddingAndDiagnosticEncoding() throws {
        let canvas = try DotCanvas(physicalSize: PhysicalSize(width: Millimeters(9), height: Millimeters(3)),
            resolution: DotResolution(xDotsPerMillimeter: 1, yDotsPerMillimeter: 1))
        let bitmap = try MonochromeBitmap(width: 9, height: 3, bytes: [128, 128, 0, 0, 255, 0])
        let zpl = try ZPLGraphicEncoder().diagnosticFormat(bitmap)
        func output(_ preview: Data, _ encoded: Data, width: Int = 9) -> OfflineRenderWorkerOutput {
            .init(result: .init(widthDots: width, heightDots: 3,
                                zplBytes: encoded.count, previewBytes: preview.count),
                  zpl: encoded, previewPBM: preview)
        }
        XCTAssertEqual(try OfflineExtractionWorker.validate(output: output(bitmap.pbmData(), zpl), canvas: canvas), bitmap)
        var badPadding = bitmap.pbmData()
        badPadding[badPadding.index(before: badPadding.endIndex)] = 1
        let invalidOutputs = [
            output(badPadding, zpl),
            output(bitmap.pbmData(), Data("unrelated output".utf8)),
            output(bitmap.pbmData(), zpl, width: 8),
            output(bitmap.pbmData() + Data([0]), zpl),
            output(Data(bitmap.pbmData().dropLast()), zpl),
            output(Data("P4\n8 3\n".utf8) + Data(bitmap.bytes), zpl),
        ]
        for invalid in invalidOutputs {
            XCTAssertThrowsError(try OfflineExtractionWorker.validate(output: invalid, canvas: canvas)) {
                XCTAssertEqual($0 as? OfflineExtractionWorker.Error, .invalidWorkerBitmap)
            }
        }
    }

    private func plannedLabel(outputMargins: OutputMargins, outputStock: PhysicalSize) throws -> PlannedExtractionLabel {
        let box = try PDFPageBox(originX: 0, originY: 0, width: 20, height: 10)
        let profile = try WorkflowProfile(
            schemaVersion: outputMargins == .zero ? 2 : 3, id: "offline-extraction", revision: 4,
            outputStockID: "test-stock", outputStock: outputStock, outputMargins: outputMargins,
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

    private var stock: PhysicalSize {
        get throws { PhysicalSize(width: try Millimeters(20), height: try Millimeters(10)) }
    }

    private func canvas(_ size: PhysicalSize) throws -> DotCanvas {
        try DotCanvas(physicalSize: size,
            resolution: DotResolution(xDotsPerMillimeter: 1, yDotsPerMillimeter: 1))
    }

    /// A zero-margin plan must keep emitting the byte-identical v2 ticket, so
    /// the margin feature cannot silently change the established wire form.
    func testZeroMarginTicketStaysAtSchemaVersionTwoWithoutMarginKey() throws {
        let stock = try self.stock
        let ticket = try OfflineExtractionWorker.ticketJSON(
            label: try plannedLabel(outputMargins: .zero, outputStock: stock),
            canvas: try canvas(stock), conversion: .textAndBarcodeThreshold(cutoff: 128))
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: ticket) as? [String: Any])
        XCTAssertEqual(wire["schemaVersion"] as? Int, 2)
        XCTAssertNil(wire["outputMargins"])
    }

    /// A non-zero margin must reach the child as schemaVersion 3 carrying the
    /// exact four edges; an inert ticket would render margins invisibly.
    func testNonZeroMarginTicketCarriesSchemaVersionThreeAndEveryEdge() throws {
        let stock = try self.stock
        let margins = try OutputMargins(left: 1, top: 2, right: 3, bottom: 0.5)
        let ticket = try OfflineExtractionWorker.ticketJSON(
            label: try plannedLabel(outputMargins: margins, outputStock: stock),
            canvas: try canvas(stock), conversion: .textAndBarcodeThreshold(cutoff: 128))
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: ticket) as? [String: Any])
        XCTAssertEqual(wire["schemaVersion"] as? Int, 3)
        let emitted = try XCTUnwrap(wire["outputMargins"] as? [String: Double])
        XCTAssertEqual(emitted, ["left": 1, "top": 2, "right": 3, "bottom": 0.5])
    }

    /// The emitted v3 ticket is what the worker parent admits back, so the two
    /// ends of the process boundary are checked against each other, not apart.
    func testEmittedTicketRoundTripsThroughOfflineConversionTicket() throws {
        let stock = try self.stock
        for margins in [OutputMargins.zero, try OutputMargins(left: 1, top: 2, right: 3, bottom: 0.5)] {
            let ticket = try OfflineExtractionWorker.ticketJSON(
                label: try plannedLabel(outputMargins: margins, outputStock: stock),
                canvas: try canvas(stock), conversion: .textAndBarcodeThreshold(cutoff: 128))
            let admitted = try OfflineConversionTicket(jsonData: ticket)
            XCTAssertEqual(admitted.outputMargins, margins)
            XCTAssertEqual(admitted.physicalSize, stock)
        }
    }

    /// The emitted v3 ticket is the process boundary, so its margin object is
    /// attacker-influenced input. Each malformed shape must be refused with a
    /// typed error rather than clamped, defaulted or silently zeroed.
    func testEmittedTicketMarginsAreRejectedFailClosedWithTypedErrors() throws {
        let stock = try self.stock
        let margins = try OutputMargins(left: 1, top: 2, right: 3, bottom: 0.5)
        let emitted = try OfflineExtractionWorker.ticketJSON(
            label: try plannedLabel(outputMargins: margins, outputStock: stock),
            canvas: try canvas(stock), conversion: .textAndBarcodeThreshold(cutoff: 128))
        func mutated(_ change: (inout [String: Any]) -> Void) throws -> Data {
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: emitted) as? [String: Any])
            change(&root)
            return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        }

        // A negative edge is refused by the geometry type, not normalized to 0.
        let negative = try mutated { $0["outputMargins"] = ["left": -1, "top": 2, "right": 3, "bottom": 0.5] }
        XCTAssertThrowsError(try OfflineConversionTicket(jsonData: negative)) {
            XCTAssertEqual($0 as? PagePlacementError, .invalidMargins)
        }

        // Margins wider than the stock leave no printable area at all.
        let exhausting = try mutated {
            $0["outputMargins"] = ["left": stock.width.value, "top": 0,
                                   "right": stock.width.value, "bottom": 0]
        }
        XCTAssertThrowsError(try OfflineConversionTicket(jsonData: exhausting)) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError, .malformedJSON)
        }

        // A v2 ticket has no margin field, so margins carried at v2 are refused
        // instead of being accepted and quietly applied.
        let versionTwo = try mutated { $0["schemaVersion"] = 2 }
        XCTAssertThrowsError(try OfflineConversionTicket(jsonData: versionTwo)) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError, .malformedJSON)
        }

        // A v3 ticket that drops the margin object entirely is refused rather
        // than defaulted to zero, so a stripped field cannot lose the margins.
        let stripped = try mutated { $0.removeValue(forKey: "outputMargins") }
        XCTAssertThrowsError(try OfflineConversionTicket(jsonData: stripped)) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError, .malformedJSON)
        }
    }

    /// A non-finite edge cannot be produced by `JSONSerialization`, so it is
    /// spliced in as a raw literal the way a hostile writer would send it.
    func testEmittedTicketRejectsNonFiniteMarginArrivingAsARawLiteral() throws {
        let stock = try self.stock
        let margins = try OutputMargins(left: 1, top: 2, right: 3, bottom: 0.5)
        let emitted = try OfflineExtractionWorker.ticketJSON(
            label: try plannedLabel(outputMargins: margins, outputStock: stock),
            canvas: try canvas(stock), conversion: .textAndBarcodeThreshold(cutoff: 128))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: emitted) as? [String: Any])
        root.removeValue(forKey: "outputMargins")
        let base = String(decoding: try JSONSerialization.data(withJSONObject: root,
            options: [.sortedKeys]), as: UTF8.self)
        XCTAssertTrue(base.hasPrefix("{"))
        for literal in ["1e400", "-1e400"] {
            let spliced = Data(("{\"outputMargins\":{\"left\":\(literal),\"top\":0,"
                + "\"right\":0,\"bottom\":0}," + base.dropFirst()).utf8)
            XCTAssertThrowsError(try OfflineConversionTicket(jsonData: spliced)) { error in
                // Fail-closed either way: the decoder may refuse the overflowing
                // literal, or admit an infinity the geometry type then refuses.
                // What must never happen is a ticket carrying a non-finite edge.
                let decoded = (error as? OfflineConversionTicket.TicketError) == .malformedJSON
                let geometry = (error as? PagePlacementError) == .invalidMargins
                XCTAssertTrue(decoded || geometry, "untyped rejection: \(error)")
            }
        }
    }
}
