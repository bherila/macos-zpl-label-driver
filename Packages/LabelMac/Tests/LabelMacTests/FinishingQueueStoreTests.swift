import CryptoKit
import Darwin
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class FinishingQueueStoreTests: XCTestCase {
    private let documented = CapabilityFact(state: .supported,
        evidence: .documentedModel(sourceID: "synthetic-finishing-queue"))
    private func profile(maximumBatch: Int = 3, model: String = "synthetic-finishing-queue", stock: Observation<Bool> = .observed(true, evidence: .reportedInstallation)) throws -> PrinterProfile {
        let base = try PrinterProfile.gc420dUSBReference(revision: 11)
        return try .init(schemaVersion: 8, revision: base.revision,
            capabilities: .init(model: model, thermalTransfer: base.capabilities.thermalTransfer,
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
                    [FinishingMode.tearOff, .cut, .peel, .rewind].map { ($0, stock) })),
                schedules: .init(everyLabel: documented, batch: documented, endOfJob: documented,
                    maximumBatchSize: maximumBatch)))
    }
    private func workflow(revision: Int = 1) throws -> WorkflowProfile {
        let page = try PDFPageBox(originX: 0, originY: 0, width: 288, height: 432)
        let region = try NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        return try WorkflowProfile(
            id: "native-4x6-local", revision: revision,
            outputStockID: "nominal-4x6",
            outputStock: PhysicalSize(
                width: try Millimeters.inches(4), height: try Millimeters.inches(6)
            ),
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(uprightPhysicalSize: page.effectivePhysicalSize()),
                disposition: .extract([try ExtractionRegion(
                    id: "label", normalizedRect: region,
                    outputOrder: 0
                )]),
                structuralAnchors: [try StructuralAnchorExpectation(
                    id: "border", kind: .border, normalizedRect: region
                )]
            )]
        )
    }

    private func root() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FinishingQueue-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    private func queue(workflow w: WorkflowProfile, printer p: PrinterProfile,
                       printerReference: ImmutableProfileReference, workflowHash: String? = nil,
                       name: String = "Synthetic finishing",
                       defaults: PrinterControlDefaults = .init(printSpeedIps: 3, darkness: 0)) throws -> FinishingQueueDefinition {
        try .init(id: "synthetic-finishing", revision: 1, displayName: name,
            physicalDevice: .init(sha256: String(repeating: "a", count: 64)),
            workflowProfile: .init(id: w.id, schemaVersion: w.schemaVersion, revision: w.revision,
                sha256: workflowHash ?? digest(WorkflowProfileJSON.encode(w))),
            printerProfile: printerReference, defaultSelection: .init(mode: .cut, schedule: .batch(size: 3, cutRemainderAtJobEnd: true)),
            workflowDefaults: defaults, validatingWorkflow: w, validatingPrinter: p)
    }
    func testColdReopenIdempotenceAndConflictPreserveExactPolicy() throws {
        let r = root(), workflows = try WorkflowProfileStore(root: r), printers = try PrinterProfileStore(root: r)
        let w = try workflow(), p = try profile()
        try workflows.save(w); try workflows.confirmForUnattendedUse(w)
        let pr = try printers.save(id: "synthetic-printer", profile: p)
        let q = try queue(workflow: w, printer: p, printerReference: pr)
        let store = try FinishingQueueStore(root: r)
        let ref = try store.save(q, workflowStore: workflows, printerStore: printers)
        XCTAssertEqual(try store.save(q, workflowStore: workflows, printerStore: printers), ref)
        let reopened = try FinishingQueueStore(root: r).load(reference: ref,
            workflowStore: WorkflowProfileStore(root: r), printerStore: PrinterProfileStore(root: r))
        XCTAssertEqual(reopened, q)
        XCTAssertEqual(try reopened.resolve(outputLabelCount: 7, workflow: w, printer: p).plan.cutAfterOutputLabels, [3,6,7])
        XCTAssertThrowsError(try store.save(queue(workflow: w, printer: p, printerReference: pr, name: "Changed"),
            workflowStore: workflows, printerStore: printers)) { XCTAssertEqual($0 as? FinishingQueueStore.Error, .conflict) }
    }
    func testReferenceDigestsAndCompleteSnapshotsAreIndependentlyCheckedBeforePublication() throws {
        let r = root(), workflows = try WorkflowProfileStore(root: r), printers = try PrinterProfileStore(root: r)
        let w = try workflow(), p = try profile()
        try workflows.save(w); try workflows.confirmForUnattendedUse(w)
        let pr = try printers.save(id: "synthetic-printer", profile: p), store = try FinishingQueueStore(root: r)
        let bad = try ImmutableProfileReference(id: pr.id, schemaVersion: pr.schemaVersion, revision: pr.revision, sha256: String(repeating: "0", count:64))
        XCTAssertThrowsError(try store.save(queue(workflow: w, printer: p, printerReference: bad), workflowStore: workflows, printerStore: printers)) {
            XCTAssertEqual($0 as? FinishingQueueStore.Error, .printerReferenceMismatch)
        }
        XCTAssertThrowsError(try store.save(queue(workflow: w, printer: p, printerReference: pr, workflowHash: String(repeating:"0",count:64)), workflowStore: workflows, printerStore: printers)) {
            XCTAssertEqual($0 as? FinishingQueueStore.Error, .workflowReferenceMismatch)
        }
        XCTAssertThrowsError(try store.save(queue(workflow: w, printer: profile(maximumBatch: 4), printerReference: pr), workflowStore: workflows, printerStore: printers)) {
            XCTAssertEqual($0 as? FinishingQueueStore.Error, .snapshotMismatch)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.appendingPathComponent("finishing-queues").path))
    }
    func testUnqualifiedWorkflowNeverPublishes() throws {
        let r = root(), workflows = try WorkflowProfileStore(root:r), printers = try PrinterProfileStore(root:r)
        let w = try workflow(), p = try profile(); try workflows.save(w)
        let pr = try printers.save(id:"synthetic-printer", profile:p)
        XCTAssertThrowsError(try FinishingQueueStore(root:r).save(queue(workflow:w,printer:p,printerReference:pr), workflowStore:workflows,printerStore:printers)) {
            XCTAssertEqual($0 as? FinishingQueueStore.Error, .workflowNotQualified)
        }
    }
    func testAlteredArchiveAndSymlinkFailOnColdRead() throws {
        let r=root(), workflows=try WorkflowProfileStore(root:r), printers=try PrinterProfileStore(root:r)
        let w=try workflow(), p=try profile(); try workflows.save(w); try workflows.confirmForUnattendedUse(w)
        let pr=try printers.save(id:"synthetic-printer",profile:p)
        let store=try FinishingQueueStore(root:r), q=try queue(workflow:w,printer:p,printerReference:pr)
        let ref=try store.save(q,workflowStore:workflows,printerStore:printers)
        let path=r.appendingPathComponent("finishing-queues").appendingPathComponent(FinishingQueueStore.fileName(ref))
        let wrongReference=try FinishingQueueReference(id:ref.id,revision:ref.revision,sha256:String(repeating:"0",count:64))
        XCTAssertThrowsError(try store.load(reference:wrongReference,workflowStore:workflows,printerStore:printers)) {
            XCTAssertEqual($0 as? FinishingQueueStore.Error,.referenceMismatch)
        }
        let original=try Data(contentsOf:path)
        try (original+Data([32])).write(to:path)
        XCTAssertThrowsError(try store.load(reference:ref,workflowStore:workflows,printerStore:printers)) {
            XCTAssertEqual($0 as? FinishingQueueStore.Error,.referenceMismatch)
        }
        try FileManager.default.removeItem(at:path)
        let target=r.appendingPathComponent("external.json"); try original.write(to:target)
        try FileManager.default.createSymbolicLink(at:path,withDestinationURL:target)
        XCTAssertThrowsError(try store.load(reference:ref,workflowStore:workflows,printerStore:printers)) {
            XCTAssertEqual($0 as? FinishingQueueStore.Error,.cannotRead)
        }
    }
    func testUncertainPublicationCarriesExactColdRecoverableReference() throws {
        let r=root(), workflows=try WorkflowProfileStore(root:r), printers=try PrinterProfileStore(root:r)
        let w=try workflow(), p=try profile(); try workflows.save(w); try workflows.confirmForUnattendedUse(w)
        let pr=try printers.save(id:"synthetic-printer",profile:p), q=try queue(workflow:w,printer:p,printerReference:pr)
        let expected=try FinishingQueueReference(id:q.id,revision:q.revision,sha256:digest(FinishingQueueJSON.encode(q)))
        let storage=try PrivateImmutableDirectory(root:r,syncDirectory:{ _ in -1 })
        let faulty=FinishingQueueStore(root:r,storage:storage)
        XCTAssertThrowsError(try faulty.save(q,workflowStore:workflows,printerStore:printers)) {
            XCTAssertEqual($0 as? FinishingQueueStore.Error,.commitUncertain(expected))
        }
        XCTAssertEqual(try FinishingQueueStore(root:r).load(reference:expected,workflowStore:workflows,printerStore:printers),q)
    }
    func testNativePitchIsBoundToExactVerifiedProfileAndDevice() throws {
        let r=root(), printers=try PrinterProfileStore(root:r), w=try workflow(), p=try profile()
        let pr=try printers.save(id:"synthetic-printer",profile:p)
        let stored=try printers.load(id:pr.id,revision:pr.revision)
        let device=try PhysicalDeviceCoordinationID(sha256:String(repeating:"a",count:64))
        let pitch=try DotResolution(xDotsPerMillimeter:8,yDotsPerMillimeter:8)
        let geometry=try FinishingDeviceGeometry(printer:stored,physicalDevice:device,
            nativePitch:.observed(pitch,evidence:.documentedModel(sourceID:"synthetic-native-pitch")))
        let q=try queue(workflow:w,printer:p,printerReference:pr)
        let canvas=try geometry.canvas(for:q,workflow:w)
        XCTAssertEqual(canvas.width,813); XCTAssertEqual(canvas.height,1219)
        XCTAssertEqual(canvas.resolution,pitch)
        try geometry.validate(canvas:canvas,queue:q,workflow:w)
        let nominal=try DotCanvas(physicalSize:w.outputStock,
            resolution:DotResolution(xDotsPerMillimeter:203/25.4,yDotsPerMillimeter:203/25.4))
        XCTAssertThrowsError(try geometry.validate(canvas:nominal,queue:q,workflow:w))
        let alias=try FinishingDeviceGeometry(printer:stored,
            physicalDevice:.init(sha256:String(repeating:"b",count:64)),
            nativePitch:.observed(pitch,evidence:.reportedInstallation))
        XCTAssertThrowsError(try alias.canvas(for:q,workflow:w))
        let forged=StoredPrinterProfile(reference:try .init(id:pr.id,schemaVersion:8,revision:pr.revision,
            sha256:String(repeating:"0",count:64)),profile:p)
        XCTAssertThrowsError(try FinishingDeviceGeometry(printer:forged,physicalDevice:device,
            nativePitch:.observed(pitch,evidence:.reportedInstallation)))
    }
    func testUnknownPitchAndInvalidModelProvenanceRemainRejected() throws {
        let r=root(), printers=try PrinterProfileStore(root:r), p=try profile()
        let pr=try printers.save(id:"synthetic-printer",profile:p), stored=try printers.load(id:pr.id,revision:pr.revision)
        let device=try PhysicalDeviceCoordinationID(sha256:String(repeating:"a",count:64))
        let pitch=try DotResolution(xDotsPerMillimeter:8,yDotsPerMillimeter:8)
        for observation in [Observation<DotResolution>.unobserved,
            .observed(pitch,evidence:.unobserved), .observed(pitch,evidence:.documentedModel(sourceID:"../unsafe"))] {
            XCTAssertThrowsError(try FinishingDeviceGeometry(printer:stored,physicalDevice:device,nativePitch:observation))
        }
        let old=try PrinterProfile.gc420dUSBReference()
        let oldRef=try printers.save(id:"synthetic-legacy",profile:old)
        XCTAssertThrowsError(try FinishingDeviceGeometry(printer:printers.load(id:oldRef.id,revision:oldRef.revision),
            physicalDevice:device,nativePitch:.observed(pitch,evidence:.reportedInstallation)))
    }
    func testGC420dNativePitchNeverUsesNominal203DPI() throws {
        let r=root(), printers=try PrinterProfileStore(root:r), p=try profile(model:"GC420d")
        let pr=try printers.save(id:"synthetic-gc420d",profile:p), stored=try printers.load(id:pr.id,revision:pr.revision)
        let device=try PhysicalDeviceCoordinationID(sha256:String(repeating:"a",count:64))
        for (x,y) in [(203/25.4,203/25.4),(8.0,7.0)] {
            XCTAssertThrowsError(try FinishingDeviceGeometry(printer:stored,physicalDevice:device,
                nativePitch:.observed(DotResolution(xDotsPerMillimeter:x,yDotsPerMillimeter:y),
                    evidence:.documentedModel(sourceID:"R26")))) {
                XCTAssertEqual($0 as? FinishingDeviceGeometry.Error,.modelPitchMismatch)
            }
        }
        let native=try DotResolution(xDotsPerMillimeter:8,yDotsPerMillimeter:8)
        XCTAssertEqual(try FinishingDeviceGeometry(printer:stored,physicalDevice:device,
            nativePitch:.observed(native,evidence:.documentedModel(sourceID:"R26"))).resolution,native)
    }
    private func originalSource() throws -> (Data,URL) {
        var repository=URL(fileURLWithPath:#filePath)
        for _ in 0..<5 { repository.deleteLastPathComponent() }
        #if DEBUG
        let configuration="debug"
        #else
        let configuration="release"
        #endif
        return (try Data(contentsOf:repository.appendingPathComponent("Fixtures/generated/native-vector.pdf")),
            repository.appendingPathComponent("Packages/LabelMac/.build/\(configuration)/label-render-worker"))
    }
    private func acceptanceSetup() throws -> (WorkflowProfileStore,PrinterProfileStore,FinishingQueueStore,FinishingQueueReference,FinishingDeviceGeometry,Data,URL) {
        let (source,worker)=try originalSource()
        let pages=try OfflineLayoutWorker.analyze(originalPDF:source,structuralPages:[1],workerExecutable:worker)
        let border=try XCTUnwrap(pages[0].anchors?.first { $0.kind == .border })
        let p=try profile(), r=root(), workflows=try WorkflowProfileStore(root:r), printers=try PrinterProfileStore(root:r)
        let w=try WorkflowProfile(id:"synthetic-original",revision:1,outputStockID:"nominal-4x6",outputStock:workflow().outputStock,
            pageRules:[WorkflowPageRule(sourcePage:1,expectedInput:ExpectedInputPage(uprightPhysicalSize:pages[0].pageBox.effectivePhysicalSize()),
                disposition:.extract([ExtractionRegion(id:"left",normalizedRect:NormalizedRect(x:0,y:0,width:0.5,height:1),outputOrder:0),
                                      ExtractionRegion(id:"right",normalizedRect:NormalizedRect(x:0.5,y:0,width:0.5,height:1),outputOrder:1)]),
                structuralAnchors:[StructuralAnchorExpectation(id:"border",kind:.border,normalizedRect:border.normalizedRect)])])
        try workflows.save(w); try workflows.confirmForUnattendedUse(w)
        let pr=try printers.save(id:"synthetic-printer",profile:p), store=try FinishingQueueStore(root:r)
        let q=try queue(workflow:w,printer:p,printerReference:pr,defaults:.init(printSpeedIps:3,darkness:9))
        let ref=try store.save(q,workflowStore:workflows,printerStore:printers)
        let geometry=try FinishingDeviceGeometry(printer:printers.load(id:pr.id,revision:pr.revision),physicalDevice:q.physicalDevice,
            nativePitch:.observed(DotResolution(xDotsPerMillimeter:1,yDotsPerMillimeter:1),evidence:.documentedModel(sourceID:"synthetic-pitch")))
        return (workflows,printers,store,ref,geometry,source,worker)
    }
    func testOriginalFinishingAcceptanceOwnsOrderAndPreparationUsesSameSnapshot() throws {
        let (workflows,printers,store,ref,geometry,source,worker)=try acceptanceSetup()
        for collated in [true,false] {
            let accepted=try AcceptedFinishingJob.accept(acceptanceID:"synthetic-accepted",cancellationSHA256:String(repeating:"c",count:64),
                queueReference:ref,queueStore:store,workflowStore:workflows,printerStore:printers,geometry:geometry,originalPDF:source,
                copyOwnership:.engine(copies:2,collated:collated),pageRangeOwnership:.engine(selectedSourcePages:[1]),
                controls:.init(darkness:0),workerExecutable:worker)
            XCTAssertEqual(accepted.sourceSHA256,digest(source))
            XCTAssertEqual(accepted.originalPDF,source)
            XCTAssertEqual(accepted.extraction.outputLabels.map(\.regionID),collated ? ["left","right","left","right"] : ["left","left","right","right"])
            XCTAssertEqual(accepted.job.plan.cutAfterOutputLabels,[3,4])
            XCTAssertEqual(accepted.controls.darkness,.value(0))
            XCTAssertEqual(accepted.intakeProvenance,.offlineCLI)
            if collated {
                let prepared=try accepted.prepare(workerExecutable:worker)
                XCTAssertEqual(prepared.extraction,accepted.extraction)
                XCTAssertEqual(prepared.binding.job,accepted.job)
                XCTAssertEqual(prepared.controls,accepted.controls)
                XCTAssertEqual(prepared.rasters.count,4)
            }
        }
    }
    func testFinishingAcceptanceRejectsInvalidControlsBeforeWorkerAndInvalidOwnership() throws {
        let (workflows,printers,store,ref,geometry,source,worker)=try acceptanceSetup()
        XCTAssertThrowsError(try AcceptedFinishingJob.accept(acceptanceID:"synthetic-accepted",cancellationSHA256:String(repeating:"c",count:64),
            queueReference:ref,queueStore:store,workflowStore:workflows,printerStore:printers,geometry:geometry,originalPDF:source,
            copyOwnership:.upstreamAlreadyExpanded,pageRangeOwnership:.upstreamAlreadyApplied,controls:.init(finishing:.peel),
            workerExecutable:URL(fileURLWithPath:"/nonexistent-worker"))) {
            XCTAssertEqual($0 as? FinishingQueueDefinition.Error,.selectionMismatch)
        }
        for pages in [[1,1],[2]] {
            XCTAssertThrowsError(try AcceptedFinishingJob.accept(acceptanceID:"synthetic-accepted",cancellationSHA256:String(repeating:"c",count:64),
                queueReference:ref,queueStore:store,workflowStore:workflows,printerStore:printers,geometry:geometry,originalPDF:source,
                copyOwnership:.upstreamAlreadyExpanded,pageRangeOwnership:.engine(selectedSourcePages:pages),workerExecutable:worker)) {
                XCTAssertEqual($0 as? AcceptedFinishingJob.Error,.invalidOwnership)
            }
        }
        let cancellation=OfflineRenderWorkerCancellation(); cancellation.cancel()
        XCTAssertThrowsError(try AcceptedFinishingJob.accept(acceptanceID:"synthetic-accepted",cancellationSHA256:String(repeating:"c",count:64),
            queueReference:ref,queueStore:store,workflowStore:workflows,printerStore:printers,geometry:geometry,originalPDF:source,
            copyOwnership:.upstreamAlreadyExpanded,pageRangeOwnership:.upstreamAlreadyApplied,workerExecutable:worker,cancellation:cancellation)) {
            XCTAssertEqual($0 as? AcceptedFinishingJob.Error,.cancelled)
        }
    }
    private func acceptedFixture() throws -> (AcceptedFinishingJob,WorkflowProfileStore,PrinterProfileStore,FinishingQueueStore,URL) {
        let (workflows,printers,queues,ref,geometry,source,worker)=try acceptanceSetup()
        let accepted=try AcceptedFinishingJob.accept(acceptanceID:"synthetic-durable",cancellationSHA256:String(repeating:"c",count:64),
            queueReference:ref,queueStore:queues,workflowStore:workflows,printerStore:printers,geometry:geometry,originalPDF:source,
            copyOwnership:.engine(copies:2,collated:false),pageRangeOwnership:.engine(selectedSourcePages:[1]),controls:.init(darkness:0),workerExecutable:worker)
        return (accepted,workflows,printers,queues,worker)
    }
    func testDurableFinishingColdReopenAndConflictKeepOriginalContext() throws {
        let (job,workflows,printers,queues,worker)=try acceptedFixture()
        let store=try AcceptedFinishingJobStore(root:workflows.root)
        let ref=try store.save(job)
        XCTAssertEqual(try store.save(job),ref)
        XCTAssertEqual(try AcceptedFinishingJobStore(root:workflows.root).load(reference:ref,
            queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker),job)
        let altered=try AcceptedFinishingJob.accept(acceptanceID:job.acceptanceID,cancellationSHA256:job.cancellationSHA256,
            queueReference:job.queueReference,queueStore:queues,workflowStore:workflows,printerStore:printers,geometry:job.geometry,
            originalPDF:job.originalPDF,copyOwnership:.engine(copies:2,collated:true),pageRangeOwnership:job.pageRangeOwnership,workerExecutable:worker)
        XCTAssertThrowsError(try store.save(altered)) { XCTAssertEqual($0 as? AcceptedFinishingJobStore.Error,.conflict) }
        let wrong=try AcceptedFinishingReference(acceptanceID:ref.acceptanceID,sha256:String(repeating:"0",count:64))
        XCTAssertThrowsError(try store.load(reference:wrong,queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker)) {
            XCTAssertEqual($0 as? AcceptedFinishingJobStore.Error,.referenceMismatch)
        }
    }
    func testDurableFinishingRehashedStaleContextFailsInsteadOfReinterpretation() throws {
        let (job,workflows,printers,queues,worker)=try acceptedFixture()
        let store=try AcceptedFinishingJobStore(root:workflows.root), ref=try store.save(job)
        let file=workflows.root.appendingPathComponent("accepted-finishing-jobs").appendingPathComponent(AcceptedFinishingJobStore.fileName(ref))
        let original=try Data(contentsOf:file)
        var length:UInt64=0
        for (i,byte) in original[8..<16].enumerated() { length |= UInt64(byte) << (i*8) }
        let boundary=16+Int(length)
        var metadata=try XCTUnwrap(JSONSerialization.jsonObject(with:original.subdata(in:16..<boundary)) as? [String:Any])
        metadata["context"]=Data([0]).base64EncodedString()
        let changed=try JSONSerialization.data(withJSONObject:metadata,options:[.sortedKeys])
        var bytes=Data("AFJOB001".utf8)
        for shift in stride(from:0,through:56,by:8) { bytes.append(UInt8(truncatingIfNeeded:UInt64(changed.count)>>shift)) }
        bytes.append(changed);bytes.append(original.subdata(in:boundary..<original.count));try bytes.write(to:file)
        let rehashed=try AcceptedFinishingReference(acceptanceID:ref.acceptanceID,sha256:digest(bytes))
        XCTAssertThrowsError(try store.load(reference:rehashed,queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker)) {
            XCTAssertEqual($0 as? AcceptedFinishingJobStore.Error,.contextMismatch)
        }
    }
    func testDurableFinishingUncertainPublicationReturnsExactRecoverableIdentity() throws {
        let (job,workflows,printers,queues,worker)=try acceptedFixture()
        let store=AcceptedFinishingJobStore(root:workflows.root,storage:try PrivateImmutableDirectory(root:workflows.root,syncDirectory:{ _ in -1 }))
        var recovery:AcceptedFinishingReference?
        XCTAssertThrowsError(try store.save(job)) { error in
            if case let AcceptedFinishingJobStore.Error.commitUncertain(ref)=error { recovery=ref }
            else { XCTFail("Expected exact uncertain publication") }
        }
        let ref=try XCTUnwrap(recovery)
        XCTAssertEqual(try AcceptedFinishingJobStore(root:workflows.root).load(reference:ref,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker),job)
    }
    func testDurableFinishingOversizedLengthAndBinarySymlinkFailBeforeWorker() throws {
        let (job,workflows,printers,queues,_)=try acceptedFixture()
        let store=try AcceptedFinishingJobStore(root:workflows.root), ref=try store.save(job)
        let file=workflows.root.appendingPathComponent("accepted-finishing-jobs").appendingPathComponent(AcceptedFinishingJobStore.fileName(ref))
        let original=try Data(contentsOf:file)
        var bytes=original;bytes.replaceSubrange(8..<16,with:Data(repeating:255,count:8));try bytes.write(to:file)
        let wrong=try AcceptedFinishingReference(acceptanceID:ref.acceptanceID,sha256:digest(bytes))
        XCTAssertThrowsError(try store.load(reference:wrong,queueStore:queues,workflowStore:workflows,printerStore:printers,
            workerExecutable:URL(fileURLWithPath:"/nonexistent-worker"))) {
            XCTAssertEqual($0 as? AcceptedFinishingJobStore.Error,.invalidRecord)
        }
        try FileManager.default.removeItem(at:file)
        let target=workflows.root.appendingPathComponent("external.bin");try original.write(to:target)
        try FileManager.default.createSymbolicLink(at:file,withDestinationURL:target)
        XCTAssertThrowsError(try store.load(reference:ref,queueStore:queues,workflowStore:workflows,printerStore:printers,
            workerExecutable:URL(fileURLWithPath:"/nonexistent-worker"))) {
            XCTAssertEqual($0 as? AcceptedFinishingJobStore.Error,.cannotRead)
        }
    }
}
