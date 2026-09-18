import XCTest
@testable import LabelCore

final class PhysicalGeometryQualificationTests: XCTestCase {
    private let supported = CapabilityFact(state: .supported, evidence: .documentedModel(sourceID: "synthetic-geometry-fixture"))
    private func limit(_ maximum: Int) -> QualifiedDotLimit { .init(fact: supported, maximumDots: maximum) }
    private var policy: PhysicalGeometryQualification {
        .init(width: limit(832), continuousLength: limit(1_500), homeX: limit(100), homeY: limit(200))
    }

    func testQualifiedPhysicalGeometryHasExactPairedOrderAndBoundedOutput() throws {
        let request = try MediaGeometryRequest(widthDots: 813, lengthDots: 1_219, originXDot: 9, originYDot: 17)
        let expected = Data("^MNN\n^LL1219\n^PW813\n^LH9,17\n".utf8)
        XCTAssertEqual(try ZPLDocumentedControlEncoder(maximumOutputBytes: expected.count).encodePhysicalGeometry(
            request, qualification: policy, tracking: .continuous, trackingFact: supported), expected)
        XCTAssertThrowsError(try ZPLDocumentedControlEncoder(maximumOutputBytes: expected.count - 1).encodePhysicalGeometry(
            request, qualification: policy, tracking: .continuous, trackingFact: supported))
    }

    func testDeclarationRequiresEvidenceAndSeparateKnownBounds() throws {
        try PhysicalGeometryQualification.unverified.validateDeclaration()
        for state in [CapabilityState.unknown, .unsupported] {
            let fact = CapabilityFact(state: state, evidence: .unobserved)
            XCTAssertThrowsError(try PhysicalGeometryQualification(width: .init(fact: fact, maximumDots: 832)).validateDeclaration())
        }
        for maximum: Int? in [nil, 0, 1, 32_001, Int.max] {
            XCTAssertThrowsError(try PhysicalGeometryQualification(width: .init(fact: supported, maximumDots: maximum)).validateDeclaration())
        }
        XCTAssertThrowsError(try PhysicalGeometryQualification(homeX: .init(fact: .init(state: .supported,
            evidence: .unobserved), maximumDots: 0)).validateDeclaration())
        try PhysicalGeometryQualification(homeX: limit(0), homeY: limit(0)).validateDeclaration()
    }

    func testUnknownAndUnsupportedRequestsRemainDistinct() throws {
        let request = try MediaGeometryRequest(widthDots: 2)
        for state in [CapabilityState.unknown, .unsupported] {
            let p = PhysicalGeometryQualification(width: .init(fact: .init(state: state, evidence: .unobserved), maximumDots: nil))
            XCTAssertThrowsError(try p.controls(for: request)) {
                XCTAssertEqual($0 as? PhysicalGeometryQualification.Error, .unavailable(.width, state))
            }
        }
        XCTAssertThrowsError(try policy.controls(for: MediaGeometryRequest()))
        XCTAssertThrowsError(try policy.controls(for: MediaGeometryRequest(originXDot: 0))) {
            XCTAssertEqual($0 as? PhysicalGeometryQualification.Error, .incompleteHome)
        }
        XCTAssertThrowsError(try policy.controls(for: MediaGeometryRequest(widthDots: 833)))
        XCTAssertThrowsError(try policy.controls(for: MediaGeometryRequest(originXDot: 101, originYDot: 0)))
        XCTAssertThrowsError(try policy.controls(for: MediaGeometryRequest(originXDot: 0, originYDot: 201)))
        XCTAssertThrowsError(try policy.controls(for: MediaGeometryRequest(originXDot: Int.min, originYDot: Int.max)))
    }

    func testContinuousLengthNeverUsesRetainedModeOrLength() throws {
        let length = try MediaGeometryRequest(lengthDots: 1_219)
        for mode: MediaTracking? in [nil, .gap, .blackMark] {
            XCTAssertThrowsError(try policy.controls(for: length, tracking: mode, trackingFact: supported)) {
                XCTAssertEqual($0 as? PhysicalGeometryQualification.Error, .continuousModeRequired)
            }
        }
        XCTAssertThrowsError(try policy.controls(for: MediaGeometryRequest(widthDots: 2), tracking: .continuous)) {
            XCTAssertEqual($0 as? PhysicalGeometryQualification.Error, .continuousLengthRequired)
        }
        for state in [CapabilityState.unknown, .unsupported] {
            XCTAssertThrowsError(try policy.controls(for: length, tracking: .continuous,
                trackingFact: .init(state: state, evidence: .unobserved))) {
                XCTAssertEqual($0 as? PhysicalGeometryQualification.Error, .unavailableContinuousMode(state))
            }
        }
        XCTAssertThrowsError(try policy.controls(for: length, tracking: .continuous,
            trackingFact: .init(state: .supported, evidence: .unobserved)))
        XCTAssertThrowsError(try policy.controls(for: MediaGeometryRequest(lengthDots: 1_501), tracking: .continuous,
            trackingFact: supported))
    }

    func testKnownRasterContainmentAccountsForHomeWithoutOverflow() throws {
        let bitmap = try MonochromeBitmap(width: 8, height: 2, bytes: [0x80, 0x80])
        let fitting = try MediaGeometryRequest(widthDots: 10, lengthDots: 3, originXDot: 2, originYDot: 1)
        try policy.validateRaster(bitmap, request: fitting, tracking: .continuous, trackingFact: supported)
        for request in [try MediaGeometryRequest(widthDots: 7),
                       try MediaGeometryRequest(widthDots: 10, originXDot: 3, originYDot: 0),
                       try MediaGeometryRequest(widthDots: 10, originXDot: 100, originYDot: 0)] {
            XCTAssertThrowsError(try policy.validateRaster(bitmap, request: request)) {
                XCTAssertEqual($0 as? PhysicalGeometryQualification.Error, .rasterExceedsWidth)
            }
        }
        for request in [try MediaGeometryRequest(lengthDots: 1),
                       try MediaGeometryRequest(lengthDots: 3, originXDot: 0, originYDot: 2),
                       try MediaGeometryRequest(lengthDots: 3, originXDot: 0, originYDot: 200)] {
            XCTAssertThrowsError(try policy.validateRaster(bitmap, request: request, tracking: .continuous, trackingFact: supported)) {
                XCTAssertEqual($0 as? PhysicalGeometryQualification.Error, .rasterExceedsLength)
            }
        }
        // Unknown home is not promoted to an observed zero; only width is controlled.
        try policy.validateRaster(bitmap, request: MediaGeometryRequest(widthDots: 8))
    }
}
