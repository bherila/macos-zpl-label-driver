import AppKit
import SwiftUI
import XCTest
@testable import LabelMac

@MainActor
final class WorkflowEditorLayoutTests: XCTestCase {
    func testEditorHasFiniteUsefulHeightInsideVerticalSetupScroll() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let source = try Data(contentsOf: root.appending(path: "Fixtures/generated/letter-one.pdf"))
        let scratch = FileManager.default.temporaryDirectory.appending(path: "editor-layout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = try WorkflowEditorBootstrap.makeModel(originalPDF: source,
            store: WorkflowProfileStore(root: scratch))
        // Vertical scrolling proposes unbounded height to its children. The
        // editor must reserve its own space instead of drawing over siblings.
        for width: CGFloat in [820, 900, 1200] {
            let host = NSHostingView(rootView: WorkflowEditorView(model: model).frame(width: width))
            host.frame = NSRect(x: 0, y: 0, width: width, height: 760)
            host.layoutSubtreeIfNeeded()
            let height = host.fittingSize.height
            XCTAssertTrue(height.isFinite)
            XCTAssertGreaterThanOrEqual(height, 500, "Native split view must reserve usable editor space")
            XCTAssertLessThanOrEqual(height, 900, "Details must scroll within the editor, not expand its allocation")
        }
    }
}
