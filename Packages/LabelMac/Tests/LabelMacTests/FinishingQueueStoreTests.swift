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
    func testPreparedFinishingIdentityComesFromVerifiedDurableRecord() throws {
        let (job,workflows,printers,queues,worker)=try acceptedFixture()
        let store=try AcceptedFinishingJobStore(root:workflows.root), ref=try store.save(job)
        let result=try store.prepare(reference:ref,queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        XCTAssertEqual(result.reference,ref)
        XCTAssertEqual(result.acceptance,job)
        XCTAssertEqual(result.preparation.extraction,job.extraction)
        XCTAssertEqual(result.preparation.controls,job.controls)
        XCTAssertEqual(result.preparation.sourceSHA256,job.sourceSHA256)
        XCTAssertEqual(result.preparation.rasters.count,4)
        let wrong=try AcceptedFinishingReference(acceptanceID:ref.acceptanceID,sha256:String(repeating:"0",count:64))
        XCTAssertThrowsError(try store.prepare(reference:wrong,queueStore:queues,workflowStore:workflows,printerStore:printers,
            workerExecutable:URL(fileURLWithPath:"/nonexistent-worker"))) {
            XCTAssertEqual($0 as? AcceptedFinishingJobStore.Error,.referenceMismatch)
        }
    }
    func testAcceptedFramingKeepsIdentityAndIntentSurvivesNewArtifactNames() throws {
        let (job,workflows,printers,queues,worker)=try acceptedFixture()
        let accepted=try AcceptedFinishingJobStore(root:workflows.root), ref=try accepted.save(job)
        let prepared=try accepted.prepare(reference:ref,queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        let qualification=FinishingOutputQualification(profile:job.geometry.printer.profile,model:job.geometry.printer.profile.capabilities.model,
            quantityOne:documented,labelCompletion:documented,rfid:.init(state:.unsupported,evidence:.documentedModel(sourceID:"synthetic-non-rfid")),
            delayedCutter:documented,delayedCutReadiness:documented,cutCompletion:documented,
            completeFileDelivery:.observed(true,evidence:.reportedInstallation))
        let framed=try prepared.frame(qualification:qualification)
        XCTAssertEqual(framed.reference,ref)
        XCTAssertEqual(framed.output.preparation,prepared.preparation)
        XCTAssertEqual(framed.output.steps.compactMap { if case let .formatFile(n,_)=($0) { return n }; return nil },[1,2,3,4])
        XCTAssertEqual(framed.output.steps.compactMap { if case let .delayedCutFile(n,_)=($0) { return n }; return nil },[3,4])
        let artifacts=try FinishingArtifactStore(root:workflows.root)
        let first=try artifacts.save(id:"synthetic-frame-one",revision:1,output:framed.output)
        let second=try artifacts.save(id:"synthetic-frame-two",revision:1,output:framed.output)
        XCTAssertNotEqual(first.id,second.id)
        let intents=try AcceptedFinishingAttemptStore(root:workflows.root)
        XCTAssertEqual(try intents.recoveryObservation(reference:ref,against:job,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker),.noRecordedIntent)
        try intents.recordPotentialAttempt(reference:ref,against:job,queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        try intents.recordPotentialAttempt(reference:ref,against:job,queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        _ = try artifacts.load(reference:second,against:framed.output)
        _ = try InertFinishingDelivery.run(output:framed.output, coordinationID:job.geometry.physicalDevice,
            leaseDirectory:workflows.root)
        XCTAssertEqual(try AcceptedFinishingAttemptStore(root:workflows.root).recoveryObservation(reference:ref,against:job,
            queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker),.uncertainAfterRecordedIntent)
        let directory=workflows.root.appendingPathComponent("accepted-finishing-attempts")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:directory.path).filter { $0.hasSuffix(".bin") }.count,1)
    }
    func testAcceptedIntentRequiresExactContextAndUncertainCommitRemainsRecorded() throws {
        let (job,workflows,printers,queues,worker)=try acceptedFixture()
        let accepted=try AcceptedFinishingJobStore(root:workflows.root), ref=try accepted.save(job)
        let wrong=try AcceptedFinishingJob.accept(acceptanceID:job.acceptanceID,cancellationSHA256:job.cancellationSHA256,
            queueReference:job.queueReference,queueStore:queues,workflowStore:workflows,printerStore:printers,geometry:job.geometry,
            originalPDF:job.originalPDF,copyOwnership:.engine(copies:2,collated:true),pageRangeOwnership:job.pageRangeOwnership,workerExecutable:worker)
        let intents=try AcceptedFinishingAttemptStore(root:workflows.root)
        XCTAssertThrowsError(try intents.recordPotentialAttempt(reference:ref,against:wrong,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker)) {
            XCTAssertEqual($0 as? AcceptedFinishingAttemptStore.Error,.contextMismatch)
        }
        XCTAssertThrowsError(try intents.recoveryObservation(reference:ref,against:wrong,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker)) {
            XCTAssertEqual($0 as? AcceptedFinishingAttemptStore.Error,.contextMismatch)
        }
        let faulty=try AcceptedFinishingAttemptStore(root:workflows.root,
            storage:PrivateImmutableDirectory(root:workflows.root,syncDirectory:{ _ in -1 }))
        XCTAssertThrowsError(try faulty.recordPotentialAttempt(reference:ref,against:job,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker)) {
            XCTAssertEqual($0 as? AcceptedFinishingAttemptStore.Error,.commitUncertain)
        }
        XCTAssertEqual(try intents.recoveryObservation(reference:ref,against:job,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker),.uncertainAfterRecordedIntent)
    }
    private func acceptedFramedFixture() throws -> (AcceptedFinishingFramedJob,WorkflowProfileStore,PrinterProfileStore,FinishingQueueStore,URL) {
        let (job,workflows,printers,queues,worker)=try acceptedFixture()
        let accepted=try AcceptedFinishingJobStore(root:workflows.root), ref=try accepted.save(job)
        let prepared=try accepted.prepare(reference:ref,queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        let qualification=FinishingOutputQualification(profile:job.geometry.printer.profile,model:job.geometry.printer.profile.capabilities.model,
            quantityOne:documented,labelCompletion:documented,rfid:.init(state:.unsupported,evidence:.documentedModel(sourceID:"synthetic-non-rfid")),
            delayedCutter:documented,delayedCutReadiness:documented,cutCompletion:documented,
            completeFileDelivery:.observed(true,evidence:.reportedInstallation))
        return (try prepared.frame(qualification:qualification),workflows,printers,queues,worker)
    }
    func testAcceptedCoordinatorRecordsBeforeDiscardHoldsLeasesThroughWaitsAndRefusesReplay() throws {
        let (framed,workflows,printers,queues,worker)=try acceptedFramedFixture()
        let intents=try AcceptedFinishingAttemptStore(root:workflows.root)
        var attempts=0, waits=0, discarded=0
        _ = try InertAcceptedFinishingDelivery.run(framed:framed,attemptStore:intents,cancellationStore:try AcceptedFinishingCancellationStore(root:workflows.root),queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker,leaseDirectory:workflows.root,
            scenario:.init(),deadlineSeconds:60,cancellation:.init()) { event in
                switch event {
                case .fileAttempt:
                    attempts += 1
                    XCTAssertEqual(try intents.recoveryObservation(reference:framed.reference,against:framed.prepared.acceptance,
                        queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker),.uncertainAfterRecordedIntent)
                case .bytesDiscarded: discarded += 1
                case .statusWait:
                    waits += 1
                    XCTAssertThrowsError(try InertAcceptedFinishingDelivery.run(framed:framed,attemptStore:intents,cancellationStore:try AcceptedFinishingCancellationStore(root:workflows.root),
                        queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker,leaseDirectory:workflows.root)) {
                        XCTAssertEqual($0 as? InertAcceptedFinishingDelivery.Error,.jobBusy)
                    }
                    XCTAssertThrowsError(try PhysicalDeviceLease(acquiring:.init(coordinationID:framed.prepared.acceptance.geometry.physicalDevice),
                        inExistingDirectory:workflows.root)) { XCTAssertEqual($0 as? PhysicalDeviceLeaseError,.alreadyHeld) }
                }
            }
        XCTAssertEqual(attempts,6);XCTAssertGreaterThan(waits,0);XCTAssertGreaterThan(discarded,0)
        XCTAssertThrowsError(try InertAcceptedFinishingDelivery.run(framed:framed,attemptStore:try AcceptedFinishingAttemptStore(root:workflows.root),cancellationStore:try AcceptedFinishingCancellationStore(root:workflows.root),
            queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker,leaseDirectory:workflows.root)) {
            XCTAssertEqual($0 as? InertAcceptedFinishingDelivery.Error,.recordedIntentRequiresReview)
        }
        let released=try PhysicalDeviceLease(acquiring:.init(coordinationID:framed.prepared.acceptance.geometry.physicalDevice),inExistingDirectory:workflows.root)
        released.release()
    }
    func testAcceptedCoordinatorZeroBytesAndUncertainPublicationCannotBecomeFreshAdmission() throws {
        for publicationFault in [false,true] {
            let (framed,workflows,printers,queues,worker)=try acceptedFramedFixture()
            let intents=try AcceptedFinishingAttemptStore(root:workflows.root)
            let selected = publicationFault ? try AcceptedFinishingAttemptStore(root:workflows.root,
                storage:PrivateImmutableDirectory(root:workflows.root,syncDirectory:{ _ in -1 })) : intents
            var observed=0
            if publicationFault {
                XCTAssertThrowsError(try InertAcceptedFinishingDelivery.run(framed:framed,attemptStore:selected,cancellationStore:try AcceptedFinishingCancellationStore(root:workflows.root),queueStore:queues,
                    workflowStore:workflows,printerStore:printers,workerExecutable:worker,leaseDirectory:workflows.root,
                    scenario:.init(),deadlineSeconds:60,cancellation:.init(),observe:{ _ in observed += 1 })) {
                    XCTAssertEqual($0 as? AcceptedFinishingAttemptStore.Error,.commitUncertain)
                }
                XCTAssertEqual(observed,0)
            } else {
                _ = try InertAcceptedFinishingDelivery.run(framed:framed,attemptStore:selected,cancellationStore:try AcceptedFinishingCancellationStore(root:workflows.root),queueStore:queues,
                    workflowStore:workflows,printerStore:printers,workerExecutable:worker,leaseDirectory:workflows.root,
                    scenario:.init(failAfterAttemptAtStep:0),deadlineSeconds:60,cancellation:.init()) { event in
                        if case .bytesDiscarded = event { observed += 1 }
                    }
                XCTAssertEqual(observed,0)
            }
            XCTAssertEqual(try intents.recoveryObservation(reference:framed.reference,against:framed.prepared.acceptance,
                queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker),.uncertainAfterRecordedIntent)
            XCTAssertThrowsError(try InertAcceptedFinishingDelivery.run(framed:framed,attemptStore:intents,cancellationStore:try AcceptedFinishingCancellationStore(root:workflows.root),queueStore:queues,
                workflowStore:workflows,printerStore:printers,workerExecutable:worker,leaseDirectory:workflows.root)) {
                XCTAssertEqual($0 as? InertAcceptedFinishingDelivery.Error,.recordedIntentRequiresReview)
            }
        }
    }
    func testAcceptedCoordinatorStopBeforeAttemptAndCancellationCreateNoIntent() throws {
        let (framed,workflows,printers,queues,worker)=try acceptedFramedFixture()
        let intents=try AcceptedFinishingAttemptStore(root:workflows.root)
        _ = try InertAcceptedFinishingDelivery.run(framed:framed,attemptStore:intents,cancellationStore:try AcceptedFinishingCancellationStore(root:workflows.root),queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker,leaseDirectory:workflows.root,
            scenario:.init(stopBeforeStep:0))
        let cancellation=OfflineRenderWorkerCancellation();cancellation.cancel()
        XCTAssertThrowsError(try InertAcceptedFinishingDelivery.run(framed:framed,attemptStore:intents,cancellationStore:try AcceptedFinishingCancellationStore(root:workflows.root),queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker,leaseDirectory:workflows.root,cancellation:cancellation)) {
            XCTAssertEqual($0 as? AcceptedFinishingJob.Error,.cancelled)
        }
        XCTAssertEqual(try intents.recoveryObservation(reference:framed.reference,against:framed.prepared.acceptance,
            queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker),.noRecordedIntent)
    }
    private func cancellableAcceptedFixture() throws -> (AcceptedFinishingJob,AcceptedFinishingReference,WorkflowProfileStore,PrinterProfileStore,FinishingQueueStore,URL,Data) {
        let (prior,workflows,printers,queues,worker)=try acceptedFixture()
        let token=Data("synthetic-cancellation-token".utf8)
        let digest=SHA256.hash(data:token).map { String(format:"%02x",$0) }.joined()
        let job=try AcceptedFinishingJob.accept(acceptanceID:prior.acceptanceID,cancellationSHA256:digest,
            queueReference:prior.queueReference,queueStore:queues,workflowStore:workflows,printerStore:printers,
            geometry:prior.geometry,originalPDF:prior.originalPDF,copyOwnership:prior.copyOwnership,
            pageRangeOwnership:prior.pageRangeOwnership,controls:prior.controlRequest,workerExecutable:worker)
        return (job,try AcceptedFinishingJobStore(root:workflows.root).save(job),workflows,printers,queues,worker,token)
    }
    func testFinishingCancellationAuthenticatesAndSurvivesColdReopenWithoutStoringToken() throws {
        let (job,ref,workflows,printers,queues,worker,token)=try cancellableAcceptedFixture()
        let store=try AcceptedFinishingCancellationStore(root:workflows.root)
        let monitor=try store.monitor(reference:ref,against:job,queueStore:queues,workflowStore:workflows,
            printerStore:printers,workerExecutable:worker)
        XCTAssertEqual(try monitor.poll(),.noRecordedRequest)
        for bad in [Data(),Data(repeating:1,count:257),Data("synthetic-wrong-token".utf8)] {
            XCTAssertThrowsError(try store.request(reference:ref,against:job,token:bad,queueStore:queues,
                workflowStore:workflows,printerStore:printers,workerExecutable:URL(fileURLWithPath:"/nonexistent-worker"))) {
                XCTAssertEqual($0 as? AcceptedFinishingCancellationStore.Error,.unauthorized)
            }
        }
        XCTAssertEqual(try monitor.poll(),.noRecordedRequest)
        for _ in 0..<2 { try store.request(reference:ref,against:job,token:token,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker) }
        XCTAssertEqual(try monitor.poll(),.requested)
        XCTAssertEqual(try AcceptedFinishingCancellationStore(root:workflows.root).observation(reference:ref,against:job,
            queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker),.requested)
        let dir=workflows.root.appendingPathComponent("accepted-finishing-cancellations")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:dir.path).filter{$0.hasSuffix(".bin")}.count,1)
        let bytes=try Data(contentsOf:dir.appendingPathComponent(AcceptedFinishingCancellationStore.fileName(ref)))
        XCTAssertNil(bytes.range(of:token))
    }
    func testFinishingCancellationPublicationUncertaintyDoesNotClearAttemptUncertainty() throws {
        let (job,ref,workflows,printers,queues,worker,token)=try cancellableAcceptedFixture()
        let intents=try AcceptedFinishingAttemptStore(root:workflows.root)
        try intents.recordPotentialAttempt(reference:ref,against:job,queueStore:queues,workflowStore:workflows,
            printerStore:printers,workerExecutable:worker)
        let faulty=try AcceptedFinishingCancellationStore(root:workflows.root,
            storage:PrivateImmutableDirectory(root:workflows.root,syncDirectory:{ _ in -1 }))
        XCTAssertThrowsError(try faulty.request(reference:ref,against:job,token:token,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker)) {
            XCTAssertEqual($0 as? AcceptedFinishingCancellationStore.Error,.commitUncertain)
        }
        XCTAssertEqual(try AcceptedFinishingCancellationStore(root:workflows.root).observation(reference:ref,against:job,
            queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker),.requested)
        XCTAssertEqual(try intents.recoveryObservation(reference:ref,against:job,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker),.uncertainAfterRecordedIntent)
    }
    func testFinishingCancellationRequiresExactContextAndRejectsCorruptOrSymlinkRecords() throws {
        let (job,ref,workflows,printers,queues,worker,token)=try cancellableAcceptedFixture()
        let wrong=try AcceptedFinishingJob.accept(acceptanceID:job.acceptanceID,cancellationSHA256:job.cancellationSHA256,
            queueReference:job.queueReference,queueStore:queues,workflowStore:workflows,printerStore:printers,
            geometry:job.geometry,originalPDF:job.originalPDF,copyOwnership:.engine(copies:1,collated:false),
            pageRangeOwnership:job.pageRangeOwnership,controls:job.controlRequest,workerExecutable:worker)
        let store=try AcceptedFinishingCancellationStore(root:workflows.root)
        XCTAssertThrowsError(try store.request(reference:ref,against:wrong,token:token,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker)) {
            XCTAssertEqual($0 as? AcceptedFinishingCancellationStore.Error,.contextMismatch)
        }
        XCTAssertThrowsError(try store.monitor(reference:ref,against:wrong,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker)) {
            XCTAssertEqual($0 as? AcceptedFinishingCancellationStore.Error,.contextMismatch)
        }
        let monitor=try store.monitor(reference:ref,against:job,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        try store.request(reference:ref,against:job,token:token,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        let file=workflows.root.appendingPathComponent("accepted-finishing-cancellations").appendingPathComponent(AcceptedFinishingCancellationStore.fileName(ref))
        try Data("corrupt".utf8).write(to:file)
        XCTAssertThrowsError(try monitor.poll()) { XCTAssertEqual($0 as? AcceptedFinishingCancellationStore.Error,.invalidRecord) }
        try FileManager.default.removeItem(at:file)
        try FileManager.default.createSymbolicLink(at:file,withDestinationURL:workflows.root.appendingPathComponent("missing-target"))
        XCTAssertThrowsError(try monitor.poll()) { XCTAssertEqual($0 as? AcceptedFinishingCancellationStore.Error,.cannotRead) }
    }
    private func cancellableFramedFixture() throws -> (AcceptedFinishingFramedJob,WorkflowProfileStore,PrinterProfileStore,FinishingQueueStore,URL,Data) {
        let (job,ref,workflows,printers,queues,worker,token)=try cancellableAcceptedFixture()
        let prepared=try AcceptedFinishingJobStore(root:workflows.root).prepare(reference:ref,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        let qualification=FinishingOutputQualification(profile:job.geometry.printer.profile,model:job.geometry.printer.profile.capabilities.model,
            quantityOne:documented,labelCompletion:documented,rfid:.init(state:.unsupported,evidence:.documentedModel(sourceID:"synthetic-non-rfid")),
            delayedCutter:documented,delayedCutReadiness:documented,cutCompletion:documented,
            completeFileDelivery:.observed(true,evidence:.reportedInstallation))
        return (try prepared.frame(qualification:qualification),workflows,printers,queues,worker,token)
    }
    func testAcceptedCoordinatorDurableCancellationBeforeAdmissionCreatesNoIntent() throws {
        let (framed,workflows,printers,queues,worker,token)=try cancellableFramedFixture()
        let requests=try AcceptedFinishingCancellationStore(root:workflows.root)
        let intents=try AcceptedFinishingAttemptStore(root:workflows.root)
        try requests.request(reference:framed.reference,against:framed.prepared.acceptance,token:token,
            queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        XCTAssertThrowsError(try InertAcceptedFinishingDelivery.run(framed:framed,attemptStore:intents,cancellationStore:requests,
            queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker,leaseDirectory:workflows.root)) {
            XCTAssertEqual($0 as? InertAcceptedFinishingDelivery.Error,.cancellationRequested)
        }
        XCTAssertEqual(try intents.recoveryObservation(reference:framed.reference,against:framed.prepared.acceptance,
            queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker),.noRecordedIntent)
    }
    func testAcceptedCoordinatorDurableCancellationAtFileChunkAndStatusBoundariesKeepsUncertainty() throws {
        for target in ["attempt","chunk","status"] {
            let (framed,workflows,printers,queues,worker,token)=try cancellableFramedFixture()
            let requests=try AcceptedFinishingCancellationStore(root:workflows.root)
            let intents=try AcceptedFinishingAttemptStore(root:workflows.root)
            var requested=false, callbacksAfterRequest=0
            XCTAssertThrowsError(try InertAcceptedFinishingDelivery.run(framed:framed,attemptStore:intents,cancellationStore:requests,
                queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker,leaseDirectory:workflows.root,
                scenario:.init(maximumChunkBytes:16),deadlineSeconds:60,cancellation:.init()) { event in
                    if requested { callbacksAfterRequest += 1 }
                    let matches:Bool
                    switch event {
                    case .fileAttempt:matches=target=="attempt"
                    case .bytesDiscarded:matches=target=="chunk"
                    case .statusWait:matches=target=="status"
                    }
                    if matches && !requested {
                        try requests.request(reference:framed.reference,against:framed.prepared.acceptance,token:token,
                            queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker)
                        requested=true
                    }
                }) { XCTAssertEqual($0 as? InertAcceptedFinishingDelivery.Error,.cancellationRequested) }
            XCTAssertTrue(requested);XCTAssertEqual(callbacksAfterRequest,0)
            XCTAssertEqual(try intents.recoveryObservation(reference:framed.reference,against:framed.prepared.acceptance,
                queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker),.uncertainAfterRecordedIntent)
            XCTAssertThrowsError(try InertAcceptedFinishingDelivery.run(framed:framed,attemptStore:intents,
                cancellationStore:try AcceptedFinishingCancellationStore(root:workflows.root),queueStore:queues,
                workflowStore:workflows,printerStore:printers,workerExecutable:worker,leaseDirectory:workflows.root)) {
                XCTAssertEqual($0 as? InertAcceptedFinishingDelivery.Error,.recordedIntentRequiresReview)
            }
        }
    }
    func testColdFinishingRecoveryReportsCancellationWithoutResolvingAttemptUncertainty() throws {
        let (framed,workflows,printers,queues,worker,token)=try cancellableFramedFixture()
        let requests=try AcceptedFinishingCancellationStore(root:workflows.root)
        let intents=try AcceptedFinishingAttemptStore(root:workflows.root)
        func recover() throws -> AcceptedFinishingRecovery {
            try AcceptedFinishingRecovery.inspect(reference:framed.reference,against:framed.prepared.acceptance,
                attemptStore:AcceptedFinishingAttemptStore(root:workflows.root),
                cancellationStore:AcceptedFinishingCancellationStore(root:workflows.root),queueStore:queues,
                workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        }
        XCTAssertEqual(try recover().reference,framed.reference)
        XCTAssertEqual(try recover().observation,.noRecordedIntent(cancellationRequested:false))
        try requests.request(reference:framed.reference,against:framed.prepared.acceptance,token:token,
            queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        XCTAssertEqual(try recover().observation,.noRecordedIntent(cancellationRequested:true))
        try intents.recordPotentialAttempt(reference:framed.reference,against:framed.prepared.acceptance,
            queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        _ = try InertFinishingDelivery.run(output:framed.output,coordinationID:framed.prepared.acceptance.geometry.physicalDevice,
            leaseDirectory:workflows.root)
        XCTAssertEqual(try recover().observation,.uncertainAfterRecordedIntent(cancellationRequested:true))
        let file=workflows.root.appendingPathComponent("accepted-finishing-cancellations")
            .appendingPathComponent(AcceptedFinishingCancellationStore.fileName(framed.reference))
        try Data("corrupt".utf8).write(to:file)
        XCTAssertThrowsError(try recover()) { XCTAssertEqual($0 as? AcceptedFinishingCancellationStore.Error,.invalidRecord) }
    }
    func testColdFinishingRecoveryKeepsUncancelledIntentUncertainAndRejectsLimitsOrCancellation() throws {
        let (framed,workflows,printers,queues,worker,_)=try cancellableFramedFixture()
        let requests=try AcceptedFinishingCancellationStore(root:workflows.root)
        let intents=try AcceptedFinishingAttemptStore(root:workflows.root)
        try intents.recordPotentialAttempt(reference:framed.reference,against:framed.prepared.acceptance,
            queueStore:queues,workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        XCTAssertEqual(try AcceptedFinishingRecovery.inspect(reference:framed.reference,against:framed.prepared.acceptance,
            attemptStore:intents,cancellationStore:requests,queueStore:queues,workflowStore:workflows,
            printerStore:printers,workerExecutable:worker).observation,.uncertainAfterRecordedIntent(cancellationRequested:false))
        for limit in [0.0,61.0,Double.nan,Double.infinity] {
            XCTAssertThrowsError(try AcceptedFinishingRecovery.inspect(reference:framed.reference,against:framed.prepared.acceptance,
                attemptStore:intents,cancellationStore:requests,queueStore:queues,workflowStore:workflows,
                printerStore:printers,workerExecutable:URL(fileURLWithPath:"/nonexistent-worker"),deadlineSeconds:limit)) {
                XCTAssertEqual($0 as? AcceptedFinishingJob.Error,.invalidLimit)
            }
        }
        let cancellation=OfflineRenderWorkerCancellation();cancellation.cancel()
        XCTAssertThrowsError(try AcceptedFinishingRecovery.inspect(reference:framed.reference,against:framed.prepared.acceptance,
            attemptStore:intents,cancellationStore:requests,queueStore:queues,workflowStore:workflows,
            printerStore:printers,workerExecutable:URL(fileURLWithPath:"/nonexistent-worker"),cancellation:cancellation)) {
            XCTAssertEqual($0 as? AcceptedFinishingJob.Error,.cancelled)
        }
    }
    func testFinishingInspectionUsesVerifiedRecordAndReportsUnknownHardwareWithoutPublishingIntent() throws {
        let (job,ref,workflows,printers,queues,worker,token)=try cancellableAcceptedFixture()
        let args=["--catalog",workflows.root.path,"--accepted-id",ref.acceptanceID,"--accepted-sha",ref.sha256,"--json"]
        let command=try FinishingInspectionCommand(arguments:args)
        var result=try XCTUnwrap(JSONSerialization.jsonObject(with:command.report(workerExecutable:worker)) as? [String:Any])
        XCTAssertEqual(result["outputLabelCount"] as? Int,4)
        XCTAssertEqual(result["hardwareCompletion"] as? String,"unknown")
        XCTAssertEqual(result["localIntent"] as? String,"no-recorded-intent")
        XCTAssertEqual(result["automaticReplayAuthorized"] as? Bool,false)
        func invoke(_ arguments:[String]) throws -> (Int32,Data,Data) {
            let process=Process(), output=Pipe(), errors=Pipe()
            process.executableURL=worker.deletingLastPathComponent().appendingPathComponent("label-driver")
            process.arguments=["finishing-inspect"]+arguments
            process.standardOutput=output;process.standardError=errors
            try process.run()
            let end=Date().addingTimeInterval(75)
            while process.isRunning && Date()<end { Thread.sleep(forTimeInterval:0.01) }
            if process.isRunning { kill(process.processIdentifier,SIGKILL) }
            process.waitUntilExit()
            return (process.terminationStatus,output.fileHandleForReading.readDataToEndOfFile(),errors.fileHandleForReading.readDataToEndOfFile())
        }
        let (code,stdout,stderr)=try invoke(args)
        XCTAssertEqual(code,0);XCTAssertTrue(stderr.isEmpty)
        let actual=try XCTUnwrap(JSONSerialization.jsonObject(with:stdout) as? [String:Any])
        XCTAssertEqual(actual["localIntent"] as? String,"no-recorded-intent")
        XCTAssertEqual(actual["outputLabelCount"] as? Int,4)
        var wrong=args;wrong[5]=String(repeating:"0",count:64)
        let (badCode,badOutput,badErrors)=try invoke(wrong)
        XCTAssertEqual(badCode,65);XCTAssertTrue(badOutput.isEmpty)
        XCTAssertFalse(String(decoding:badErrors,as:UTF8.self).contains(workflows.root.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:workflows.root.appendingPathComponent("accepted-finishing-attempts").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:workflows.root.appendingPathComponent("accepted-finishing-cancellations").path))
        try AcceptedFinishingAttemptStore(root:workflows.root).recordPotentialAttempt(reference:ref,against:job,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        try AcceptedFinishingCancellationStore(root:workflows.root).request(reference:ref,against:job,token:token,queueStore:queues,
            workflowStore:workflows,printerStore:printers,workerExecutable:worker)
        result=try XCTUnwrap(JSONSerialization.jsonObject(with:command.report(workerExecutable:worker)) as? [String:Any])
        XCTAssertEqual(result["localIntent"] as? String,"uncertain-after-recorded-intent")
        XCTAssertEqual(result["cancellationRequested"] as? Bool,true)
        XCTAssertNil(result["token"]);XCTAssertNil(result["catalog"])
        XCTAssertThrowsError(try FinishingInspectionCommand(arguments:args+["--json"]))
        let missing=workflows.root.appendingPathComponent("missing-catalog")
        let absent=try FinishingInspectionCommand(arguments:["--catalog",missing.path,"--accepted-id",ref.acceptanceID,"--accepted-sha",ref.sha256])
        XCTAssertThrowsError(try absent.report(workerExecutable:worker))
        XCTAssertFalse(FileManager.default.fileExists(atPath:missing.path))
    }
    func testPackedPreviewExportMatchesActualRastersAndBindsAcceptedIdentity() throws {
        let (framed,workflows,_,_,_,_)=try cancellableFramedFixture()
        let directory=workflows.root.appendingPathComponent("synthetic-packed-preview")
        try PackedFinishingPreviewExport.write(framed.prepared,toNewDirectory:directory)
        let files=try FileManager.default.contentsOfDirectory(atPath:directory.path)
        XCTAssertEqual(files.count,5);XCTAssertFalse(files.contains { $0.hasSuffix(".zpl") })
        for (index,raster) in framed.prepared.preparation.rasters.enumerated() {
            XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent(String(format:"label-%05d.pbm",index+1))),raster.pbmData())
        }
        let meta=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("preview.json"))) as? [String:Any])
        XCTAssertEqual(meta["acceptedRecordSHA256"] as? String,framed.reference.sha256)
        XCTAssertEqual(meta["sourceSHA256"] as? String,framed.prepared.acceptance.sourceSHA256)
        XCTAssertEqual(meta["hardwareCompletion"] as? String,"unknown")
    }
    func testPackedPreviewExportNeverOverwritesAndRejectsBudgetBeforeCreatingOutput() throws {
        let (framed,workflows,_,_,_,_)=try cancellableFramedFixture()
        let directory=workflows.root.appendingPathComponent("synthetic-existing-preview")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
        let sentinel=directory.appendingPathComponent("sentinel")
        try Data("synthetic-sentinel".utf8).write(to:sentinel)
        XCTAssertThrowsError(try PackedFinishingPreviewExport.write(framed.prepared,toNewDirectory:directory)) {
            XCTAssertEqual($0 as? PackedFinishingPreviewExport.Error,.destinationExists)
        }
        XCTAssertEqual(try Data(contentsOf:sentinel),Data("synthetic-sentinel".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:directory.path),["sentinel"])
        let empty=workflows.root.appendingPathComponent("synthetic-empty-preview")
        try FileManager.default.createDirectory(at:empty,withIntermediateDirectories:false)
        var originalInfo=stat(), finalInfo=stat()
        XCTAssertEqual(lstat(empty.path,&originalInfo),0)
        XCTAssertThrowsError(try PackedFinishingPreviewExport.write(framed.prepared,toNewDirectory:empty)) {
            XCTAssertEqual($0 as? PackedFinishingPreviewExport.Error,.destinationExists)
        }
        XCTAssertEqual(lstat(empty.path,&finalInfo),0);XCTAssertEqual(finalInfo.st_ino,originalInfo.st_ino)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:empty.path).isEmpty)
        let absent=workflows.root.appendingPathComponent("synthetic-budget-preview")
        XCTAssertThrowsError(try PackedFinishingPreviewExport.write(framed.prepared,toNewDirectory:absent,maximumBytes:1)) {
            XCTAssertEqual($0 as? PackedFinishingPreviewExport.Error,.byteLimit)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath:absent.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:workflows.root.path).contains { $0.hasPrefix(".packed-preview-") })
    }
    func testPackedPreviewCLIExportsExactPreparedBytesAndRefusesExistingOutput() throws {
        let (framed,workflows,_,_,worker,_)=try cancellableFramedFixture()
        let directory=workflows.root.appendingPathComponent("synthetic-cli-preview")
        let args=["finishing-preview","--catalog",workflows.root.path,"--accepted-id",framed.reference.acceptanceID,
            "--accepted-sha",framed.reference.sha256,"--preview-dir",directory.path,"--json"]
        func invoke() throws -> (Int32,Data,Data) {
            let process=Process(), output=Pipe(), errors=Pipe()
            process.executableURL=worker.deletingLastPathComponent().appendingPathComponent("label-driver")
            process.arguments=args;process.standardOutput=output;process.standardError=errors
            try process.run()
            let end=Date().addingTimeInterval(75)
            while process.isRunning && Date()<end { Thread.sleep(forTimeInterval:0.01) }
            if process.isRunning { kill(process.processIdentifier,SIGKILL) }
            process.waitUntilExit()
            return (process.terminationStatus,output.fileHandleForReading.readDataToEndOfFile(),errors.fileHandleForReading.readDataToEndOfFile())
        }
        let (code,stdout,stderr)=try invoke()
        XCTAssertEqual(code,0);XCTAssertTrue(stderr.isEmpty)
        let result=try XCTUnwrap(JSONSerialization.jsonObject(with:stdout) as? [String:Any])
        XCTAssertEqual(result["hardwareCompletion"] as? String,"unknown")
        XCTAssertEqual(result["outputLabelCount"] as? Int,4)
        let original=try Data(contentsOf:directory.appendingPathComponent("label-00001.pbm"))
        XCTAssertEqual(original,framed.prepared.preparation.rasters[0].pbmData())
        let (badCode,badOutput,badErrors)=try invoke()
        XCTAssertEqual(badCode,73);XCTAssertTrue(badOutput.isEmpty)
        XCTAssertFalse(String(decoding:badErrors,as:UTF8.self).contains(directory.path))
        XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent("label-00001.pbm")),original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:workflows.root.path).contains{$0.hasPrefix(".packed-preview-")})
    }
}
