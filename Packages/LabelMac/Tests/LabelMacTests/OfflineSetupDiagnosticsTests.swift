import Foundation
import XCTest
@testable import LabelMac

final class OfflineSetupDiagnosticsTests: XCTestCase {
    @MainActor
    func testUnavailableModelsRemainUnavailableWithoutInventingAcceptance() {
        let report = OfflineSetupDiagnostics(documents: nil, setupAvailable: false,
            setupErrorPresent: true, scratchWarningPresent: true)
        XCTAssertFalse(report.documentModelAvailable)
        XCTAssertFalse(report.editorAvailable)
        XCTAssertTrue(report.setupErrorPresent)
        XCTAssertTrue(report.scratchWarningPresent)
        XCTAssertTrue(report.text.contains("document_model_available=no\n"))
        XCTAssertTrue(report.text.contains("installation_scheduler_hardware_acceptance=not_established_by_this_report\n"))
        XCTAssertEqual(report.text, report.text)
        XCTAssertLessThan(report.text.utf8.count, 1_024)
    }

    @MainActor
    func testActualModelErrorPresenceDoesNotExportPrivatePathsOrErrorDetails() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "synthetic-private-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = WorkflowDocumentOpeningModel(store: try WorkflowProfileStore(root: root),
            workerExecutable: root.appending(path: "synthetic-private-worker"))
        model.reportImportFailure()
        let report = OfflineSetupDiagnostics(documents: model, setupAvailable: true,
            setupErrorPresent: false, scratchWarningPresent: false)
        XCTAssertTrue(report.documentModelAvailable)
        XCTAssertTrue(report.openingErrorPresent)
        XCTAssertFalse(report.editorAvailable)
        XCTAssertFalse(report.exactPreviewAvailable)
        XCTAssertFalse(report.text.contains(root.path))
        XCTAssertFalse(report.text.contains("synthetic-private"))
        XCTAssertFalse(report.text.contains(try XCTUnwrap(model.error)))
        let lines = report.text.split(separator: "\n")
        XCTAssertEqual(lines.count, 18)
        for line in lines.dropFirst(3) {
            let parts = line.split(separator: "=")
            XCTAssertEqual(parts.count, 2)
            XCTAssertTrue(["yes", "no"].contains(String(parts[1])))
        }
    }
}
