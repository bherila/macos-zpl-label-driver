import CryptoKit
import Darwin
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

/// The combined `finishing-preview` contract: one shared budget, one analysis of
/// the accepted original, and unchanged cancellation/timeout/uncertainty rules.
/// Nothing here admits a queue, reaches a device or authorizes replay.
final class FinishingPreviewBudgetTests: XCTestCase {
    private let documented = CapabilityFact(state: .supported,
        evidence: .documentedModel(sourceID: "synthetic-finishing-preview"))

    /// A deterministic monotonic clock. Each reading advances by one fixed step,
    /// so a shared budget can be exhausted without waiting for wall-clock time.
    private final class SteppedClock: @unchecked Sendable {
        private let lock = NSLock()
        private let origin = ContinuousClock.Instant.now
        private let step: Duration
        private var reads = 0
        init(step: Duration) { self.step = step }
        func next() -> ContinuousClock.Instant {
            lock.lock(); defer { lock.unlock() }
            let instant = origin.advanced(by: step * reads); reads += 1; return instant
        }
    }

    private func root() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FinishingPreviewBudget-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    private func profile() throws -> PrinterProfile {
        let base = try PrinterProfile.gc420dUSBReference(revision: 11)
        return try .init(schemaVersion: 8, revision: base.revision,
            capabilities: .init(model: "synthetic-finishing-preview", thermalTransfer: base.capabilities.thermalTransfer,
                cutter: documented, peeler: documented, rewind: documented, tracking: base.capabilities.tracking,
                printSpeedChoicesIps: base.capabilities.printSpeedChoicesIps, darkness: documented,
                directThermal: documented),
            installedHardware: .init(transport: .usb, selectedFinishing: .tearOff,
                cutter: .init(state: .supported, evidence: .reportedInstallation),
                peeler: .init(state: .supported, evidence: .reportedInstallation),
                observedSpeedIps: nil, observedDarkness: nil, observedTracking: nil),
            media: base.media, connection: base.connection,
            configuredDefaults: .init(thermalMethod: .directThermal),
            thermalMedia: .init(method: .observed(.directThermal, evidence: .reportedInstallation),
                ribbonPresent: .observed(false, evidence: .reportedInstallation)),
            finishingConfiguration: .init(finishing: .init(
                modes: Dictionary(uniqueKeysWithValues: [FinishingMode.tearOff, .cut, .peel, .rewind].map { ($0, documented) }),
                enabledModes: [.tearOff, .cut, .peel, .rewind], installed: .init(
                    cutter: .observed(true, evidence: .reportedInstallation),
                    peeler: .observed(true, evidence: .reportedInstallation),
                    rewinder: .observed(true, evidence: .reportedInstallation))),
                stock: .init(media: base.media, compatibleModes: Dictionary(uniqueKeysWithValues:
                    [FinishingMode.tearOff, .cut, .peel, .rewind].map { ($0, Observation<Bool>.observed(true, evidence: .reportedInstallation)) })),
                schedules: .init(everyLabel: documented, batch: documented, endOfJob: documented,
                    maximumBatchSize: 3)))
    }
    private func originalSource() throws -> (Data, URL) {
        var repository = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repository.deleteLastPathComponent() }
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        return (try Data(contentsOf: repository.appendingPathComponent("Fixtures/generated/native-vector.pdf")),
            repository.appendingPathComponent("Packages/LabelMac/.build/\(configuration)/label-render-worker"))
    }

    private struct Fixture {
        let reference: AcceptedFinishingReference
        let job: AcceptedFinishingJob
        let workflows: WorkflowProfileStore
        let printers: PrinterProfileStore
        let queues: FinishingQueueStore
        let worker: URL
    }

    /// A non-trivial analysis path: the real vector original is analyzed for a
    /// structural border anchor and split into two regions at two copies, so the
    /// preview exercises four output labels rather than a single trivial page.
    private func previewFixture() throws -> Fixture {
        let (source, worker) = try originalSource()
        let pages = try OfflineLayoutWorker.analyze(originalPDF: source, structuralPages: [1], workerExecutable: worker)
        let border = try XCTUnwrap(pages[0].anchors?.first { $0.kind == .border })
        let r = root(), workflows = try WorkflowProfileStore(root: r), printers = try PrinterProfileStore(root: r)
        let p = try profile()
        let w = try WorkflowProfile(id: "synthetic-preview-original", revision: 1, outputStockID: "nominal-4x6",
            outputStock: PhysicalSize(width: try Millimeters.inches(4), height: try Millimeters.inches(6)),
            pageRules: [WorkflowPageRule(sourcePage: 1, expectedInput: ExpectedInputPage(uprightPhysicalSize: pages[0].pageBox.effectivePhysicalSize()),
                disposition: .extract([ExtractionRegion(id: "left", normalizedRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1), outputOrder: 0),
                                       ExtractionRegion(id: "right", normalizedRect: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1), outputOrder: 1)]),
                structuralAnchors: [StructuralAnchorExpectation(id: "border", kind: .border, normalizedRect: border.normalizedRect)])])
        try workflows.save(w); try workflows.confirmForUnattendedUse(w)
        let pr = try printers.save(id: "synthetic-printer", profile: p), queues = try FinishingQueueStore(root: r)
        let q = try FinishingQueueDefinition(id: "synthetic-finishing", revision: 1, displayName: "Synthetic preview",
            physicalDevice: .init(sha256: String(repeating: "a", count: 64)),
            workflowProfile: .init(id: w.id, schemaVersion: w.schemaVersion, revision: w.revision,
                sha256: digest(WorkflowProfileJSON.encode(w))),
            printerProfile: pr, defaultSelection: .init(mode: .cut, schedule: .batch(size: 3, cutRemainderAtJobEnd: true)),
            workflowDefaults: .init(printSpeedIps: 3, darkness: 9), validatingWorkflow: w, validatingPrinter: p)
        let ref = try queues.save(q, workflowStore: workflows, printerStore: printers)
        let geometry = try FinishingDeviceGeometry(printer: printers.load(id: pr.id, revision: pr.revision), physicalDevice: q.physicalDevice,
            nativePitch: .observed(DotResolution(xDotsPerMillimeter: 1, yDotsPerMillimeter: 1), evidence: .documentedModel(sourceID: "synthetic-pitch")))
        let job = try AcceptedFinishingJob.accept(acceptanceID: "synthetic-preview-budget",
            cancellationSHA256: digest(Data("synthetic-preview-token".utf8)), queueReference: ref, queueStore: queues,
            workflowStore: workflows, printerStore: printers, geometry: geometry, originalPDF: source,
            copyOwnership: .engine(copies: 2, collated: false), pageRangeOwnership: .engine(selectedSourcePages: [1]),
            controls: .init(darkness: 0), workerExecutable: worker)
        return Fixture(reference: try AcceptedFinishingJobStore(root: r).save(job), job: job,
            workflows: workflows, printers: printers, queues: queues, worker: worker)
    }

    /// A finite pass-through that records each operation flag and execs the real
    /// worker. It parses nothing, reaches no device and produces no output of its own.
    private func countingWorker(_ worker: URL) throws -> (URL, URL) {
        let tools = root()
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let log = tools.appendingPathComponent("invocations"), wrapper = tools.appendingPathComponent("label-render-worker")
        try Data("#!/bin/sh\nprintf '%s\\n' \"$1\" >> \"\(log.path)\"\nexec \"\(worker.path)\" \"$@\"\n".utf8).write(to: wrapper)
        XCTAssertEqual(chmod(wrapper.path, 0o500), 0)
        return (wrapper, log)
    }
    private func invocations(_ log: URL, flag: String) -> Int {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").filter { String($0) == flag }.count
    }
    private func hasStore(_ root: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)
    }

    func testFinishingPreviewSharesOneBudgetAndAnalysesTheAcceptedOriginalOnce() throws {
        let fixture = try previewFixture(), catalog = fixture.workflows.root
        let expected = try AcceptedFinishingJobStore(root: catalog).prepare(reference: fixture.reference,
            queueStore: fixture.queues, workflowStore: fixture.workflows, printerStore: fixture.printers,
            workerExecutable: fixture.worker)
        XCTAssertEqual(expected.preparation.rasters.count, 4)
        let (counting, log) = try countingWorker(fixture.worker)
        let destination = catalog.appendingPathComponent("synthetic-shared-budget-preview")
        let command = try FinishingPreviewCommand(arguments: ["--catalog", catalog.path,
            "--accepted-id", fixture.reference.acceptanceID, "--accepted-sha", fixture.reference.sha256,
            "--preview-dir", destination.path, "--json"])
        let deadline = try FinishingDeadline()
        let before = try deadline.remaining()
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: command.run(workerExecutable: counting, deadline: deadline)) as? [String: Any])
        XCTAssertEqual(result["outputLabelCount"] as? Int, 4)
        XCTAssertEqual(result["acceptedRecordSHA256"] as? String, fixture.reference.sha256)
        XCTAssertEqual(result["hardwareCompletion"] as? String, "unknown")
        XCTAssertEqual(result["automaticReplayAuthorized"] as? Bool, false)
        // One accepted load, not four: the command analyzes the accepted original
        // once for acceptance and once for preparation's page accounting, then
        // renders each output label. Four accepted loads would report five.
        XCTAssertEqual(invocations(log, flag: "--analysis-directory"), 2)
        XCTAssertEqual(invocations(log, flag: "--job-directory"), 4)
        // One budget spans inspection, preparation and export, so the whole
        // command draws from the single reading taken before it started.
        XCTAssertLessThan(try deadline.remaining(), before)
        for (index, raster) in expected.preparation.rasters.enumerated() {
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(String(format: "label-%05d.pbm", index + 1))), raster.pbmData())
        }
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: destination.appendingPathComponent("preview.json"))) as? [String: Any])
        XCTAssertEqual(manifest["sourceSHA256"] as? String, fixture.job.sourceSHA256)
        XCTAssertEqual(manifest["hardwareCompletion"] as? String, "unknown")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: destination.path).contains { $0.hasSuffix(".zpl") })
        XCTAssertFalse(hasStore(catalog, "accepted-finishing-attempts"))
        XCTAssertFalse(hasStore(catalog, "accepted-finishing-cancellations"))
    }

    func testFinishingPreviewBudgetSpentDuringInspectionTimesOutBeforePreparation() throws {
        let fixture = try previewFixture(), catalog = fixture.workflows.root
        let (counting, log) = try countingWorker(fixture.worker)
        let destination = catalog.appendingPathComponent("synthetic-exhausted-budget-preview")
        let command = try FinishingPreviewCommand(arguments: ["--catalog", catalog.path,
            "--accepted-id", fixture.reference.acceptanceID, "--accepted-sha", fixture.reference.sha256,
            "--preview-dir", destination.path])
        // Thirty seconds per reading: inspection alone spends the whole budget,
        // which a second independent clock for preparation would have hidden.
        let clock = SteppedClock(step: .seconds(30))
        let deadline = try FinishingDeadline(seconds: 60, cancellation: .init(), now: { clock.next() })
        XCTAssertThrowsError(try command.run(workerExecutable: counting, deadline: deadline)) {
            XCTAssertEqual($0 as? AcceptedFinishingJob.Error, .timedOut)
        }
        XCTAssertEqual(invocations(log, flag: "--analysis-directory"), 1)
        XCTAssertEqual(invocations(log, flag: "--job-directory"), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: catalog.path).contains { $0.hasPrefix(".packed-preview-") })
        XCTAssertFalse(hasStore(catalog, "accepted-finishing-attempts"))
    }

    func testFinishingPreviewCancellationVetoesPreparationExportAndRecoveryReads() throws {
        let fixture = try previewFixture(), catalog = fixture.workflows.root
        let store = try AcceptedFinishingJobStore(root: catalog)
        let (counting, log) = try countingWorker(fixture.worker)
        let destination = catalog.appendingPathComponent("synthetic-cancelled-preview")
        let command = try FinishingPreviewCommand(arguments: ["--catalog", catalog.path,
            "--accepted-id", fixture.reference.acceptanceID, "--accepted-sha", fixture.reference.sha256,
            "--preview-dir", destination.path])
        let early = OfflineRenderWorkerCancellation(); early.cancel()
        XCTAssertThrowsError(try command.run(workerExecutable: counting, deadline: FinishingDeadline(cancellation: early))) {
            XCTAssertEqual($0 as? AcceptedFinishingJob.Error, .cancelled)
        }
        XCTAssertEqual(invocations(log, flag: "--analysis-directory"), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let live = OfflineRenderWorkerCancellation()
        let shared = try FinishingDeadline(cancellation: live)
        let inspected = try command.inspection.observe(workerExecutable: fixture.worker, deadline: shared)
        XCTAssertEqual(inspected.recovery.observation, .noRecordedIntent(cancellationRequested: false))
        live.cancel()
        XCTAssertThrowsError(try store.prepare(validated: inspected.context, workerExecutable: fixture.worker, deadline: shared)) {
            XCTAssertEqual($0 as? AcceptedFinishingJob.Error, .cancelled)
        }
        XCTAssertThrowsError(try AcceptedFinishingRecovery.inspect(validated: inspected.context,
            attemptStore: AcceptedFinishingAttemptStore(root: catalog),
            cancellationStore: AcceptedFinishingCancellationStore(root: catalog), deadline: shared)) {
            XCTAssertEqual($0 as? AcceptedFinishingJob.Error, .cancelled)
        }
        XCTAssertThrowsError(try AcceptedFinishingAttemptStore(root: catalog).recoveryObservation(validated: inspected.context, deadline: shared)) {
            XCTAssertEqual($0 as? AcceptedFinishingJob.Error, .cancelled)
        }
        // Preparation that completed before cancellation still exports nothing.
        let prepared = try store.prepare(validated: inspected.context, workerExecutable: fixture.worker, deadline: FinishingDeadline())
        let late = OfflineRenderWorkerCancellation(); late.cancel()
        let output = catalog.appendingPathComponent("synthetic-cancelled-export")
        XCTAssertThrowsError(try PackedFinishingPreviewExport.write(prepared, toNewDirectory: output,
            deadline: FinishingDeadline(cancellation: late))) {
            XCTAssertEqual($0 as? AcceptedFinishingJob.Error, .cancelled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(hasStore(catalog, "accepted-finishing-attempts"))
        XCTAssertFalse(hasStore(catalog, "accepted-finishing-cancellations"))
    }

    // The export's inner budget is a relative DispatchTime span drawn once from the
    // shared deadline. DispatchTime stops while the machine sleeps and ContinuousClock
    // does not, so the inner span can still have time left after the shared deadline
    // expired. A stepped clock reproduces that divergence without sleeping: the inner
    // write runs and publishes under a live relative span, and only the shared deadline
    // is past. The export must report that as uncertainty rather than a clean success,
    // and must not unpublish what it already committed.
    func testExportRechecksTheSharedDeadlineAfterPublishing() throws {
        let fixture = try previewFixture(), catalog = fixture.workflows.root
        let store = try AcceptedFinishingJobStore(root: catalog)
        let prepared = try store.prepare(validated: try store.validatedContext(reference: fixture.reference,
            queueStore: fixture.queues, workflowStore: fixture.workflows, printerStore: fixture.printers,
            workerExecutable: fixture.worker, deadline: FinishingDeadline()),
            workerExecutable: fixture.worker, deadline: FinishingDeadline())
        // Reads: 0 sets the origin and expiry, 1 draws the inner span (30s left, so the
        // write runs normally), 2 is the post-publication re-check and lands exactly on
        // expiry. Nothing sleeps.
        let clock = SteppedClock(step: .seconds(30))
        let deadline = try FinishingDeadline(seconds: 60, cancellation: .init(), now: { clock.next() })
        let output = catalog.appendingPathComponent("synthetic-overrun-export")
        XCTAssertThrowsError(try PackedFinishingPreviewExport.write(prepared, toNewDirectory: output,
                                                                    deadline: deadline)) {
            XCTAssertEqual($0 as? PackedFinishingPreviewExport.Error, .commitUncertain)
        }
        // Publication happened before the budget was re-checked, so the directory stays.
        // Uncertainty is about the budget, never a reason to roll back a committed export.
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("preview.json").path))
        // Still no intent, cancellation or delivery authority anywhere on this path.
        XCTAssertFalse(hasStore(catalog, "accepted-finishing-attempts"))
        XCTAssertFalse(hasStore(catalog, "accepted-finishing-cancellations"))
    }

    func testValidatedFinishingContextIsNotReusableAcrossCatalogs() throws {
        let fixture = try previewFixture(), catalog = fixture.workflows.root
        let deadline = try FinishingDeadline()
        let context = try AcceptedFinishingJobStore(root: catalog).validatedContext(reference: fixture.reference,
            queueStore: fixture.queues, workflowStore: fixture.workflows, printerStore: fixture.printers,
            workerExecutable: fixture.worker, deadline: deadline)
        XCTAssertEqual(context.job, fixture.job)
        XCTAssertEqual(context.reference, fixture.reference)
        let other = root()
        XCTAssertThrowsError(try AcceptedFinishingJobStore(root: other).prepare(validated: context,
            workerExecutable: fixture.worker, deadline: deadline)) {
            XCTAssertEqual($0 as? AcceptedFinishingJobStore.Error, .contextMismatch)
        }
        XCTAssertThrowsError(try AcceptedFinishingCancellationStore(root: other).monitor(validated: context, deadline: deadline)) {
            XCTAssertEqual($0 as? AcceptedFinishingCancellationStore.Error, .contextMismatch)
        }
        XCTAssertThrowsError(try AcceptedFinishingAttemptStore(root: other).recoveryObservation(validated: context, deadline: deadline)) {
            XCTAssertEqual($0 as? AcceptedFinishingAttemptStore.Error, .contextMismatch)
        }
        XCTAssertThrowsError(try AcceptedFinishingRecovery.inspect(validated: context,
            attemptStore: AcceptedFinishingAttemptStore(root: other),
            cancellationStore: AcceptedFinishingCancellationStore(root: other), deadline: deadline)) {
            XCTAssertEqual($0 as? AcceptedFinishingCancellationStore.Error, .contextMismatch)
        }
        XCTAssertFalse(hasStore(other, "accepted-finishing-jobs"))
    }

    func testFinishingDeadlineIsOneFailClosedBudget() throws {
        for invalid in [Double(0), -1, 61, .nan, .infinity] {
            XCTAssertThrowsError(try FinishingDeadline(seconds: invalid)) {
                XCTAssertEqual($0 as? AcceptedFinishingJob.Error, .invalidLimit)
            }
        }
        let clock = SteppedClock(step: .seconds(20))
        let deadline = try FinishingDeadline(seconds: 60, cancellation: .init(), now: { clock.next() })
        XCTAssertEqual(try deadline.remaining(), 40, accuracy: 0.001)
        XCTAssertEqual(try deadline.remaining(), 20, accuracy: 0.001)
        XCTAssertThrowsError(try deadline.remaining()) { XCTAssertEqual($0 as? AcceptedFinishingJob.Error, .timedOut) }
        XCTAssertThrowsError(try deadline.check()) { XCTAssertEqual($0 as? AcceptedFinishingJob.Error, .timedOut) }
        let cancellation = OfflineRenderWorkerCancellation(); cancellation.cancel()
        let cancelled = try FinishingDeadline(cancellation: cancellation)
        XCTAssertThrowsError(try cancelled.remaining()) { XCTAssertEqual($0 as? AcceptedFinishingJob.Error, .cancelled) }
        XCTAssertLessThanOrEqual(try FinishingDeadline().remaining(), FinishingDeadline.maximumSeconds)
    }
}
