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

    func testRealBarcodeChildUsesOriginalQuartzRasterAndCanonicalFixturePlacement() throws {
        // Correctness uses the production bound; dedicated tests exercise short deadlines.
        let source = try fixture("native-vector")
        let analyzed = try OfflineLayoutWorker.analyze(originalPDF: source,
            structuralPages: [1], workerExecutable: worker(), barcodePages: [1], deadlineSeconds: NativeBarcodeCorrectnessBudget.seconds)
        let page = try XCTUnwrap(analyzed.first)
        XCTAssertEqual(page.pageBox, try QuartzPDFRenderer.pageBox(originalPDF: source, pageNumber: 1))
        let locations = try XCTUnwrap(page.anchors).filter { $0.kind == .barcodeLike }
        XCTAssertFalse(locations.isEmpty, "the supplied synthetic QR must be observed, not skipped")
        XCTAssertLessThanOrEqual(locations.count, QuartzBarcodeAnalyzer.maximumObservations)
        // Independent source artwork: QR quiet-zone square at (182,151), size 84,
        // on a 288x432 point page. Vision observes barcode pixels inside that square.
        let quietZone = try NormalizedRect(x: 182.0 / 288, y: (432.0 - 151 - 84) / 432,
            width: 84.0 / 288, height: 84.0 / 432)
        XCTAssertTrue(locations.contains { anchor in
            let r = anchor.normalizedRect
            return r.x >= quietZone.x - 0.01 && r.y >= quietZone.y - 0.01 &&
                r.x + r.width <= quietZone.x + quietZone.width + 0.01 &&
                r.y + r.height <= quietZone.y + quietZone.height + 0.01 &&
                r.width > quietZone.width * 0.5 && r.height > quietZone.height * 0.5
        }, "canonical bounds must discriminate top/bottom and lie inside the original QR artwork: \(locations.map(\.normalizedRect))")
        let borders = try QuartzStructuralAnalyzer.analyzeBorders(originalPDF: source, pageNumber: 1)
        XCTAssertEqual(page.anchors?.filter { $0.kind == .border }, borders.anchors)
        let repeated = try OfflineLayoutWorker.analyze(originalPDF: source,
            structuralPages: [1], workerExecutable: worker(), barcodePages: [1], deadlineSeconds: NativeBarcodeCorrectnessBudget.seconds)
        XCTAssertEqual(repeated, analyzed)
    }

    func testBarcodeRequestsAndUntrustedKindsAreExplicitlyBounded() throws {
        for request in [
            OfflineLayoutWorker.Request(schemaVersion: 1, structuralPages: [], barcodePages: [1]),
            .init(schemaVersion: 1, structuralPages: [1], barcodePages: [1]),
            .init(schemaVersion: 2, structuralPages: [], barcodePages: [1]),
            .init(schemaVersion: 2, structuralPages: [1], barcodePages: [1, 1]),
            .init(schemaVersion: 2, structuralPages: [1], maximumPages: 1, barcodePages: [2])
        ] { XCTAssertThrowsError(try request.validate()) }
        let source = Data("synthetic source".utf8)
        let box = try PDFPageBox(originX: 0, originY: 0, width: 288, height: 432)
        let barcode = ObservedPageAnchor(kind: .barcodeLike,
            normalizedRect: try NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        func result(_ anchors: [ObservedPageAnchor], version: Int = 2) throws -> Data {
            try JSONEncoder().encode(OfflineLayoutWorker.Result(schemaVersion: version,
                sourceSHA256: OfflineLayoutWorker.digest(source), pages: [
                    OfflineLayoutWorker.Page(try AnalyzedSourcePage(pageBox: box, anchors: anchors))]))
        }
        let explicit = OfflineLayoutWorker.Request(schemaVersion: 2, structuralPages: [1], barcodePages: [1])
        XCTAssertEqual(try OfflineLayoutWorker.validate(result([barcode]), originalPDF: source,
            request: explicit)[0].anchors, [barcode])
        XCTAssertThrowsError(try OfflineLayoutWorker.validate(result([barcode], version: 1), originalPDF: source,
            request: .init(schemaVersion: 1, structuralPages: [1])))
        XCTAssertThrowsError(try OfflineLayoutWorker.validate(result([], version: 1), originalPDF: source,
            request: explicit), "an older border-only result cannot acknowledge barcode analysis")
        let unsupported = ObservedPageAnchor(kind: .darkBlock, normalizedRect: barcode.normalizedRect)
        XCTAssertThrowsError(try OfflineLayoutWorker.validate(result([unsupported]), originalPDF: source,
            request: explicit))
        XCTAssertThrowsError(try OfflineLayoutWorker.validate(
            result(Array(repeating: barcode, count: QuartzBarcodeAnalyzer.maximumObservations + 1)),
            originalPDF: source, request: explicit))
    }

    func testRealNonLabelPageReturnsObservedEmptyBarcodeLocationsWithoutAnalyzingOtherPage() throws {
        let analyzed = try OfflineLayoutWorker.analyze(originalPDF: fixture("non-label-pages"),
            structuralPages: [2], workerExecutable: worker(), barcodePages: [2], deadlineSeconds: NativeBarcodeCorrectnessBudget.seconds)
        XCTAssertEqual(analyzed.count, 2)
        XCTAssertNil(analyzed[0].anchors)
        let observed = try XCTUnwrap(analyzed[1].anchors)
        XCTAssertTrue(observed.filter { $0.kind == .barcodeLike }.isEmpty)
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

    func testAllPagesRequestsRetainLimitsAndRequireObservedFacts() throws {
        let source = try fixture("native-vector")
        for (limit, pages) in [(0, []), (1_001, []), (32, [1])] {
            XCTAssertThrowsError(try OfflineLayoutWorker.analyze(originalPDF: source,
                structuralPages: pages, workerExecutable: worker(), maximumSourcePages: limit,
                analyzeAllPages: true)) {
                XCTAssertEqual($0 as? OfflineConversionTicket.TicketError, .malformedJSON)
            }
        }
        let box = try PDFPageBox(originX: 0, originY: 0, width: 288, height: 432)
        let page = OfflineLayoutWorker.Page(try AnalyzedSourcePage(pageBox: box, anchors: nil))
        let data = try JSONEncoder().encode(OfflineLayoutWorker.Result(schemaVersion: 1,
            sourceSHA256: OfflineLayoutWorker.digest(source), pages: [page]))
        XCTAssertThrowsError(try OfflineLayoutWorker.validate(data, originalPDF: source,
            request: .init(schemaVersion: 1, structuralPages: [], maximumPages: 32, analyzeAllPages: true))) {
            XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .invalidResult)
        }
    }
}
