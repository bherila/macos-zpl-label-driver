import Foundation
import XCTest
@testable import LabelMac

/// Correctness uses the product's finite budget. Short-deadline enforcement
/// remains tested with deliberately stalled workers in separate scenarios.
enum NativeBarcodeCorrectnessBudget {
    static let seconds = OfflineRenderWorkerProcess.defaultDeadlineSeconds
}

final class NativeBarcodeCorrectnessBudgetTests: XCTestCase {
    func testAllRealBarcodeCorrectnessScenariosUseTheNamedProductionBudget() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sites: [(String, String, Int)] = [
            ("OfflineLayoutWorkerTests.swift", "testRealBarcodeChildUsesOriginalQuartzRasterAndCanonicalFixturePlacement", 2),
            ("OfflineLayoutWorkerTests.swift", "testRealNonLabelPageReturnsObservedEmptyBarcodeLocationsWithoutAnalyzingOtherPage", 1),
            ("SyntheticInertJobPipelineTests.swift", "testBarcodeLocationValidationFeedsOriginalPreparedBytesAndRejectsChangedAnchor", 3),
            ("WorkflowDocumentOpeningModelTests.swift", "testSavedBarcodeProfileReopensWithRealWorkerAndRequiresFreshBoundsReview", 4),
        ]
        XCTAssertEqual(NativeBarcodeCorrectnessBudget.seconds, 60)
        for (file, name, expectedCalls) in sites {
            let source = try String(contentsOf: directory.appending(path: file), encoding: .utf8)
            let start = try XCTUnwrap(source.range(of: "    func \(name)("))
            let remainder = source[start.lowerBound...]
            let end = remainder.dropFirst().range(of: "\n    func ")?.lowerBound ?? source.endIndex
            let body = String(source[start.lowerBound..<end])
            let regex = try NSRegularExpression(pattern: "(?:preparationDeadlineSeconds|deadlineSeconds): ([^,\\n)]+)")
            let matches = regex.matches(in: body, range: NSRange(body.startIndex..., in: body))
            XCTAssertEqual(matches.count, expectedCalls, name)
            for match in matches {
                let range = try XCTUnwrap(Range(match.range(at: 1), in: body))
                XCTAssertEqual(String(body[range]), "NativeBarcodeCorrectnessBudget.seconds", name)
            }
        }
    }
}
