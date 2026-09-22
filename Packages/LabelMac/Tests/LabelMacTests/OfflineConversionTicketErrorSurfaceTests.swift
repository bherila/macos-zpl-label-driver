import XCTest
import LabelCore
@testable import LabelMac

/// Pins the complete set of error types `OfflineConversionTicket`'s initializers
/// can throw.
///
/// The ticket is the process boundary between the app and the render worker and
/// it decodes attacker-influenced JSON. Before #132 the initializer was
/// documented around `TicketError` but also propagated `PhysicalGeometryError`,
/// `PagePlacementError` and `PageGeometryError` from its component
/// initializers, so a caller that switched exhaustively over `TicketError` had
/// not, in fact, handled the ticket's failure surface.
///
/// Every rejection was typed and fail-closed both before and after, so this was
/// never a vulnerability. It was a contract wider than its documentation, which
/// is the shape a future unhandled path grows from.
///
/// Two properties are asserted together, because either alone is satisfiable by
/// a fix that breaks the other:
///
/// 1. **Closed.** Nothing but `TicketError` escapes either initializer.
/// 2. **Not collapsed.** Each component domain keeps its own case and its own
///    payload. Mapping all four onto `malformedJSON` would satisfy (1) while
///    throwing away which constraint a hostile ticket actually violated.
///
/// Closure held everywhere by construction except at one call: `init(jsonData:)`
/// re-parses the accepted bytes with `JSONSerialization` to tell a present key
/// from an absent one, and that `try` sat outside every `do`/`catch`. The
/// `guard ... else` around it handled a failed *cast*, not a *throw*, so an
/// `NSError` in `NSCocoaErrorDomain` would have crossed the boundary untyped.
/// `rootObject(from:)` now owns that call, and the two tests at the end of this
/// file pin the mapping and the property it protects separately, because the
/// inputs on which two JSON parsers disagree are platform-dependent and the
/// mapping is not.
final class OfflineConversionTicketErrorSurfaceTests: XCTestCase {
    /// A ticket that parses, as the base every malformed sample is mutated from.
    private static let validV1 = """
    {
      "schemaVersion": 1,
      "pageNumber": 1,
      "physicalSize": { "widthMillimeters": 10, "heightMillimeters": 10 },
      "resolution": { "xDotsPerMillimeter": 1, "yDotsPerMillimeter": 1 },
      "conversion": { "mode": "textAndBarcodeThreshold", "cutoff": 128 }
    }
    """

    private func ticket(_ json: String) throws -> OfflineConversionTicket {
        try OfflineConversionTicket(jsonData: Data(json.utf8))
    }

    /// Mutates the valid v1 base through `JSONSerialization` so a sample differs
    /// from a parsing ticket by exactly the field under test.
    private func mutatedV1(_ change: (inout [String: Any]) -> Void) throws -> String {
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(Self.validV1.utf8)) as? [String: Any])
        change(&root)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func v2(region: [String: Double], expected: [String: Double]) throws -> String {
        try mutatedV1 {
            $0["schemaVersion"] = 2
            $0["extraction"] = ["region": region, "expectedSourceRect": expected, "rotation": 0]
        }
    }

    private static let unitRect: [String: Double] = ["x": 0, "y": 0, "width": 1, "height": 1]
    private static let sourceRect: [String: Double] = ["x": 0, "y": 0, "width": 100, "height": 100]

    // MARK: - Each component domain keeps its own case and payload

    /// A length the geometry type refuses arrives as the geometry type's own
    /// error, wrapped -- not as `malformedJSON`, which would say only that
    /// something somewhere was wrong.
    func testPhysicalLengthFailureIsWrappedWithItsOwnCause() throws {
        let zeroWidth = try mutatedV1 {
            $0["physicalSize"] = ["widthMillimeters": 0, "heightMillimeters": 10]
        }
        XCTAssertThrowsError(try ticket(zeroWidth)) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError,
                           .invalidPhysicalGeometry(.nonPositiveLength))
        }

    }

    func testResolutionFailureIsWrappedWithItsOwnCause() throws {
        let zeroResolution = try mutatedV1 {
            $0["resolution"] = ["xDotsPerMillimeter": 0, "yDotsPerMillimeter": 1]
        }
        XCTAssertThrowsError(try ticket(zeroResolution)) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError,
                           .invalidPhysicalGeometry(.nonPositiveResolution))
        }
    }

    func testNormalizedRegionFailureIsWrappedWithItsOwnCause() throws {
        let degenerate = try v2(region: ["x": 0, "y": 0, "width": 0, "height": 1],
                                expected: Self.sourceRect)
        XCTAssertThrowsError(try ticket(degenerate)) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError,
                           .invalidPageGeometry(.invalidNormalizedRegion))
        }
    }

    func testSourceRectFailureIsWrappedWithItsOwnCause() throws {
        let degenerate = try v2(region: Self.unitRect,
                                expected: ["x": 0, "y": 0, "width": 0, "height": 100])
        XCTAssertThrowsError(try ticket(degenerate)) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError,
                           .invalidPageGeometry(.nonPositiveBox))
        }
    }

    func testMarginFailureIsWrappedWithItsOwnCause() throws {
        let negative = try mutatedV1 {
            $0["schemaVersion"] = 3
            $0["outputMargins"] = ["left": -1, "top": 0, "right": 0, "bottom": 0]
        }
        XCTAssertThrowsError(try ticket(negative)) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError,
                           .invalidPagePlacement(.invalidMargins))
        }
    }

    // MARK: - The surface is closed

    /// The property the issue is actually about: across every way a ticket can
    /// be refused, nothing but `TicketError` reaches the caller.
    ///
    /// Without the boundary mapping this fails on the first four samples, which
    /// throw `PhysicalGeometryError`, `PageGeometryError` and
    /// `PagePlacementError` respectively.
    func testNothingButTicketErrorEscapesTheInitializer() throws {
        let samples: [(String, String)] = [
            ("zero width", try mutatedV1 {
                $0["physicalSize"] = ["widthMillimeters": 0, "heightMillimeters": 10] }),
            ("zero resolution", try mutatedV1 {
                $0["resolution"] = ["xDotsPerMillimeter": 0, "yDotsPerMillimeter": 1] }),
            ("degenerate region", try v2(region: ["x": 0, "y": 0, "width": 0, "height": 1],
                                        expected: Self.sourceRect)),
            ("degenerate source rect", try v2(region: Self.unitRect,
                                              expected: ["x": 0, "y": 0, "width": 0, "height": 100])),
            ("negative margin", try mutatedV1 {
                $0["schemaVersion"] = 3
                $0["outputMargins"] = ["left": -1, "top": 0, "right": 0, "bottom": 0] }),
            ("unknown schema", try mutatedV1 { $0["schemaVersion"] = 4 }),
            ("page number zero", try mutatedV1 { $0["pageNumber"] = 0 }),
            ("cutoff out of range", try mutatedV1 {
                $0["conversion"] = ["mode": "textAndBarcodeThreshold", "cutoff": 256] }),
            ("unknown conversion mode", try mutatedV1 {
                $0["conversion"] = ["mode": "unknown"] }),
            ("unknown placement policy", try mutatedV1 { $0["placementPolicy"] = "stretch" }),
            ("v1 carrying margins", try mutatedV1 {
                $0["outputMargins"] = ["left": 0, "top": 0, "right": 0, "bottom": 0] }),
            ("v3 without margins", try mutatedV1 { $0["schemaVersion"] = 3 }),
            ("not JSON at all", "{"),
        ]

        for (name, json) in samples {
            XCTAssertThrowsError(try ticket(json), name) { error in
                guard let ticketError = error as? OfflineConversionTicket.TicketError else {
                    return XCTFail("\(name): \(type(of: error)) crossed the boundary: \(error)")
                }
                // An unrecognised component domain must not read as a
                // recognised one, so the fallback case is a failure here too.
                if case let .unclassifiedComponentFailure(domain) = ticketError {
                    XCTFail("\(name): unmapped component domain \(domain)")
                }
            }
        }
    }

    /// Closing the surface must not be done by collapsing it. Two different
    /// violated constraints stay two different values, and neither degrades to
    /// the catch-all `malformedJSON`.
    func testDistinctComponentFailuresStayDistinct() throws {
        let zeroWidth = try mutatedV1 {
            $0["physicalSize"] = ["widthMillimeters": 0, "heightMillimeters": 10]
        }
        let negativeMargin = try mutatedV1 {
            $0["schemaVersion"] = 3
            $0["outputMargins"] = ["left": -1, "top": 0, "right": 0, "bottom": 0]
        }
        var thrown: [OfflineConversionTicket.TicketError] = []
        for json in [zeroWidth, negativeMargin] {
            XCTAssertThrowsError(try ticket(json)) { error in
                if let ticketError = error as? OfflineConversionTicket.TicketError {
                    thrown.append(ticketError)
                }
            }
        }
        XCTAssertEqual(thrown.count, 2)
        XCTAssertNotEqual(thrown.first, thrown.last)
        XCTAssertFalse(thrown.contains(.malformedJSON),
                       "a component cause was flattened into the catch-all")
    }

    /// The pre-existing `TicketError` cases are unchanged by the widening, so
    /// the mapping added causes rather than rerouting the ones already pinned
    /// by `QuartzPDFRendererTests` and `OfflineExtractionWorkerTests`.
    func testExistingTicketErrorCasesAreUnchanged() throws {
        XCTAssertThrowsError(try ticket(try mutatedV1 { $0["schemaVersion"] = 4 })) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError, .unsupportedSchemaVersion(4))
        }
        XCTAssertThrowsError(try ticket(try mutatedV1 { $0["pageNumber"] = 0 })) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError, .invalidPageNumber)
        }
        XCTAssertThrowsError(try ticket(try mutatedV1 {
            $0["conversion"] = ["mode": "textAndBarcodeThreshold", "cutoff": 256]
        })) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError, .invalidThreshold)
        }
        XCTAssertThrowsError(try ticket("{")) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError, .malformedJSON)
        }
    }

    // MARK: - The second parse over the same bytes is inside the surface

    /// Splices a raw JSON token under a key the ticket schema does not know, so
    /// the sample differs from a parsing ticket only in bytes both parsers must
    /// traverse and no ticket field consumes. The token is spliced textually
    /// rather than built through `JSONSerialization`, which cannot express the
    /// tokens these samples are made of.
    private static func v1WithUnknownField(_ rawToken: String) -> String {
        precondition(validV1.hasSuffix("}"), "the base sample must end at its closing brace")
        return String(validV1.dropLast()) + ",\n  \"unknownField\": \(rawToken)\n}"
    }

    /// Every way the second parse can fail is refused as `malformedJSON` --
    /// named, not merely "something was thrown".
    ///
    /// These bytes are the deterministic half of the property: no JSON parser
    /// accepts a truncated object, empty input or an invalid UTF-8 key, and the
    /// last three samples are refused either by the parser (which may reject a
    /// top-level fragment) or by the cast (which rejects any top level that is
    /// not a dictionary) -- mapping both is this function's job, so the outcome
    /// is the same either way. Remove the `do`/`catch` inside
    /// `rootObject(from:)` and the first three samples deliver `NSError`
    /// instead, failing here.
    func testEverySecondParseFailureIsRefusedAsMalformedJSON() throws {
        let samples: [(String, Data)] = [
            ("truncated object", Data("{".utf8)),
            ("empty input", Data()),
            // 0xFF cannot appear in UTF-8 text: {"<0xFF>":1}
            ("invalid UTF-8 in a key", Data([0x7B, 0x22, 0xFF, 0x22, 0x3A, 0x31, 0x7D])),
            ("top-level array", Data("[]".utf8)),
            ("top-level number", Data("1".utf8)),
            ("top-level string", Data("\"ticket\"".utf8)),
        ]
        for (name, data) in samples {
            XCTAssertThrowsError(try OfflineConversionTicket.rootObject(from: data), name) { error in
                XCTAssertEqual(error as? OfflineConversionTicket.TicketError, .malformedJSON, name)
            }
        }
    }

    /// The property the mapping protects: on bytes where the two parsers can
    /// disagree, a refusal is still a `TicketError`.
    ///
    /// Which of these samples actually reaches the second parse depends on the
    /// Foundation build, so this asserts the reachable outcomes rather than
    /// pretending to know them: each sample is the valid base plus bytes no
    /// admitted field's value depends on, so it either parses or is refused as
    /// `malformedJSON`. What it may never do is deliver an error of any other
    /// type. On Linux Foundation (Swift 6.1.3) the exponent samples are the ones
    /// observed to reach the second parse: `TokenPreservingJSON` keeps `1e999`
    /// as an unconverted token and `JSONDecoder` never materializes an unknown
    /// key, while `JSONSerialization` refuses the whole document.
    func testParserDisagreementCannotEscapeAsAnUntypedError() throws {
        let deepArray = String(repeating: "[", count: 64) + "1" + String(repeating: "]", count: 64)
        var samples: [(String, Data)] = [
            ("exponent beyond Double", Data(Self.v1WithUnknownField("1e999").utf8)),
            ("negative exponent beyond Double", Data(Self.v1WithUnknownField("-1e999").utf8)),
            ("lone high surrogate escape", Data(Self.v1WithUnknownField("\"\\ud800\"").utf8)),
            ("integer of 200 digits", Data(Self.v1WithUnknownField(String(repeating: "9", count: 200)).utf8)),
            ("64-deep array", Data(Self.v1WithUnknownField(deepArray).utf8)),
            ("duplicate key", Data(Self.v1WithUnknownField("1")
                .replacingOccurrences(of: "\"pageNumber\": 1",
                                      with: "\"pageNumber\": 1, \"pageNumber\": 1").utf8)),
            ("UTF-8 byte order mark", Data([0xEF, 0xBB, 0xBF]) + Data(Self.validV1.utf8)),
            // A lone 0xFF inside a string value, which is not UTF-8 text.
            ("invalid UTF-8 in a string", Data(String(Self.validV1.dropLast()).utf8)
                + Data(",\n  \"unknownField\": \"".utf8) + Data([0xFF]) + Data("\"\n}".utf8)),
        ]
        if let utf16 = Self.validV1.data(using: .utf16LittleEndian) {
            samples.append(("UTF-16LE without a byte order mark", utf16))
        }

        for (name, data) in samples {
            do {
                _ = try OfflineConversionTicket(jsonData: data)
            } catch let error as OfflineConversionTicket.TicketError {
                XCTAssertEqual(error, .malformedJSON, name)
            } catch {
                XCTFail("\(name): \(type(of: error)) crossed the boundary: \(error)")
            }
        }
    }
}
