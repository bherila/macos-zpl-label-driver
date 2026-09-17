import XCTest
@testable import LabelCore

final class DiagnosticErrorRedactionTests: XCTestCase {
    func testIdentifierErrorsRedactDescriptionsAndNestedDumpsWhilePreservingTypedValues() throws {
        let privateValue = "synthetic-private.example.test/identifier"
        let errors: [any Swift.Error] = [
            VirtualQueueError.invalidSelector(privateValue),
            VirtualQueueError.duplicateQueueID(privateValue),
            WorkflowProfileDraft.Error.regionNotFound(privateValue),
            ExtractionPlanError.missingAnchor(page: 1, anchorID: privateValue),
            ExtractionPlanError.ambiguousAnchor(page: 2, anchorID: privateValue),
            ReferenceWorkflowError.requiresTeachOnce(workflowID: privateValue),
        ]
        for error in errors {
            XCTAssertFalse(String(describing: error).contains(privateValue))
            XCTAssertFalse(String(reflecting: error).contains(privateValue))
            var output = ""
            dump([error], to: &output)
            XCTAssertFalse(output.contains(privateValue))
        }
        XCTAssertNotEqual(String(describing: errors[0]), String(describing: errors[1]))
        guard case let .invalidSelector(value) = errors[0] as? VirtualQueueError else {
            return XCTFail("typed identifier must remain available")
        }
        XCTAssertEqual(value, privateValue)
        XCTAssertEqual(errors[1] as? VirtualQueueError, .duplicateQueueID(privateValue))
        XCTAssertEqual(errors[2] as? WorkflowProfileDraft.Error, .regionNotFound(privateValue))
        XCTAssertEqual(errors[3] as? ExtractionPlanError, .missingAnchor(page: 1, anchorID: privateValue))
        XCTAssertEqual(errors[4] as? ExtractionPlanError, .ambiguousAnchor(page: 2, anchorID: privateValue))
        XCTAssertEqual(errors[5] as? ReferenceWorkflowError, .requiresTeachOnce(workflowID: privateValue))
        XCTAssertThrowsError(try ImmutableProfileReference(id: privateValue, revision: 1,
            sha256: String(repeating: "a", count: 64))) {
            XCTAssertEqual($0 as? VirtualQueueError, .invalidSelector(privateValue))
            XCTAssertFalse(String(describing: $0).contains(privateValue))
        }
    }
}
