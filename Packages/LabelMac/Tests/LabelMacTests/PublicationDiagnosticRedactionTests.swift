import Foundation
import XCTest
@testable import LabelMac

final class PublicationDiagnosticRedactionTests: XCTestCase {
    func testAllIdentityBearingUncertainStoreErrorsRedactRoutineDiagnosticsAndPreserveRecoveryValues() throws {
        let id = "synthetic-private-publication"
        let digest = String(repeating: "a", count: 64)
        let identity = ImmutablePublicationIdentity(id: id, schemaVersion: 1, revision: 2, sha256: digest)
        let queue = try FinishingQueueReference(id: id, revision: 2, sha256: digest)
        let artifact = try FinishingArtifactReference(id: id, revision: 2, sha256: digest)
        let accepted = try AcceptedFinishingReference(acceptanceID: id, sha256: digest)
        let values: [Any] = [identity, queue, artifact, accepted,
            VirtualQueueStore.Error.commitUncertain(identity),
            WorkflowProfileStore.Error.commitUncertain(identity),
            PrinterProfileStore.Error.commitUncertain(identity),
            FinishingQueueStore.Error.commitUncertain(queue),
            FinishingArtifactStore.Error.commitUncertain(artifact),
            AcceptedFinishingJobStore.Error.commitUncertain(accepted)]
        for value in values {
            var nestedDump = ""
            dump([value], to: &nestedDump)
            for text in [String(describing: value), String(reflecting: value), nestedDump] {
                XCTAssertFalse(text.contains(id))
                XCTAssertFalse(text.contains(digest))
            }
        }
        XCTAssertEqual(identity.id, id)
        XCTAssertEqual(identity.schemaVersion, 1)
        XCTAssertEqual(identity.revision, 2)
        XCTAssertEqual(identity.sha256, digest)
        XCTAssertEqual(queue.id, id)
        XCTAssertEqual(queue.sha256, digest)
        XCTAssertEqual(artifact.id, id)
        XCTAssertEqual(artifact.sha256, digest)
        XCTAssertEqual(accepted.acceptanceID, id)
        XCTAssertEqual(accepted.sha256, digest)
        XCTAssertEqual(values[4] as? VirtualQueueStore.Error, .commitUncertain(identity))
        XCTAssertEqual(values[5] as? WorkflowProfileStore.Error, .commitUncertain(identity))
        XCTAssertEqual(values[6] as? PrinterProfileStore.Error, .commitUncertain(identity))
        XCTAssertEqual(values[7] as? FinishingQueueStore.Error, .commitUncertain(queue))
        XCTAssertEqual(values[8] as? FinishingArtifactStore.Error, .commitUncertain(artifact))
        XCTAssertEqual(values[9] as? AcceptedFinishingJobStore.Error, .commitUncertain(accepted))
    }
}
