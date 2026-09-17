import Foundation
import XCTest
@testable import LabelCore

final class OffsetControlQualificationTests: XCTestCase {
    private let fact = CapabilityFact(state: .supported, evidence: .documentedModel(sourceID: "synthetic-offset-fixture"))
    private var policy: OffsetControlQualification {
        .init(blackMark: .init(fact: fact, range: -10...20), shiftLeft: .init(fact: fact, range: -30...40),
              labelTop: .init(fact: fact, range: -5...6))
    }

    func testEachSignedModelIntervalAndZeroProducesExactDocumentedBytes() throws {
        for values in [(-10, -30, -5), (0, 0, 0), (20, 40, 6)] {
            let request = OffsetControlRequest(blackMarkOffsetDots: values.0, shiftLeftDots: values.1, labelTopDots: values.2)
            XCTAssertEqual(try ZPLDocumentedControlEncoder().encodeOffsets(request, policy: policy,
                tracking: .blackMark, trackingFact: fact), Data("^MNM,\(values.0)\n^LS\(values.1)\n^LT\(values.2)\n".utf8))
        }
        XCTAssertEqual(try ZPLDocumentedControlEncoder().encodeOffsets(.init(shiftLeftDots: 0), policy: policy), Data("^LS0\n".utf8))
    }

    func testValuesInsideProtocolButOutsideModelAreRejectedWithoutClamp() throws {
        for value in [-11, 21, Int.min, Int.max] {
            XCTAssertThrowsError(try policy.controls(for: .init(blackMarkOffsetDots: value), tracking: .blackMark, trackingFact: fact))
        }
        for value in [-31, 41, Int.min, Int.max] {
            XCTAssertThrowsError(try policy.controls(for: .init(shiftLeftDots: value)))
        }
        for value in [-6, 7, Int.min, Int.max] {
            XCTAssertThrowsError(try policy.controls(for: .init(labelTopDots: value)))
        }
    }

    func testEachQualificationNeedsItsOwnEvidencedRange() throws {
        let unknown = CapabilityFact(state: .unknown, evidence: .unobserved)
        let unsupported = CapabilityFact(state: .unsupported, evidence: .documentedModel(sourceID: "synthetic-offset-fixture"))
        for component in OffsetControlQualification.Component.allCases {
            for bad in [QualifiedDotRange(fact: fact, range: nil), .init(fact: unknown, range: 0...0),
                        .init(fact: unsupported, range: 0...0), .init(fact: .init(state: .supported, evidence: .unobserved), range: 0...0),
                        .init(fact: fact, range: Int.min...Int.max)] {
                var limits = [policy.blackMark, policy.shiftLeft, policy.labelTop]
                limits[OffsetControlQualification.Component.allCases.firstIndex(of: component)!] = bad
                XCTAssertThrowsError(try OffsetControlQualification(blackMark: limits[0], shiftLeft: limits[1], labelTop: limits[2]).validateDeclaration())
            }
        }
        XCTAssertNoThrow(try OffsetControlQualification.unverified.validateDeclaration())
        XCTAssertThrowsError(try OffsetControlQualification.unverified.controls(for: .init(shiftLeftDots: 0))) {
            XCTAssertEqual($0 as? OffsetControlQualification.Error, .unavailable(.shiftLeft, .unknown))
        }
    }

    func testBlackMarkRequiresModeOffsetAndSeparateTrackingQualification() throws {
        let request = OffsetControlRequest(blackMarkOffsetDots: 0)
        for mode: MediaTracking? in [nil, .gap, .continuous] {
            XCTAssertThrowsError(try policy.controls(for: request, tracking: mode, trackingFact: fact))
        }
        XCTAssertThrowsError(try policy.controls(for: .init(shiftLeftDots: 0), tracking: .blackMark, trackingFact: fact)) {
            XCTAssertEqual($0 as? OffsetControlQualification.Error, .blackMarkOffsetRequired)
        }
        XCTAssertThrowsError(try policy.controls(for: request, tracking: .blackMark))
        XCTAssertThrowsError(try policy.controls(for: .init()))
    }

    func testCompositionStillRejectsCompetingTrackingAndOutputLimit() throws {
        let controls = try policy.controls(for: .init(blackMarkOffsetDots: 0), tracking: .blackMark, trackingFact: fact)
        XCTAssertThrowsError(try ZPLDocumentedControlEncoder().encode(controls + [.gapTracking],
            qualification: [.blackMarkTracking: .supported, .gapTracking: .supported], limits: .init(blackMarkOffsetDots: -10...20)))
        XCTAssertThrowsError(try ZPLDocumentedControlEncoder(maximumOutputBytes: 1).encodeOffsets(.init(shiftLeftDots: 0), policy: policy))
        let bytes = try ZPLDocumentedControlEncoder().encodeOffsets(.init(shiftLeftDots: 0, labelTopDots: 0), policy: policy)
        for forbidden in ["^J", "~J", "^DF", "^ID"] { XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(forbidden)) }
    }
}
