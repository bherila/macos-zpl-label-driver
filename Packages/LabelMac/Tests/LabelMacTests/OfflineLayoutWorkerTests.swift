import Foundation
import LabelCore
import XCTest
@testable import LabelMac

final class OfflineLayoutWorkerTests: XCTestCase {
    private var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: root.appending(path: "Fixtures/generated/\(name).pdf"))
    }

    private func worker() throws -> URL {
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let url = root.appending(path: "Packages/LabelMac/.build/\(configuration)/label-render-worker")
        return try XCTUnwrap(FileManager.default.isExecutableFile(atPath: url.path) ? url : nil)
    }

    func testRealChildPreservesBoxesAndExactStructuralFacts() throws {
        for name in ["native-vector", "letter-one", "layout-changed"] {
            let source = try fixture(name)
            let boxes = try QuartzPDFRenderer.documentPageBoxes(originalPDF: source)
            let bare = try OfflineLayoutWorker.analyze(originalPDF: source,
                structuralPages: [], workerExecutable: worker(), deadlineSeconds: 5)
            XCTAssertEqual(bare.map(\.pageBox), boxes)
            XCTAssertTrue(bare.allSatisfy { $0.anchors == nil })
            let analyzed = try OfflineLayoutWorker.analyze(originalPDF: source,
                structuralPages: [1], workerExecutable: worker(), deadlineSeconds: 5)
            XCTAssertEqual(analyzed[0], try QuartzStructuralAnalyzer.analyzeBorders(
                originalPDF: source, pageNumber: 1))
        }
    }

    func testAnalysisDeadlineAndCancellationUseOwnedChildLifecycle() throws {
        let start = ContinuousClock.now
        XCTAssertThrowsError(try OfflineLayoutWorker.analyze(originalPDF: Data("%PDF".utf8),
            structuralPages: [], workerExecutable: URL(fileURLWithPath: "/usr/bin/yes"),
            deadlineSeconds: 0.05)) {
            XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .timedOut)
        }
        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
        let liveCancellation = OfflineRenderWorkerCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(50)) {
            liveCancellation.cancel()
        }
        XCTAssertThrowsError(try OfflineLayoutWorker.analyze(originalPDF: Data("%PDF".utf8),
            structuralPages: [], workerExecutable: URL(fileURLWithPath: "/usr/bin/yes"),
            deadlineSeconds: 5, cancellation: liveCancellation)) {
            XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .cancelled)
        }
        let cancellation = OfflineRenderWorkerCancellation()
        cancellation.cancel()
        XCTAssertThrowsError(try OfflineLayoutWorker.analyze(originalPDF: Data("%PDF".utf8),
            structuralPages: [], workerExecutable: URL(fileURLWithPath: "/nonexistent-worker"),
            cancellation: cancellation)) {
            XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .cancelled)
        }
    }

    func testInputAndRequestedPageFailuresRemainSanitized() throws {
        for (source, code) in [
            (Data("not a PDF".utf8), OfflineRenderWorkerFailure.Code.inputUnsupported),
            (try fixture("encrypted-input"), .inputEncrypted)
        ] {
            XCTAssertThrowsError(try OfflineLayoutWorker.analyze(originalPDF: source,
                structuralPages: [], workerExecutable: worker(), deadlineSeconds: 5)) {
                XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .jobRejected(code: code))
            }
        }
        XCTAssertThrowsError(try OfflineLayoutWorker.analyze(originalPDF: fixture("native-vector"),
            structuralPages: [2], workerExecutable: worker(), deadlineSeconds: 5)) {
            XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .jobRejected(code: .pageOutOfRange))
        }
        for pages in [[0], [1, 1], [1_001]] {
            XCTAssertThrowsError(try OfflineLayoutWorker.analyze(originalPDF: Data(),
                structuralPages: pages, workerExecutable: URL(fileURLWithPath: "/nonexistent-worker"))) {
                XCTAssertEqual($0 as? OfflineConversionTicket.TicketError, .malformedJSON)
            }
        }
    }

    func testUntrustedLayoutResultRejectsWrongBindingGeometryAndAnchorSemantics() throws {
        let source = Data("synthetic source binding".utf8)
        let box = try PDFPageBox(originX: -10, originY: 20, width: 288, height: 432)
        let page = OfflineLayoutWorker.Page(try AnalyzedSourcePage(pageBox: box, anchors: nil))
        let result = OfflineLayoutWorker.Result(schemaVersion: 1,
            sourceSHA256: OfflineLayoutWorker.digest(source), pages: [page])
        let data = try JSONEncoder().encode(result)
        let request = OfflineLayoutWorker.Request(schemaVersion: 1, structuralPages: [])
        XCTAssertEqual(try OfflineLayoutWorker.validate(data, originalPDF: source, request: request)[0].pageBox, box)
        XCTAssertThrowsError(try OfflineLayoutWorker.validate(data, originalPDF: Data(), request: request))
        XCTAssertThrowsError(try OfflineLayoutWorker.validate(data, originalPDF: source,
            request: .init(schemaVersion: 1, structuralPages: [1])))

        let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var invalidVersion = dictionary
        invalidVersion["schemaVersion"] = 2
        XCTAssertThrowsError(try OfflineLayoutWorker.validate(JSONSerialization.data(withJSONObject: invalidVersion),
            originalPDF: source, request: request))
        let wirePage = try XCTUnwrap((dictionary["pages"] as? [[String: Any]])?.first)
        for modification in [["width": 0.0], ["rotation": 45], ["userUnit": 0.0],
                             ["anchors": [["kind": "barcodeLike", "x": 0, "y": 0, "width": 1, "height": 1]]]] as [[String: Any]] {
            var changedPage = wirePage
            changedPage.merge(modification) { _, new in new }
            var changed = dictionary
            changed["pages"] = [changedPage]
            let expected = OfflineLayoutWorker.Request(schemaVersion: 1,
                structuralPages: modification["anchors"] == nil ? [] : [1])
            XCTAssertThrowsError(try OfflineLayoutWorker.validate(JSONSerialization.data(withJSONObject: changed),
                originalPDF: source, request: expected))
        }
    }

    func testObservedEmptyAnchorsAndAggregateBoundsAreDistinct() throws {
        let source = Data()
        let box = try PDFPageBox(originX: 0, originY: 0, width: 10, height: 10)
        let empty = OfflineLayoutWorker.Page(try AnalyzedSourcePage(pageBox: box, anchors: []))
        let request = OfflineLayoutWorker.Request(schemaVersion: 1, structuralPages: [1])
        let data = try JSONEncoder().encode(OfflineLayoutWorker.Result(schemaVersion: 1,
            sourceSHA256: OfflineLayoutWorker.digest(source), pages: [empty]))
        XCTAssertEqual(try OfflineLayoutWorker.validate(data, originalPDF: source, request: request)[0].anchors, [])
        XCTAssertThrowsError(try OfflineLayoutWorker.validate(data, originalPDF: source,
            request: .init(schemaVersion: 1, structuralPages: [])))
        let anchor = ObservedPageAnchor(kind: .border,
            normalizedRect: try NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        let full = OfflineLayoutWorker.Page(try AnalyzedSourcePage(pageBox: box,
            anchors: Array(repeating: anchor, count: 256)))
        let crowded = try JSONEncoder().encode(OfflineLayoutWorker.Result(schemaVersion: 1,
            sourceSHA256: OfflineLayoutWorker.digest(source), pages: Array(repeating: full, count: 17)))
        XCTAssertThrowsError(try OfflineLayoutWorker.validate(crowded, originalPDF: source,
            request: .init(schemaVersion: 1, structuralPages: Array(1...17)))) {
            XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .outputLimitExceeded)
        }
        XCTAssertThrowsError(try OfflineLayoutWorker.validate(
            Data(repeating: 0, count: OfflineLayoutWorker.maximumOutputBytes + 1),
            originalPDF: source, request: request)) {
            XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .outputLimitExceeded)
        }
    }
}
