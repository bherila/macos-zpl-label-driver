import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import XCTest
import LabelCore
import Vision
@testable import LabelMac

final class SyntheticInertJobPipelineTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let workflows: WorkflowProfileStore
        let printers: PrinterProfileStore
        let queues: VirtualQueueStore
        let active: ActiveVirtualQueueStore
        let jobs: AcceptedJobStore
        let pipeline: SyntheticInertJobPipeline
        let physicalDevice: PhysicalDeviceCoordinationID
        let leaseDirectory: URL
        let queue: VirtualQueueDefinition
        let selection: ActiveVirtualQueueSelection
        let printer: PrinterProfile
    }

    func testThreeReferenceSheetsPreserveInputGeometryThroughCompleteInertPipeline() throws {
        let references: [(String, String, Double, Double)] = [
            ("native-vector", "native-4x6", 288, 432),
            ("letter-one", "letter-to-4x6", 612, 792),
            ("a4-one", "a4-to-4x6", 595.2756, 841.8898),
        ]
        var bitmaps: [MonochromeBitmap] = []
        var payloads: [Data] = []
        var sourceDigests: Set<String> = []
        for (name, workflowID, widthPoints, heightPoints) in references {
            let original = try Data(contentsOf: fixtureURL("\(name).pdf"))
            let fixture = try makeFixture(workflowSource: original,
                regionOverride: referenceRegion(name), workflowID: workflowID,
                queueID: "shipping-\(workflowID)")
            let workflow = try fixture.workflows.load(profileID: workflowID, revision: 1)
            let input = try XCTUnwrap(workflow.pageRules.first).expectedInput.uprightPhysicalSize
            XCTAssertEqual(input.width.value, widthPoints * 25.4 / 72, accuracy: 1e-8)
            XCTAssertEqual(input.height.value, heightPoints * 25.4 / 72, accuracy: 1e-8)
            XCTAssertEqual(workflow.outputStockID, "nominal-4x6")
            XCTAssertEqual(workflow.outputStock.width.value, 101.6, accuracy: 1e-8)
            XCTAssertEqual(workflow.outputStock.height.value, 152.4, accuracy: 1e-8)
            let path = fixture.root.appending(path: "source.pdf")
            try original.write(to: path, options: .withoutOverwriting)
            let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { return XCTFail("could not open synthetic source") }
            defer { close(descriptor) }
            let result = try fixture.pipeline.run(queueID: fixture.queue.id,
                sourcePDFDescriptor: descriptor, acceptanceID: "reference-\(name)",
                cancellationToken: Data("synthetic cancellation capability".utf8),
                scenario: try InertDeliveryScenario(maximumChunkBytes: 4_096))
            XCTAssertEqual(result.outputLabelCount, 1)
            XCTAssertEqual(result.delivery, .transmitted(byteCount: result.preparedByteCount))
            let bundle = try fixture.jobs.load(acceptanceID: result.acceptanceID,
                queueStore: fixture.queues, workflowStore: fixture.workflows,
                printerStore: fixture.printers)
            XCTAssertEqual(bundle.sourcePDF, original)
            XCTAssertEqual(bundle.ticket.workflowProfile, fixture.queue.workflowProfile)
            sourceDigests.insert(bundle.ticket.sourceDocumentSHA256)
            let stored = try AcceptedJobStateStore(acceptedJobStore: fixture.jobs).loadPrepared(
                acceptanceID: result.acceptanceID, queueStore: fixture.queues,
                workflowStore: fixture.workflows, printerStore: fixture.printers)
            let plan = try ExtractionPlanner.plan(
                analyzedPages: OfflineLayoutWorker.analyze(originalPDF: bundle.sourcePDF,
                    structuralPages: [1], workerExecutable: renderWorkerExecutable()),
                profile: workflow)
            let label = try XCTUnwrap(plan.outputLabels.first)
            XCTAssertEqual(label.sourceRect.width, 288, accuracy: 1e-8)
            XCTAssertEqual(label.sourceRect.height, 432, accuracy: 1e-8)
            let canvas = try DotCanvas(physicalSize: workflow.outputStock,
                resolution: DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8))
            XCTAssertEqual(canvas.bitmapLayout.width, 813)
            XCTAssertEqual(canvas.bitmapLayout.height, 1219)
            let prepared = try QuartzPlannedExtraction.prepare(originalPDF: bundle.sourcePDF,
                label: label, canvas: canvas,
                conversion: bundle.ticket.monochromeConversion)
            XCTAssertEqual(prepared.previewPBM, prepared.bitmap.pbmData())
            let encoded = try ZPLPreparedLabelEncoder().prepare(bitmap: prepared.bitmap,
                profile: fixture.printer, workflowDefaults: PrinterControlDefaults(
                    thermalMethod: fixture.queue.workflowDefaults.thermalMethod,
                    finishing: fixture.queue.workflowDefaults.finishing,
                    printSpeedIps: fixture.queue.workflowDefaults.printSpeedIps))
            XCTAssertEqual(encoded.resolvedControls, stored.resolvedControls)
            XCTAssertEqual(stored.bytes, encoded.bytes)
            try assertSyntheticBarcodesDecodeFromFinalBitmap(prepared.bitmap, fixtureName: name)
            bitmaps.append(prepared.bitmap)
            payloads.append(stored.bytes)
        }
        XCTAssertEqual(sourceDigests.count, 3)
        let letterPixels = bitmaps[1].grayscalePreview().pixels
        let a4Pixels = bitmaps[2].grayscalePreview().pixels
        let differences = letterPixels.indices.filter { letterPixels[$0] != a4Pixels[$0] }
        XCTAssertEqual(differences.count, 0, "Letter/A4 artwork must agree at every dot")
        XCTAssertEqual(digest(Data(bitmaps[1].bytes)), digest(Data(bitmaps[2].bytes)))
        XCTAssertEqual(digest(payloads[1]), digest(payloads[2]))
        // The supplied native PDF alone has sheet-corner markers inside the
        // label. Exclude only their <=6-point edge extent; all shared artwork
        // (including both barcode types and the frame) must agree dot for dot.
        let native = bitmaps[0].grayscalePreview().pixels
        let letter = bitmaps[1].grayscalePreview().pixels
        for y in 24..<(1219 - 24) {
            let row = (y * 813 + 24)..<(y * 813 + 813 - 24)
            XCTAssertEqual(Array(native[row]), Array(letter[row]), "shared artwork row \(y)")
        }
        XCTAssertNotEqual(bitmaps[0], bitmaps[1], "native corner markers must remain visible")
    }

    /// Test-only synthetic payload decoding. The image expands the encoder's
    /// exact packed bits at one pixel per printer dot; no PDF rerender, analysis
    /// thumbnail, crop, interpolation or upsampling enters this oracle.
    private func assertSyntheticBarcodesDecodeFromFinalBitmap(
        _ bitmap: MonochromeBitmap, fixtureName: String
    ) throws {
        let observations = try decodeFinalBitmap(bitmap)
        XCTAssertEqual(observations.count, 2, fixtureName)
        for symbology in [VNBarcodeSymbology.code128, .qr] {
            let matches = observations.filter { $0.symbology == symbology }
            XCTAssertEqual(matches.count, 1, "\(fixtureName): \(symbology)")
            XCTAssertEqual(matches.first?.payloadStringValue, "LPD-TEST-A-001",
                "\(fixtureName): \(symbology)")
        }
    }

    func testFinalBitmapBarcodeOracleDoesNotInventSymbolsOnBlankStock() throws {
        let blank = try MonochromeBitmap(width: 813, height: 1219,
            bytes: Array(repeating: 0, count: 124_338))
        XCTAssertTrue(try decodeFinalBitmap(blank).isEmpty)
    }

    private func decodeFinalBitmap(_ bitmap: MonochromeBitmap) throws -> [VNBarcodeObservation] {
        let raster = bitmap.grayscalePreview()
        let provider = try XCTUnwrap(CGDataProvider(data: Data(raster.pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: raster.width, height: raster.height,
            bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: raster.bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: .init(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let request = VNDetectBarcodesRequest()
        request.revision = VNDetectBarcodesRequestRevision3
        request.symbologies = [.code128, .qr]
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        return try XCTUnwrap(request.results)
    }

    func testReferenceLetterWorkflowRejectsChangedWrongSizedAndUnconfiguredIntake() throws {
        let original = try Data(contentsOf: fixtureURL("letter-one.pdf"))
        let fixture = try makeFixture(workflowSource: original,
            regionOverride: referenceRegion("letter-one"), workflowID: "letter-one",
            queueID: "shipping-letter-one")
        for (name, queueID, expected) in [
            ("layout-changed", fixture.queue.id, SyntheticInertJobPipeline.Error.layoutRejected),
            ("a4-one", fixture.queue.id, .layoutRejected),
            ("letter-one", "unconfigured-sheet", .configurationUnavailable),
        ] {
            let path = fixture.root.appending(path: "\(name)-\(queueID).pdf")
            try Data(contentsOf: fixtureURL("\(name).pdf")).write(to: path, options: .withoutOverwriting)
            let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { return XCTFail("could not open synthetic source") }
            defer { close(descriptor) }
            let acceptanceID = "rejected-\(name)"
            XCTAssertThrowsError(try fixture.pipeline.run(queueID: queueID,
                sourcePDFDescriptor: descriptor, acceptanceID: acceptanceID,
                cancellationToken: Data("synthetic cancellation capability".utf8),
                scenario: try InertDeliveryScenario())) {
                XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, expected)
            }
            XCTAssertNil(try fixture.jobs.loadIfPresent(acceptanceID: acceptanceID,
                queueStore: fixture.queues, workflowStore: fixture.workflows,
                printerStore: fixture.printers))
        }
    }

    // Test-source manifest coordinates are explicit fixture evidence, not a
    // guessed crop or a product profile schema. Never regenerate this oracle.
    private func referenceRegion(_ id: String) throws -> LabelCore.NormalizedRect {
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with:
            Data(contentsOf: fixtureURL("manifest.json"))) as? [String: Any])
        let fixtures = try XCTUnwrap(manifest["fixtures"] as? [[String: Any]])
        let fixture = try XCTUnwrap(fixtures.first { $0["id"] as? String == id })
        let pages = try XCTUnwrap(fixture["pages"] as? [[String: Any]])
        XCTAssertEqual(pages.count, 1)
        let regions = try XCTUnwrap(pages.first?["regions"] as? [[String: Any]])
        XCTAssertEqual(regions.count, 1)
        let rect = try XCTUnwrap(regions.first?["rawRect"] as? [Double])
        XCTAssertEqual(rect.count, 4)
        let box = try XCTUnwrap(QuartzPDFRenderer.documentPageBoxes(
            originalPDF: Data(contentsOf: fixtureURL("\(id).pdf"))).first)
        XCTAssertEqual(box.originX, 0)
        XCTAssertEqual(box.originY, 0)
        XCTAssertEqual(box.rotationDegreesClockwise, 0)
        // The writer rounds A4 box coordinates in the committed PDF. Bind the
        // explicit raw fixture region to those actual bytes, not the manifest's
        // pre-serialization normalized dimensions. No region is inferred.
        return try NormalizedRect(x: rect[0] / box.width,
            y: (box.height - rect[1] - rect[3]) / box.height,
            width: rect[2] / box.width, height: rect[3] / box.height)
    }

    func testDescriptorBoundPDFIsAcceptedPreparedAndInertlyDelivered() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original)
        let submittedPath = fixture.root.appending(path: "scheduler-input.pdf")
        try original.write(to: submittedPath, options: .withoutOverwriting)
        let descriptor = open(
            submittedPath.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
        )
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        let moved = fixture.root.appending(path: "opened-source.pdf")
        try FileManager.default.moveItem(at: submittedPath, to: moved)
        try Data("not the opened PDF".utf8).write(
            to: submittedPath, options: .withoutOverwriting
        )

        let result = try fixture.pipeline.run(
            queueID: "shipping-native",
            sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-intake-1",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario(maximumChunkBytes: 4_096)
        )
        XCTAssertEqual(result.acceptanceID, "synthetic-intake-1")
        XCTAssertEqual(result.outputLabelCount, 1)
        XCTAssertGreaterThan(result.preparedByteCount, 0)
        XCTAssertEqual(
            result.delivery, .transmitted(byteCount: result.preparedByteCount)
        )

        let bundle = try fixture.jobs.load(
            acceptanceID: result.acceptanceID,
            queueStore: fixture.queues,
            workflowStore: fixture.workflows,
            printerStore: fixture.printers
        )
        XCTAssertEqual(bundle.sourcePDF, original)
        XCTAssertEqual(bundle.ticket.sourceDocumentSHA256, digest(original))
        XCTAssertEqual(bundle.ticket.copyOwnership, .upstreamAlreadyExpanded)
        XCTAssertEqual(bundle.ticket.pageRangeOwnership, .upstreamAlreadyApplied)
        XCTAssertEqual(bundle.ticket.intakeProvenance, .cupsScheduler)

        let stored = try AcceptedJobStateStore(
            acceptedJobStore: fixture.jobs
        ).loadPrepared(
            acceptanceID: result.acceptanceID,
            queueStore: fixture.queues,
            workflowStore: fixture.workflows,
            printerStore: fixture.printers
        )
        XCTAssertEqual(stored.bytes.count, result.preparedByteCount)
        XCTAssertTrue(stored.bytes.starts(with: Data("^XA\n".utf8)))
        guard case .transmitted = stored.state.phase else {
            return XCTFail("expected persisted transmitted state")
        }
    }

    func testUnexpectedPageIsRejectedBeforeAcceptedBundlePublication() throws {
        let native = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let extraPages = try Data(contentsOf: fixtureURL("copy-order.pdf"))
        XCTAssertGreaterThan(
            try QuartzPDFRenderer.documentPageBoxes(originalPDF: extraPages).count, 1
        )
        let fixture = try makeFixture(workflowSource: native)
        let path = fixture.root.appending(path: "unexpected-pages.pdf")
        try extraPages.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        XCTAssertThrowsError(try fixture.pipeline.run(
            queueID: "shipping-native",
            sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-unexpected-pages",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .layoutRejected)
        }
        XCTAssertThrowsError(try fixture.jobs.load(
            acceptanceID: "synthetic-unexpected-pages",
            queueStore: fixture.queues,
            workflowStore: fixture.workflows,
            printerStore: fixture.printers
        ))
    }

    func testBarcodeLocationValidationFeedsOriginalPreparedBytesAndRejectsChangedAnchor() throws {
        // Correctness uses the production bound; dedicated tests exercise short deadlines.
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let analyzed = try OfflineLayoutWorker.analyze(originalPDF: original,
            structuralPages: [1], workerExecutable: renderWorkerExecutable(), barcodePages: [1], deadlineSeconds: OfflineRenderWorkerProcess.defaultDeadlineSeconds)
        let barcode = try XCTUnwrap(analyzed[0].anchors?.first { $0.kind == .barcodeLike })
        var outputs: [Data] = []
        let expectations: [ObservedPageAnchor?] = [nil, barcode]
        for expectation in expectations {
            let fixture = try makeFixture(workflowSource: original, anchorOverride: expectation)
            let path = fixture.root.appending(path: "synthetic-barcode-source.pdf")
            try original.write(to: path, options: .withoutOverwriting)
            let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            XCTAssertGreaterThanOrEqual(descriptor, 0)
            defer { close(descriptor) }
            let result = try fixture.pipeline.run(queueID: "shipping-native",
                sourcePDFDescriptor: descriptor, acceptanceID: "synthetic-barcode-bound",
                cancellationToken: Data("synthetic cancellation capability".utf8),
                scenario: try InertDeliveryScenario(), preparationDeadlineSeconds: OfflineRenderWorkerProcess.defaultDeadlineSeconds)
            XCTAssertEqual(result.outputLabelCount, 1)
            XCTAssertEqual(result.delivery, .transmitted(byteCount: result.preparedByteCount))
            let prepared = try AcceptedJobStateStore(acceptedJobStore: fixture.jobs).loadPrepared(
                acceptanceID: result.acceptanceID, queueStore: fixture.queues,
                workflowStore: fixture.workflows, printerStore: fixture.printers)
            outputs.append(prepared.bytes)
            XCTAssertEqual(try fixture.jobs.load(acceptanceID: result.acceptanceID,
                queueStore: fixture.queues, workflowStore: fixture.workflows,
                printerStore: fixture.printers).sourcePDF, original)
        }
        XCTAssertEqual(outputs[0], outputs[1], "location analysis must not replace the original print source")

        let wrong = ObservedPageAnchor(kind: .barcodeLike,
            normalizedRect: try NormalizedRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1))
        let rejected = try makeFixture(workflowSource: original, anchorOverride: wrong)
        let path = rejected.root.appending(path: "synthetic-layout-mismatch.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        XCTAssertThrowsError(try rejected.pipeline.run(queueID: "shipping-native",
            sourcePDFDescriptor: descriptor, acceptanceID: "synthetic-barcode-rejected",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario(), preparationDeadlineSeconds: OfflineRenderWorkerProcess.defaultDeadlineSeconds)) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .layoutRejected)
        }
        XCTAssertThrowsError(try rejected.jobs.load(acceptanceID: "synthetic-barcode-rejected",
            queueStore: rejected.queues, workflowStore: rejected.workflows, printerStore: rejected.printers))
    }

    func testRetryableWaitingStateResumesThroughPipelineEntryPoint() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original)
        let path = fixture.root.appending(path: "retryable-waiting.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        let first = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-waiting-retry",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario(failBeforeTransmission: true)
        )
        XCTAssertEqual(first.delivery, .failedBeforeTransmission)
        XCTAssertTrue(first.delivery.mayRetryAutomatically)
        XCTAssertThrowsError(try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-waiting-retry",
            cancellationToken: Data("wrong cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .acceptanceFailed)
        }
        XCTAssertThrowsError(try fixture.pipeline.run(
            queueID: "different-queue", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-waiting-retry",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .acceptanceFailed)
        }

        let laterQueue = try VirtualQueueDefinition(
            id: fixture.queue.id,
            revision: fixture.queue.revision + 1,
            displayName: fixture.queue.displayName,
            physicalDevice: fixture.queue.physicalDevice,
            workflowProfile: fixture.queue.workflowProfile,
            printerProfile: fixture.queue.printerProfile,
            workflowDefaults: fixture.queue.workflowDefaults,
            validatingAgainst: fixture.printer
        )
        let laterReference = try fixture.queues.save(
            laterQueue, workflowStore: fixture.workflows,
            printerStore: fixture.printers
        )
        _ = try fixture.active.compareAndSwap(
            queue: laterReference, expected: fixture.selection,
            queueStore: fixture.queues, workflowStore: fixture.workflows,
            printerStore: fixture.printers
        )

        let retry = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-waiting-retry",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )
        XCTAssertEqual(
            retry.delivery, .transmitted(byteCount: first.preparedByteCount)
        )
        XCTAssertEqual(retry.preparedByteCount, first.preparedByteCount)
    }

    func testRetryableDeviceContentionResumesPreparedArtifact() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original)
        let path = fixture.root.appending(path: "retryable-contention.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        let held = try PhysicalDeviceLease(
            acquiring: PhysicalDeviceIdentity(coordinationID: fixture.physicalDevice),
            inExistingDirectory: fixture.leaseDirectory
        )

        let first = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-contention-retry",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )
        XCTAssertEqual(first.delivery, .deviceBusy)
        XCTAssertTrue(first.delivery.mayRetryAutomatically)
        held.release()

        let retry = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-contention-retry",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )
        XCTAssertEqual(
            retry.delivery, .transmitted(byteCount: first.preparedByteCount)
        )
    }

    func testPreparedByteBudgetStopsMultiLabelJobWithoutPublishingPayload() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(
            workflowSource: original, regionCount: 2,
            maximumPreparedBytes: 400_000
        )
        let path = fixture.root.appending(path: "bounded-multi-label.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        XCTAssertThrowsError(try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-bounded-payload",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .preparationFailed)
        }
        let state = try AcceptedJobStateStore(
            acceptedJobStore: fixture.jobs
        ).load(
            acceptanceID: "synthetic-bounded-payload",
            queueStore: fixture.queues,
            workflowStore: fixture.workflows,
            printerStore: fixture.printers
        )
        XCTAssertEqual(state.phase, .accepted)
    }

    func testWorkflowStockMustMatchObservedLoadedFace() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(
            workflowSource: original, useMismatchedOutputStock: true
        )
        let path = fixture.root.appending(path: "stock-mismatch.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        XCTAssertThrowsError(try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-stock-mismatch",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )) {
            XCTAssertEqual(
                $0 as? SyntheticInertJobPipeline.Error, .configurationUnavailable
            )
        }
        XCTAssertThrowsError(try fixture.jobs.load(
            acceptanceID: "synthetic-stock-mismatch",
            queueStore: fixture.queues,
            workflowStore: fixture.workflows,
            printerStore: fixture.printers
        ))
    }

    func testPersistedUncertaintyIsReturnedWithoutReplayOnReentry() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original)
        let path = fixture.root.appending(path: "persisted-uncertainty.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        let first = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-persisted-uncertain",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario(
                maximumChunkBytes: 2, becomeAmbiguousAfterBytes: 3
            )
        )
        XCTAssertEqual(first.delivery, .uncertain(bytesAccepted: 3))
        let states = AcceptedJobStateStore(acceptedJobStore: fixture.jobs)
        let before = try states.load(
            acceptanceID: first.acceptanceID,
            queueStore: fixture.queues, workflowStore: fixture.workflows,
            printerStore: fixture.printers
        )

        let recovered = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: first.acceptanceID,
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )
        XCTAssertEqual(recovered, first)
        XCTAssertEqual(try states.load(
            acceptanceID: first.acceptanceID,
            queueStore: fixture.queues, workflowStore: fixture.workflows,
            printerStore: fixture.printers
        ), before)
    }

    func testPersistedTransmissionIsReturnedWithoutSecondDelivery() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original)
        let path = fixture.root.appending(path: "persisted-transmission.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        let first = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-persisted-transmitted",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )
        let recovered = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: first.acceptanceID,
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario(becomeAmbiguousAfterBytes: 0)
        )
        XCTAssertEqual(recovered, first)
    }

    func testUnavailableAnalysisWorkerRejectsBeforeAcceptanceOrSendIntent() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original,
            workerOverride: URL(fileURLWithPath: "/nonexistent-label-render-worker"))
        let path = fixture.root.appending(path: "scheduler-input.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        XCTAssertThrowsError(try fixture.pipeline.run(queueID: "shipping-native",
            sourcePDFDescriptor: descriptor, acceptanceID: "synthetic-worker-unavailable",
            cancellationToken: Data("synthetic capability".utf8), scenario: InertDeliveryScenario())) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .layoutRejected)
        }
        let bundle = try fixture.jobs.loadIfPresent(acceptanceID: "synthetic-worker-unavailable",
            queueStore: fixture.queues, workflowStore: fixture.workflows, printerStore: fixture.printers)
        XCTAssertNil(bundle)
    }

    func testProcessingCancellationIsCheckedBeforeInputAdmission() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original)
        let cancellation = OfflineRenderWorkerCancellation()
        cancellation.cancel()
        XCTAssertThrowsError(try fixture.pipeline.run(queueID: "shipping-native",
            sourcePDFDescriptor: -1, acceptanceID: "synthetic-pre-cancelled",
            cancellationToken: Data("synthetic capability".utf8), scenario: InertDeliveryScenario(),
            processingCancellation: cancellation)) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .processingCancelled)
        }
        XCTAssertNil(try fixture.jobs.loadIfPresent(acceptanceID: "synthetic-pre-cancelled",
            queueStore: fixture.queues, workflowStore: fixture.workflows, printerStore: fixture.printers))
    }

    func testAnalysisTimeoutAndLiveCancellationDoNotPublishAcceptance() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original,
            workerOverride: URL(fileURLWithPath: "/usr/bin/yes"))
        let path = fixture.root.appending(path: "scheduler-input.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        let start = ContinuousClock.now
        XCTAssertThrowsError(try fixture.pipeline.run(queueID: "shipping-native",
            sourcePDFDescriptor: descriptor, acceptanceID: "synthetic-preparation-timeout",
            cancellationToken: Data("synthetic capability".utf8), scenario: InertDeliveryScenario(),
            preparationDeadlineSeconds: 0.1)) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .preparationDeadlineExceeded)
        }
        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
        let cancellation = OfflineRenderWorkerCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(50)) {
            cancellation.cancel()
        }
        XCTAssertThrowsError(try fixture.pipeline.run(queueID: "shipping-native",
            sourcePDFDescriptor: descriptor, acceptanceID: "synthetic-live-cancelled",
            cancellationToken: Data("synthetic capability".utf8), scenario: InertDeliveryScenario(),
            preparationDeadlineSeconds: 5, processingCancellation: cancellation)) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .processingCancelled)
        }
        for id in ["synthetic-preparation-timeout", "synthetic-live-cancelled"] {
            XCTAssertNil(try fixture.jobs.loadIfPresent(acceptanceID: id,
                queueStore: fixture.queues, workflowStore: fixture.workflows, printerStore: fixture.printers))
        }
    }

    private func renderWorkerExecutable() throws -> URL {
        let root = fixtureURL("native-vector.pdf").deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let executable = root.appending(path: "Packages/LabelMac/.build/\(configuration)/label-render-worker")
        return try XCTUnwrap(FileManager.default.isExecutableFile(atPath: executable.path) ? executable : nil)
    }

    func testQualifiedMotorSpeedDefaultsReachCompletePersistedInertJob() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original, regionCount: 2,
                                      qualifiedMotorSpeeds: true)
        let path = fixture.root.appending(path: "motor-source.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return XCTFail("could not open synthetic PDF") }
        defer { close(descriptor) }
        let result = try fixture.pipeline.run(queueID: fixture.queue.id,
            sourcePDFDescriptor: descriptor, acceptanceID: "synthetic-motor-job",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario(maximumChunkBytes: 4096))
        XCTAssertEqual(result.outputLabelCount, 2)
        XCTAssertEqual(result.delivery, .transmitted(byteCount: result.preparedByteCount))
        let bundle = try fixture.jobs.load(acceptanceID: result.acceptanceID,
            queueStore: fixture.queues, workflowStore: fixture.workflows, printerStore: fixture.printers)
        XCTAssertEqual(bundle.ticket.schemaVersion, 3)
        XCTAssertEqual(bundle.ticket.controls.printSpeedIps, .value(3))
        XCTAssertEqual(bundle.ticket.controls.feedSpeedIps, .value(4))
        XCTAssertEqual(bundle.ticket.controls.backfeedSpeedIps, .value(3))
        let stored = try AcceptedJobStateStore(acceptedJobStore: fixture.jobs).loadPrepared(
            acceptanceID: result.acceptanceID, queueStore: fixture.queues,
            workflowStore: fixture.workflows, printerStore: fixture.printers)
        XCTAssertEqual(stored.resolvedControls, bundle.ticket.controls)
        let text = String(decoding: stored.bytes, as: UTF8.self)
        XCTAssertEqual(text.components(separatedBy: "^PR3,4,3\n").count - 1, 2)
        XCTAssertFalse(text.contains("^PR3,2,2\n"))
        XCTAssertEqual(text.components(separatedBy: "^XA\n").count - 1, 2)
        XCTAssertEqual(stored.bytes.count, result.preparedByteCount)
    }

    func testQualifiedDarknessAndMotorDefaultsReachSameImmutableInertJob() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original, regionCount: 2,
                                      qualifiedMotorSpeeds: true, qualifiedDarkness: true)
        let path = fixture.root.appending(path: "synthetic-darkness-source.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        let result = try fixture.pipeline.run(queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-darkness-bound", cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario(maximumChunkBytes: 4_096))
        let bundle = try fixture.jobs.load(acceptanceID: result.acceptanceID,
            queueStore: fixture.queues, workflowStore: fixture.workflows, printerStore: fixture.printers)
        XCTAssertEqual(bundle.ticket.printerProfile.schemaVersion, 4)
        XCTAssertEqual(bundle.ticket.queue.schemaVersion, 3)
        XCTAssertEqual(bundle.ticket.schemaVersion, 4)
        XCTAssertEqual(try fixture.printers.load(reference: bundle.ticket.printerProfile).configuredDefaults.darkness, 10)
        XCTAssertEqual(bundle.ticket.controls.darkness, .value(20))
        XCTAssertEqual(bundle.ticket.controls.feedSpeedIps, .value(4))
        let stored = try AcceptedJobStateStore(acceptedJobStore: fixture.jobs).loadPrepared(
            acceptanceID: result.acceptanceID, queueStore: fixture.queues,
            workflowStore: fixture.workflows, printerStore: fixture.printers)
        XCTAssertEqual(stored.resolvedControls, bundle.ticket.controls)
        let text = String(decoding: stored.bytes, as: UTF8.self)
        XCTAssertEqual(text.components(separatedBy: "^MD0\n~SD20\n").count - 1, 2)
        XCTAssertEqual(text.components(separatedBy: "^PR3,4,3\n").count - 1, 2)
        XCTAssertFalse(text.contains("~SD10\n"))
        XCTAssertEqual(result.delivery, .transmitted(byteCount: stored.bytes.count))
    }


    func testQualifiedGeometryDefaultsReachOriginalCompletePersistedInertJob() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original, regionCount: 2,
            qualifiedMotorSpeeds: true, qualifiedDarkness: true, qualifiedGeometry: true)
        let path = fixture.root.appending(path: "synthetic-geometry-source.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        let result = try fixture.pipeline.run(queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-geometry-bound", cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario(maximumChunkBytes: 4_096))
        let bundle = try fixture.jobs.load(acceptanceID: result.acceptanceID,
            queueStore: fixture.queues, workflowStore: fixture.workflows, printerStore: fixture.printers)
        XCTAssertEqual(bundle.ticket.schemaVersion, 5)
        XCTAssertEqual(bundle.ticket.printerProfile.schemaVersion, 5)
        XCTAssertEqual(bundle.ticket.queue.schemaVersion, 4)
        XCTAssertEqual(bundle.ticket.controls.mediaGeometry, .value(try .init(widthDots: 813, lengthDots: 1_300, originXDot: 0, originYDot: 0)))
        let stored = try AcceptedJobStateStore(acceptedJobStore: fixture.jobs).loadPrepared(
            acceptanceID: result.acceptanceID, queueStore: fixture.queues,
            workflowStore: fixture.workflows, printerStore: fixture.printers)
        XCTAssertEqual(stored.resolvedControls, bundle.ticket.controls)
        let text = String(decoding: stored.bytes, as: UTF8.self)
        XCTAssertEqual(text.components(separatedBy: "^MNN\n^LL1300\n^PW813\n^LH0,0\n").count - 1, 2)
        XCTAssertFalse(text.contains("^LL1400\n"))
        XCTAssertFalse(text.contains("^PW832\n"))
        XCTAssertEqual(text.components(separatedBy: "^XA\n").count - 1, 2)
        XCTAssertEqual(result.delivery, .transmitted(byteCount: stored.bytes.count))
    }

    func testQualifiedOffsetsBindStoredTicketAndEveryOriginalPDFLabel() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original, regionCount: 2, qualifiedMotorSpeeds: true,
                                      qualifiedDarkness: true, qualifiedOffsets: true)
        let path = fixture.root.appending(path: "synthetic-offset-source.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        let result = try fixture.pipeline.run(queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-offset-bound", cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario(maximumChunkBytes: 4_096))
        let bundle = try fixture.jobs.load(acceptanceID: result.acceptanceID, queueStore: fixture.queues,
            workflowStore: fixture.workflows, printerStore: fixture.printers)
        XCTAssertEqual(bundle.ticket.schemaVersion, 6)
        XCTAssertEqual(bundle.ticket.printerProfile.schemaVersion, 6)
        XCTAssertEqual(bundle.ticket.queue.schemaVersion, 5)
        XCTAssertEqual(bundle.ticket.controls.offsets, .value(.init(shiftLeftDots: 0, labelTopDots: 1)))
        let stored = try AcceptedJobStateStore(acceptedJobStore: fixture.jobs).loadPrepared(
            acceptanceID: result.acceptanceID, queueStore: fixture.queues, workflowStore: fixture.workflows, printerStore: fixture.printers)
        XCTAssertEqual(stored.resolvedControls, bundle.ticket.controls)
        let text = String(decoding: stored.bytes, as: UTF8.self)
        XCTAssertEqual(text.components(separatedBy: "^MNN\n^LL1300\n^PW813\n^LH0,0\n^LS0\n^LT1\n").count - 1, 2)
        XCTAssertFalse(text.contains("^LT0\n"))
        XCTAssertEqual(result.delivery, .transmitted(byteCount: stored.bytes.count))
    }

    func testThermalDeclarationsBindTicketPreparedSnapshotAndEveryOriginalPDFLabel() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original, regionCount: 2, qualifiedMotorSpeeds: true,
                                      qualifiedDarkness: true, qualifiedOffsets: true, qualifiedThermal: true)
        let path = fixture.root.appending(path: "synthetic-thermal-source.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        let result = try fixture.pipeline.run(queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-thermal-bound", cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario(maximumChunkBytes: 4_096))
        let bundle = try fixture.jobs.load(acceptanceID: result.acceptanceID, queueStore: fixture.queues,
            workflowStore: fixture.workflows, printerStore: fixture.printers)
        XCTAssertEqual(bundle.ticket.schemaVersion, 7)
        XCTAssertEqual(bundle.ticket.printerProfile.schemaVersion, 7)
        XCTAssertEqual(bundle.ticket.queue.schemaVersion, 6)
        XCTAssertEqual(bundle.ticket.controls.offsets, .value(.init(shiftLeftDots: 0, labelTopDots: 1)))
        let stored = try AcceptedJobStateStore(acceptedJobStore: fixture.jobs).loadPrepared(
            acceptanceID: result.acceptanceID, queueStore: fixture.queues, workflowStore: fixture.workflows, printerStore: fixture.printers)
        XCTAssertEqual(stored.resolvedControls, bundle.ticket.controls)
        XCTAssertEqual(bundle.ticket.controls.thermalMethod, .value(.directThermal))
        XCTAssertEqual(stored.profileSnapshot.thermalMedia, .init(
            method: .observed(.directThermal, evidence: .reportedInstallation),
            ribbonPresent: .observed(false, evidence: .reportedInstallation)))
        let text = String(decoding: stored.bytes, as: UTF8.self)
        XCTAssertEqual(text.components(separatedBy: "^MTD\n").count - 1, 2)
        XCTAssertFalse(text.contains("^MTT"))
        XCTAssertEqual(text.components(separatedBy: "^MNN\n^LL1300\n^PW813\n^LH0,0\n^LS0\n^LT1\n").count - 1, 2)
        XCTAssertFalse(text.contains("^LT0\n"))
        XCTAssertEqual(result.delivery, .transmitted(byteCount: stored.bytes.count))
    }

    private func makeFixture(
        workflowSource: Data,
        regionCount: Int = 1,
        maximumPreparedBytes: Int = PreparedJobPayload.maximumBytes,
        useMismatchedOutputStock: Bool = false,
        workerOverride: URL? = nil,
        anchorOverride: ObservedPageAnchor? = nil,
        regionOverride: LabelCore.NormalizedRect? = nil,
        workflowID: String = "native-4x6-local",
        queueID: String = "shipping-native",
        qualifiedMotorSpeeds: Bool = false,
        qualifiedDarkness: Bool = false,
        qualifiedGeometry: Bool = false,
        qualifiedOffsets: Bool = false,
        qualifiedThermal: Bool = false
    ) throws -> Fixture {
        let geometryEnabled = qualifiedGeometry || qualifiedOffsets
        let root = FileManager.default.temporaryDirectory.appending(
            path: "SyntheticInertJobPipeline-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let workflows = try WorkflowProfileStore(root: root)
        let printers = try PrinterProfileStore(root: root)
        let queues = try VirtualQueueStore(root: root)
        let active = try ActiveVirtualQueueStore(root: root)
        let jobs = try AcceptedJobStore(root: root)

        let box = try XCTUnwrap(
            QuartzPDFRenderer.documentPageBoxes(originalPDF: workflowSource).first
        )
        let analyzed = try QuartzStructuralAnalyzer.analyzeBorders(
            originalPDF: workflowSource, pageNumber: 1
        )
        let observed = try anchorOverride ?? XCTUnwrap(analyzed.anchors?.first)
        let stock = if useMismatchedOutputStock {
            PhysicalSize(
                width: try Millimeters.inches(2),
                height: try Millimeters.inches(3)
            )
        } else {
            PhysicalSize(
                width: try Millimeters.inches(4),
                height: try Millimeters.inches(6)
            )
        }
        let regions = try (0..<regionCount).map { index in
            try ExtractionRegion(
                id: "full-page-\(index)",
                normalizedRect: regionOverride ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                outputOrder: index
            )
        }
        let workflow = try WorkflowProfile(
            id: workflowID, revision: 1,
            outputStockID: "nominal-4x6", outputStock: stock,
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(
                    uprightPhysicalSize: try box.effectivePhysicalSize()
                ),
                disposition: .extract(regions),
                structuralAnchors: [try StructuralAnchorExpectation(
                    id: "observed-border",
                    kind: observed.kind,
                    normalizedRect: observed.normalizedRect
                )]
            )]
        )
        try workflows.save(workflow)
        try workflows.confirmForUnattendedUse(workflow)
        let workflowReference = try ImmutableProfileReference(
            id: workflow.id, schemaVersion: workflow.schemaVersion,
            revision: workflow.revision,
            sha256: digest(try WorkflowProfileJSON.encode(workflow))
        )
        let baseline = try PrinterProfile.gc420dUSBReference(revision: 1)
        let c = baseline.capabilities
        let speedFact = CapabilityFact(state: .supported,
            evidence: .documentedModel(sourceID: "synthetic-speed-fixture"))
        func geometryLimit(_ value: Int) -> QualifiedDotLimit { .init(fact: speedFact, maximumDots: value) }
        var tracking = c.tracking
        if geometryEnabled { tracking[.continuous] = speedFact }
        let printer = try (qualifiedMotorSpeeds || qualifiedDarkness || geometryEnabled || qualifiedThermal) ? PrinterProfile(
            schemaVersion: qualifiedThermal ? 7 : (qualifiedOffsets ? 6 : (geometryEnabled ? 5 : (qualifiedDarkness ? 4 : 3))), revision: 1,
            // Hypothetical test qualification only. Preserve the pipeline's
            // documented GC420d pitch guard; do not admit an unknown model.
            capabilities: PrinterCapabilities(model: "GC420d",
                thermalTransfer: c.thermalTransfer, cutter: c.cutter, peeler: c.peeler,
                rewind: c.rewind, tracking: tracking, printSpeedChoicesIps: c.printSpeedChoicesIps,
                darkness: qualifiedDarkness ? .init(state: .supported, evidence: .documentedModel(sourceID: "R45")) : c.darkness,
                feedSpeeds: qualifiedMotorSpeeds ? .init(fact: speedFact, choicesIps: [2, 4]) : .unverified,
                backfeedSpeeds: qualifiedMotorSpeeds ? .init(fact: speedFact, choicesIps: [2, 3]) : .unverified,
                physicalGeometry: geometryEnabled ? .init(width: geometryLimit(832), continuousLength: geometryLimit(1_500),
                    homeX: geometryLimit(100), homeY: geometryLimit(200)) : .unverified,
                offsets: qualifiedOffsets ? .init(blackMark: .init(fact: speedFact, range: -10...20),
                    shiftLeft: .init(fact: speedFact, range: -30...40), labelTop: .init(fact: speedFact, range: -5...6)) : .unverified,
                directThermal: qualifiedThermal ? speedFact : .init(state: .unknown, evidence: .unobserved)),
            installedHardware: baseline.installedHardware, media: baseline.media,
            connection: baseline.connection,
            configuredDefaults: .init(thermalMethod: qualifiedThermal ? .directThermal : nil, printSpeedIps: 3, feedSpeedIps: qualifiedMotorSpeeds ? 2 : nil,
                backfeedSpeedIps: qualifiedMotorSpeeds ? 2 : nil, darkness: qualifiedDarkness ? 10 : nil,
                tracking: geometryEnabled ? .continuous : nil,
                mediaGeometry: geometryEnabled ? MediaGeometryRequest(widthDots: 832, lengthDots: 1_400, originXDot: 0, originYDot: 0) : nil,
                offsets: qualifiedOffsets ? .init(shiftLeftDots: 0, labelTopDots: 0) : nil),
            thermalMedia: qualifiedThermal ? .init(method: .observed(.directThermal, evidence: .reportedInstallation),
                ribbonPresent: .observed(false, evidence: .reportedInstallation)) : .unobserved) : baseline
        let printerReference = try printers.save(id: "gc420d-usb", profile: printer)
        let physicalDevice = try PhysicalDeviceCoordinationID(
            sha256: String(repeating: "d", count: 64)
        )
        let queue = try VirtualQueueDefinition(
            schemaVersion: qualifiedThermal ? 6 : (qualifiedOffsets ? 5 : (geometryEnabled ? 4 : (qualifiedDarkness ? 3 : (qualifiedMotorSpeeds ? 2 : 1)))),
            id: queueID, revision: 1,
            displayName: "Synthetic native labels",
            physicalDevice: physicalDevice,
            workflowProfile: workflowReference,
            printerProfile: printerReference,
            workflowDefaults: PrinterControlRequest(
                thermalMethod: .directThermal,
                finishing: .tearOff,
                printSpeedIps: 3,
                feedSpeedIps: qualifiedMotorSpeeds ? 4 : nil,
                backfeedSpeedIps: qualifiedMotorSpeeds ? 3 : nil,
                darkness: qualifiedDarkness ? 20 : nil,
                tracking: geometryEnabled ? .continuous : nil,
                mediaGeometry: geometryEnabled ? MediaGeometryRequest(widthDots: 813, lengthDots: 1_300) : nil,
                offsets: qualifiedOffsets ? .init(labelTopDots: 1) : nil
            ),
            validatingAgainst: printer
        )
        let queueReference = try queues.save(
            queue, workflowStore: workflows, printerStore: printers
        )
        _ = try active.compareAndSwap(
            queue: queueReference, expected: nil,
            queueStore: queues, workflowStore: workflows,
            printerStore: printers
        )
        let leases = root.appending(path: "device-leases")
        try FileManager.default.createDirectory(
            at: leases, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return Fixture(
            root: root, workflows: workflows, printers: printers,
            queues: queues, active: active, jobs: jobs,
            pipeline: SyntheticInertJobPipeline(
                activeQueueStore: active,
                queueStore: queues,
                workflowStore: workflows,
                printerStore: printers,
                acceptedJobStore: jobs,
                leaseDirectory: leases,
                workerExecutable: try workerOverride ?? renderWorkerExecutable(),
                maximumPreparedBytes: maximumPreparedBytes
            ),
            physicalDevice: physicalDevice,
            leaseDirectory: leases,
            queue: queue,
            selection: try XCTUnwrap(try active.load(
                queueID: queue.id, queueStore: queues,
                workflowStore: workflows, printerStore: printers
            )),
            printer: printer
        )
    }

    private func fixtureURL(_ name: String) -> URL {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root.appending(path: "Fixtures/generated/\(name)")
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
