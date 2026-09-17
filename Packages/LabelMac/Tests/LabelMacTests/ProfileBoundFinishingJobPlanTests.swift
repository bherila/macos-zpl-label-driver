import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class ProfileBoundFinishingJobPlanTests: XCTestCase {
    private let modes: [FinishingMode] = [.tearOff, .cut, .peel, .rewind]
    private let documented = CapabilityFact(state: .supported,
        evidence: .documentedModel(sourceID: "synthetic-profile-finishing-plan"))
    private func store() throws -> PrinterProfileStore {
        let root = FileManager.default.temporaryDirectory.appending(path: "FinishingPlan-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try PrinterProfileStore(root: root)
    }
    private func profile(revision: Int = 11, maximumBatch: Int = 3,
                         includeConfiguration: Bool = true) throws -> PrinterProfile {
        let base = try PrinterProfile.gc420dUSBReference(), c = base.capabilities
        let installed = CapabilityFact(state: .supported, evidence: .reportedInstallation)
        return try .init(schemaVersion: 8, revision: revision,
            capabilities: .init(model: "synthetic-finishing-model", thermalTransfer: c.thermalTransfer,
                cutter: documented, peeler: documented, rewind: documented, tracking: c.tracking,
                printSpeedChoicesIps: c.printSpeedChoicesIps, darkness: documented, physicalGeometry: .init(width: .init(fact: documented, maximumDots: 200),
                    homeX: .init(fact: documented, maximumDots: 200),
                    homeY: .init(fact: documented, maximumDots: 200)),
                offsets: .init(shiftLeft: .init(fact: documented, range: -5...5),
                    labelTop: .init(fact: documented, range: -5...5)), directThermal: documented),
            installedHardware: .init(transport: .usb, selectedFinishing: .tearOff, cutter: installed,
                peeler: installed, observedSpeedIps: nil, observedDarkness: nil, observedTracking: nil),
            media: base.media, connection: base.connection,
            configuredDefaults: .init(thermalMethod: .directThermal),
            thermalMedia: .init(method: .observed(.directThermal, evidence: .reportedInstallation),
                ribbonPresent: .observed(false, evidence: .reportedInstallation)),
            finishingConfiguration: includeConfiguration ? .init(finishing: .init(
                modes: Dictionary(uniqueKeysWithValues: modes.map { ($0, documented) }), enabledModes: Set(modes),
                installed: .init(cutter: .observed(true, evidence: .reportedInstallation),
                    peeler: .observed(true, evidence: .reportedInstallation),
                    rewinder: .observed(true, evidence: .reportedInstallation))),
                stock: .init(media: base.media, compatibleModes: Dictionary(uniqueKeysWithValues: modes.map {
                    ($0, .observed(true, evidence: .reportedInstallation))
                })), schedules: .init(everyLabel: documented, batch: documented, endOfJob: documented,
                    maximumBatchSize: maximumBatch)) : nil)
    }

    private func job(_ count: Int = 2) throws -> ProfileBoundFinishingJobPlan {
        let store = try store(), reference = try store.save(id: "synthetic-finishing", profile: profile())
        return try store.finishingPlan(reference: reference, mode: .cut, outputLabelCount: count, schedule: .endOfJob)
    }

    @MainActor
    func testFinishingPreparationRendersOriginalSourceAndRetainsExpandedExtraction() async throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let source = try Data(contentsOf: root.appending(path: "Fixtures/generated/native-vector.pdf"))
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let worker = root.appending(path: "Packages/LabelMac/.build/\(configuration)/label-render-worker")
        let directory = FileManager.default.temporaryDirectory.appending(path: "FinishingSource-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let model = try WorkflowEditorBootstrap.makeModel(originalPDF: source,
            store: WorkflowProfileStore(root: directory))
        let pages = try QuartzPDFRenderer.documentPageBoxes(originalPDF: source)
        let plan = try ExtractionPlanner.plan(sourcePages: pages, profile: model.profile,
            copyPolicy: .engine(copies: 2, collated: true))
        let canvas = try DotCanvas(physicalSize: model.profile.outputStock,
            resolution: DotResolution(xDotsPerMillimeter: 1, yDotsPerMillimeter: 1))
        let conversion = MonochromeConversion.textAndBarcodeThreshold(cutoff: 128)
        let job = try job(2)
        let request = PrinterControlRequest(finishing: .cut, printSpeedIps: 3, darkness: 0,
            mediaGeometry: try .init(widthDots: canvas.width, originXDot: 1, originYDot: 0),
            offsets: .init(shiftLeftDots: 1))
        let result = try FinishingRasterPreparation.prepare(job: job,
            controlRequest: request, originalPDF: source,
            extraction: plan, canvas: canvas, conversion: conversion, workerExecutable: worker)
        XCTAssertEqual(result.extraction, plan)
        XCTAssertEqual(result.controls.finishing, .value(.cut))
        XCTAssertEqual(result.controls.thermalMethod, .value(.directThermal))
        XCTAssertEqual(result.controls.darkness, .value(0))
        XCTAssertEqual(result.controls.printSpeedIps, .value(3))
        XCTAssertEqual(result.normalization.profile, job.printer.profile)
        XCTAssertEqual(result.normalization.plan, job.plan)
        XCTAssertEqual(String(decoding: result.normalization.bytes, as: UTF8.self),
            "^MTD\n^PR3\n^MD0\n~SD00\n^PW\(canvas.width)\n^LH1,0\n^LS1\n")
        XCTAssertEqual(result.controls.mediaGeometry, .value(try .init(widthDots: canvas.width,
            originXDot: 1, originYDot: 0)))
        XCTAssertEqual(result.controls.offsets, .value(.init(shiftLeftDots: 1)))
        XCTAssertNoThrow(try result.validateControls(job: request))
        var changedRequest = request; changedRequest.printSpeedIps = 4
        XCTAssertThrowsError(try result.validateControls(job: changedRequest)) {
            XCTAssertEqual($0 as? FinishingRasterPreparation.Error, .bindingMismatch)
        }
        XCTAssertEqual(result.rasters.count, 2) // No second copy expansion.
        XCTAssertEqual(result.rasters[0], result.rasters[1])
        XCTAssertEqual(result.rasters[0], try OfflineExtractionWorker.render(originalPDF: source,
            label: plan.outputLabels[0], canvas: canvas, conversion: conversion, workerExecutable: worker))
        XCTAssertNoThrow(try result.binding.validate(job: job, orderedRasters: result.rasters))
        XCTAssertNoThrow(try result.validateSource(originalPDF: source, extraction: plan, canvas: canvas, conversion: conversion))
        var sameSizeChanged = source
        sameSizeChanged[sameSizeChanged.startIndex] ^= 1
        XCTAssertEqual(sameSizeChanged.count, source.count)
        XCTAssertThrowsError(try result.validateSource(originalPDF: sameSizeChanged,
            extraction: plan, canvas: canvas, conversion: conversion))
        XCTAssertThrowsError(try result.validateSource(originalPDF: source + Data([0]),
            extraction: plan, canvas: canvas, conversion: conversion))
        XCTAssertThrowsError(try result.validateSource(originalPDF: source, extraction: plan,
            canvas: canvas, conversion: .photographicOrderedDither4x4))
        let otherCanvas = try DotCanvas(physicalSize: canvas.physicalSize,
            resolution: DotResolution(xDotsPerMillimeter: 2, yDotsPerMillimeter: 2))
        XCTAssertThrowsError(try result.validateSource(originalPDF: source, extraction: plan,
            canvas: otherCanvas, conversion: conversion))
        let single = try ExtractionPlanner.plan(sourcePages: pages, profile: model.profile)
        XCTAssertThrowsError(try result.validateSource(originalPDF: source, extraction: single,
            canvas: canvas, conversion: conversion))
        // Resource/count failures precede any worker execution.
        let inert = URL(fileURLWithPath: "/usr/bin/false")
        XCTAssertThrowsError(try FinishingRasterPreparation.prepare(job: job,
            controlRequest: .init(finishing: .cut, printSpeedIps: 3, darkness: 0), originalPDF: source,
            extraction: single, canvas: canvas, conversion: conversion, workerExecutable: inert)) {
            XCTAssertEqual($0 as? FinishingRasterPreparation.Error, .planMismatch)
        }
        XCTAssertThrowsError(try FinishingRasterPreparation.prepare(job: job,
            controlRequest: .init(finishing: .cut, printSpeedIps: 3, darkness: 0), originalPDF: source,
            extraction: plan, canvas: canvas, conversion: conversion, workerExecutable: inert, maximumPackedBytes: 1)) {
            XCTAssertEqual($0 as? FinishingRasterPreparation.Error, .byteLimit)
        }
        XCTAssertThrowsError(try FinishingRasterPreparation.prepare(job: job,
            controlRequest: .init(finishing: .cut, printSpeedIps: 3, darkness: 31),
            originalPDF: source, extraction: plan, canvas: canvas, conversion: conversion, workerExecutable: inert)) {
            XCTAssertEqual($0 as? PrinterProfileError, .unsupportedDarkness(31))
        }
        XCTAssertThrowsError(try FinishingRasterPreparation.prepare(job: job,
            controlRequest: .init(finishing: .cut, printSpeedIps: 3, darkness: 0,
                mediaGeometry: try .init(widthDots: canvas.width, originXDot: 1, originYDot: 0)),
            originalPDF: source, extraction: plan, canvas: canvas, conversion: conversion, workerExecutable: worker)) {
            XCTAssertEqual($0 as? PhysicalGeometryQualification.Error, .rasterExceedsWidth)
        }
        let cancelled = OfflineRenderWorkerCancellation(); cancelled.cancel()
        XCTAssertThrowsError(try FinishingRasterPreparation.prepare(job: job,
            controlRequest: .init(finishing: .cut, printSpeedIps: 3, darkness: 0), originalPDF: source,
            extraction: plan, canvas: canvas, conversion: conversion, workerExecutable: inert, cancellation: cancelled)) {
            XCTAssertEqual($0 as? FinishingRasterPreparation.Error, .cancelled)
        }
        let unexpectedPages = try Data(contentsOf: root.appending(path: "Fixtures/generated/mixed-pages.pdf"))
        XCTAssertThrowsError(try FinishingRasterPreparation.prepare(job: job,
            controlRequest: .init(finishing: .cut, printSpeedIps: 3, darkness: 0), originalPDF: unexpectedPages,
            extraction: plan, canvas: canvas, conversion: conversion, workerExecutable: worker)) {
            XCTAssertEqual($0 as? FinishingRasterPreparation.Error, .planMismatch)
        }
    }

    @MainActor
    func testFramedFinishingOutputPreservesCutFilesPeelWaitsAndOneExpandedQuantity() async throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let source = try Data(contentsOf: root.appending(path: "Fixtures/generated/native-vector.pdf"))
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let worker = root.appending(path: "Packages/LabelMac/.build/\(configuration)/label-render-worker")
        let directory = FileManager.default.temporaryDirectory.appending(path: "FinishingFrames-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let model = try WorkflowEditorBootstrap.makeModel(originalPDF: source,
            store: WorkflowProfileStore(root: directory))
        let pages = try QuartzPDFRenderer.documentPageBoxes(originalPDF: source)
        let canvas = try DotCanvas(physicalSize: model.profile.outputStock,
            resolution: DotResolution(xDotsPerMillimeter: 1, yDotsPerMillimeter: 1))
        let store = try store(), reference = try store.save(id: "synthetic-framed-output", profile: profile())
        for mode in modes {
            let count = mode == .cut ? 7 : 2
            let plan = try ExtractionPlanner.plan(sourcePages: pages, profile: model.profile,
                copyPolicy: .engine(copies: count, collated: true))
            let job = try store.finishingPlan(reference: reference, mode: mode, outputLabelCount: count,
                schedule: mode == .cut ? .batch(size: 3, cutRemainderAtJobEnd: true) : nil)
            let preparation = try FinishingRasterPreparation.prepare(job: job,
                controlRequest: .init(finishing: mode, printSpeedIps: 3, darkness: 0), originalPDF: source,
                extraction: plan, canvas: canvas, conversion: .textAndBarcodeThreshold(cutoff: 128), workerExecutable: worker)
            let nonRFID = CapabilityFact(state: .unsupported,
                evidence: .documentedModel(sourceID: "synthetic-output-non-rfid"))
            let qualification = FinishingOutputQualification(profile: job.printer.profile, model: job.printer.profile.capabilities.model,
                quantityOne: documented, labelCompletion: documented, rfid: nonRFID,
                delayedCutter: documented, delayedCutReadiness: documented, cutCompletion: documented,
                completeFileDelivery: .observed(true, evidence: .reportedInstallation),
                peelLabelTaken: documented, prepeel: documented)
            let framed = try FinishingFramedOutput.prepare(preparation, qualification: qualification)
            XCTAssertEqual(framed.preparation, preparation)
            XCTAssertEqual(framed.qualification, qualification)
            var expected: [FinishingOutputStep] = [], total = 0
            let modeText: String
            switch mode {
            case .tearOff: modeText = "^MMT\n"
            case .rewind: modeText = "^MMR\n"
            case .peel: modeText = "^MMP,N\n"
            case .cut: modeText = "^MMD\n"
            }
            for (index, bitmap) in preparation.rasters.enumerated() {
                let ordinal = index + 1
                let diagnostic = String(decoding: try ZPLGraphicEncoder().diagnosticFormat(bitmap), as: UTF8.self)
                let graphic = diagnostic.replacingOccurrences(of: "^XA\n", with: "")
                    .replacingOccurrences(of: "^XZ\n", with: "")
                let bytes = Data(("^XA\n" + String(decoding: preparation.normalization.bytes, as: UTF8.self)
                    + modeText + graphic + "^PQ1\n^XZ\n").utf8)
                XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("~JK"))
                XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("^MMC"))
                expected.append(.formatFile(outputLabel: ordinal, bytes: bytes))
                expected.append(.awaitLabelPrinted(outputLabel: ordinal)); total += bytes.count
                if mode == .cut && [3, 6, 7].contains(ordinal) {
                    expected.append(.awaitDelayedCutReady(afterOutputLabel: ordinal))
                    expected.append(.delayedCutFile(afterOutputLabel: ordinal, bytes: Data("~JK\n".utf8)))
                    expected.append(.awaitCutCompleted(afterOutputLabel: ordinal)); total += 4
                }
                if mode == .peel { expected.append(.awaitLabelTaken(outputLabel: ordinal)) }
            }
            XCTAssertEqual(framed.steps, expected)
            let artifact = try FinishingFramedArtifact.encode(framed)
            XCTAssertEqual(artifact, try FinishingFramedArtifact.encode(framed))
            XCTAssertEqual(artifact.sha256.count, 64)
            XCTAssertEqual(artifact, try FinishingFramedArtifact.reopen(artifact.bytes, against: framed))
            XCTAssertNoThrow(try FinishingFramedArtifact.encode(framed, maximumBytes: artifact.bytes.count))
            XCTAssertThrowsError(try FinishingFramedArtifact.encode(framed, maximumBytes: artifact.bytes.count - 1))
            for corrupted in [Data(), Data(artifact.bytes.dropLast()), artifact.bytes + Data([0])] {
                XCTAssertThrowsError(try FinishingFramedArtifact.reopen(corrupted, against: framed))
            }
            var changed = artifact.bytes; changed[changed.startIndex] ^= 1
            XCTAssertThrowsError(try FinishingFramedArtifact.reopen(changed, against: framed))
            let reordered = FinishingFramedOutput(preparation: preparation, qualification: qualification,
                steps: Array(framed.steps.reversed()), totalEncodedBytes: total)
            XCTAssertThrowsError(try FinishingFramedArtifact.reopen(artifact.bytes, against: reordered))
            let changedSource = FinishingRasterPreparation(sourceSHA256: String(repeating: "b", count: 64),
                sourceByteCount: preparation.sourceByteCount, extraction: preparation.extraction,
                canvas: preparation.canvas, conversion: preparation.conversion, rasters: preparation.rasters,
                binding: preparation.binding, normalization: preparation.normalization)
            let changedContext = FinishingFramedOutput(preparation: changedSource, qualification: qualification,
                steps: framed.steps, totalEncodedBytes: total)
            XCTAssertThrowsError(try FinishingFramedArtifact.reopen(artifact.bytes, against: changedContext))
            let archiveRoot = directory.appending(path: "archive-store-\(mode)")
            let archives = try FinishingArtifactStore(root: archiveRoot)
            let archiveReference = try archives.save(id: "synthetic-framed", revision: 1, output: framed)
            let reopenedStore = try FinishingArtifactStore(root: archiveRoot)
            XCTAssertEqual(try reopenedStore.load(reference: archiveReference, against: framed), artifact)
            XCTAssertEqual(try reopenedStore.save(id: "synthetic-framed", revision: 1, output: framed), archiveReference)
            XCTAssertThrowsError(try reopenedStore.save(id: "synthetic-framed", revision: 1, output: changedContext)) {
                XCTAssertEqual($0 as? FinishingArtifactStore.Error, .conflict)
            }
            XCTAssertEqual(try reopenedStore.load(reference: archiveReference, against: framed), artifact)
            let wrongDigest = try FinishingArtifactReference(id: archiveReference.id, revision: 1,
                sha256: String(repeating: "c", count: 64))
            XCTAssertThrowsError(try reopenedStore.load(reference: wrongDigest, against: framed)) {
                XCTAssertEqual($0 as? FinishingArtifactStore.Error, .referenceMismatch)
            }
            let uncertainStorage = try PrivateImmutableDirectory(root: archiveRoot, syncDirectory: { _ in -1 })
            let uncertainStore = FinishingArtifactStore(root: archiveRoot, storage: uncertainStorage)
            var uncertainReference: FinishingArtifactReference?
            XCTAssertThrowsError(try uncertainStore.save(id: "synthetic-uncertain", revision: 1, output: framed)) { error in
                guard case let FinishingArtifactStore.Error.commitUncertain(reference) = error else {
                    return XCTFail("Expected uncertain publication")
                }
                uncertainReference = reference
            }
            XCTAssertEqual(try reopenedStore.load(reference: XCTUnwrap(uncertainReference), against: framed), artifact)
            for id in ["synthetic-third", "synthetic-fourth"] { _ = try archives.save(id: id, revision: 1, output: framed) }
            XCTAssertThrowsError(try archives.save(id: "synthetic-fifth", revision: 1, output: framed)) {
                XCTAssertEqual($0 as? FinishingArtifactStore.Error, .capacityReached)
            }
            XCTAssertEqual(try archives.save(id: "synthetic-framed", revision: 1, output: framed), archiveReference)
            XCTAssertThrowsError(try archives.save(id: "../unsafe", revision: 1, output: framed))
            let cancelArchive = OfflineRenderWorkerCancellation(); cancelArchive.cancel()
            XCTAssertThrowsError(try FinishingFramedArtifact.encode(framed, cancellation: cancelArchive)) {
                XCTAssertEqual($0 as? FinishingFramedArtifact.Error, .cancelled)
            }
            XCTAssertThrowsError(try FinishingFramedArtifact.encode(framed, deadlineSeconds: 0))
            XCTAssertThrowsError(try FinishingFramedArtifact.encode(framed, deadlineSeconds: Double.leastNonzeroMagnitude)) {
                XCTAssertEqual($0 as? FinishingFramedArtifact.Error, .timedOut)
            }
            // Nearest independent constraint: completing file delivery does
            // not satisfy status/removal, and no attempted file is replayable.
            var tracker = FinishingDeliveryTracker(output: framed)
            for (index, step) in expected.enumerated() {
                XCTAssertEqual(tracker.nextStepIndex, index)
                XCTAssertEqual(tracker.nextStep, step)
                XCTAssertFalse(tracker.mayRetryAutomatically)
                switch step {
                case let .formatFile(_, bytes), let .delayedCutFile(_, bytes):
                    XCTAssertThrowsError(try tracker.beginFile(stepIndex: index + 1, bytes: bytes))
                    XCTAssertThrowsError(try tracker.beginFile(stepIndex: index, bytes: Data()))
                    try tracker.beginFile(stepIndex: index, bytes: bytes)
                    XCTAssertThrowsError(try tracker.fileFinished())
                    try tracker.acceptedByTransport(byteCount: bytes.count / 2)
                    try tracker.acceptedByTransport(byteCount: bytes.count)
                    try tracker.fileFinished()
                    XCTAssertEqual(tracker.state, .awaitingStatus)
                    var waitingFailure = tracker
                    try waitingFailure.stop(cancelled: true)
                    XCTAssertEqual(waitingFailure.state, .uncertain)
                    XCTAssertFalse(waitingFailure.mayRetryAutomatically)
                default:
                    XCTAssertEqual(tracker.state, .awaitingStatus)
                    XCTAssertFalse(try tracker.observeStatus(stepIndex: index, step: step, observation: .unknown))
                    XCTAssertFalse(try tracker.observeStatus(stepIndex: index, step: step, observation: .notSatisfied))
                    XCTAssertEqual(tracker.nextStepIndex, index)
                    XCTAssertThrowsError(try tracker.observeStatus(stepIndex: index + 1, step: step, observation: .confirmed))
                    XCTAssertTrue(try tracker.observeStatus(stepIndex: index, step: step, observation: .confirmed))
                }
            }
            XCTAssertEqual(tracker.state, .confirmed)
            XCTAssertNil(tracker.nextStep)
            XCTAssertEqual(tracker.bytesAccepted, total)
            XCTAssertThrowsError(try tracker.stop(cancelled: false))
            var beforeAttempt = FinishingDeliveryTracker(output: framed)
            try beforeAttempt.stop(cancelled: false)
            XCTAssertTrue(beforeAttempt.mayRetryAutomatically)
            var cancelledBefore = FinishingDeliveryTracker(output: framed)
            try cancelledBefore.stop(cancelled: true)
            XCTAssertFalse(cancelledBefore.mayRetryAutomatically)
            guard case let .formatFile(_, firstBytes) = expected[0] else { return XCTFail("Expected format") }
            var attempted = FinishingDeliveryTracker(output: framed)
            try attempted.beginFile(stepIndex: 0, bytes: firstBytes)
            try attempted.stop(cancelled: false)
            XCTAssertEqual(attempted.bytesAccepted, 0)
            XCTAssertEqual(attempted.state, .uncertain)
            XCTAssertFalse(attempted.mayRetryAutomatically)
            XCTAssertThrowsError(try attempted.beginFile(stepIndex: 0, bytes: firstBytes))
            for invalid in [-1, firstBytes.count + 1] {
                var broken = FinishingDeliveryTracker(output: framed)
                try broken.beginFile(stepIndex: 0, bytes: firstBytes)
                XCTAssertThrowsError(try broken.acceptedByTransport(byteCount: invalid))
                XCTAssertEqual(broken.state, .uncertain)
                XCTAssertFalse(broken.mayRetryAutomatically)
            }
            var decreasing = FinishingDeliveryTracker(output: framed)
            try decreasing.beginFile(stepIndex: 0, bytes: firstBytes)
            try decreasing.acceptedByTransport(byteCount: 1)
            XCTAssertThrowsError(try decreasing.acceptedByTransport(byteCount: 0))
            XCTAssertEqual(decreasing.state, .uncertain)
            // Lease ownership must survive every file and readiness/removal wait.
            let leaseRoot = directory.appending(path: "inert-leases-\(mode)")
            try FileManager.default.createDirectory(at: leaseRoot, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            let domain = try PhysicalDeviceCoordinationID(sha256: String(repeating: "a", count: 64))
            let identity = PhysicalDeviceIdentity(coordinationID: domain)
            var observedWaits: [Int] = []
            let simulated = try InertFinishingDelivery.run(output: framed, coordinationID: domain,
                leaseDirectory: leaseRoot, scenario: .init(), deadlineSeconds: 60, cancellation: .init()) { event in
                    XCTAssertThrowsError(try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: leaseRoot)) {
                        XCTAssertEqual($0 as? PhysicalDeviceLeaseError, .alreadyHeld)
                    }
                    if case let .statusWait(index) = event { observedWaits.append(index) }
                }
            XCTAssertEqual(simulated.state, .confirmed) // Synthetic observations only.
            XCTAssertEqual(simulated.bytesAccepted, total)
            let expectedWaits = expected.indices.filter { index in
                switch expected[index] {
                case .formatFile, .delayedCutFile: false
                default: true
                }
            }
            XCTAssertEqual(observedWaits, expectedWaits)
            let afterSuccess = try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: leaseRoot)
            XCTAssertThrowsError(try InertFinishingDelivery.run(output: framed, coordinationID: domain,
                leaseDirectory: leaseRoot)) { XCTAssertEqual($0 as? InertFinishingDelivery.Error, .deviceBusy) }
            afterSuccess.release()
            for index in expectedWaits {
                let unknown = try InertFinishingDelivery.run(output: framed, coordinationID: domain,
                    leaseDirectory: leaseRoot, scenario: .init(unknownStatusAtStep: index))
                XCTAssertEqual(unknown.state, .uncertain)
                XCTAssertEqual(unknown.nextStepIndex, index)
                XCTAssertFalse(unknown.mayRetryAutomatically)
                let released = try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: leaseRoot)
                released.release()
            }
            let attemptFailure = try InertFinishingDelivery.run(output: framed, coordinationID: domain,
                leaseDirectory: leaseRoot, scenario: .init(failAfterAttemptAtStep: 0))
            XCTAssertEqual(attemptFailure.state, .uncertain)
            XCTAssertEqual(attemptFailure.bytesAccepted, 0)
            let beforeSend = try InertFinishingDelivery.run(output: framed, coordinationID: domain,
                leaseDirectory: leaseRoot, scenario: .init(stopBeforeStep: 0))
            XCTAssertTrue(beforeSend.mayRetryAutomatically)
            let cancel = OfflineRenderWorkerCancellation()
            let duringWait = try InertFinishingDelivery.run(output: framed, coordinationID: domain,
                leaseDirectory: leaseRoot, scenario: .init(), deadlineSeconds: 60, cancellation: cancel) { event in
                    if case .statusWait = event { cancel.cancel() }
                }
            XCTAssertEqual(duringWait.state, .uncertain)
            enum Injected: Swift.Error { case failure }
            XCTAssertThrowsError(try InertFinishingDelivery.run(output: framed, coordinationID: domain,
                leaseDirectory: leaseRoot, scenario: .init(), deadlineSeconds: 60, cancellation: .init()) { _ in
                    throw Injected.failure
                })
            let afterError = try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: leaseRoot)
            afterError.release()
            for scenario in [InertFinishingDelivery.Scenario(maximumChunkBytes: 0),
                .init(stopBeforeStep: -1), .init(failAfterAttemptAtStep: 1), .init(unknownStatusAtStep: 0)] {
                XCTAssertThrowsError(try InertFinishingDelivery.run(output: framed, coordinationID: domain,
                    leaseDirectory: leaseRoot, scenario: scenario)) {
                        XCTAssertEqual($0 as? InertFinishingDelivery.Error, .invalidScenario)
                    }
            }
            XCTAssertThrowsError(try InertFinishingDelivery.run(output: framed, coordinationID: domain,
                leaseDirectory: leaseRoot, deadlineSeconds: 0))
            if mode == .peel {
                let withoutPrepeel = FinishingOutputQualification(profile: job.printer.profile, model: qualification.model,
                    quantityOne: documented, labelCompletion: documented, rfid: nonRFID,
                    peelLabelTaken: documented, prepeel: .init(state: .unsupported,
                        evidence: .documentedModel(sourceID: "synthetic-prepeel-not-applicable")))
                let modeOnly = try FinishingFramedOutput.prepare(preparation, qualification: withoutPrepeel)
                let expectedModeOnly = expected.map { step -> FinishingOutputStep in
                    if case let .formatFile(ordinal, bytes) = step {
                        return .formatFile(outputLabel: ordinal, bytes: Data(String(decoding: bytes, as: UTF8.self)
                            .replacingOccurrences(of: "^MMP,N\n", with: "^MMP\n").utf8))
                    }
                    return step
                }
                XCTAssertEqual(modeOnly.steps, expectedModeOnly)
            }
            XCTAssertEqual(framed.totalEncodedBytes, total)
            XCTAssertNoThrow(try FinishingFramedOutput.prepare(preparation, qualification: qualification, maximumBytes: total))
            XCTAssertThrowsError(try FinishingFramedOutput.prepare(preparation, qualification: qualification, maximumBytes: total - 1))
            XCTAssertThrowsError(try FinishingFramedOutput.prepare(preparation, qualification: qualification, maximumBytes: 0))
            let cancellation = OfflineRenderWorkerCancellation(); cancellation.cancel()
            XCTAssertThrowsError(try FinishingFramedOutput.prepare(preparation, qualification: qualification, cancellation: cancellation)) {
                XCTAssertEqual($0 as? FinishingFramedOutput.Error, .cancelled)
            }
            XCTAssertThrowsError(try FinishingFramedOutput.prepare(preparation, qualification: qualification, deadlineSeconds: 0))
            XCTAssertThrowsError(try FinishingFramedOutput.prepare(preparation, qualification: qualification,
                deadlineSeconds: Double.leastNonzeroMagnitude)) {
                XCTAssertEqual($0 as? FinishingFramedOutput.Error, .timedOut)
            }
        }
    }

    func testRasterBindingRejectsReorderingReplacementAndDimensionsWithIdenticalBytes() throws {
        let job = try job()
        let a = try MonochromeBitmap(width: 8, height: 2, bytes: [0x80, 0])
        let b = try MonochromeBitmap(width: 8, height: 2, bytes: [0x40, 0])
        let reshaped = try MonochromeBitmap(width: 4, height: 2, bytes: a.bytes)
        let binding = try FinishingRasterBinding(job: job, orderedRasters: [a, b])
        XCTAssertEqual(binding.totalPackedBytes, 4)
        XCTAssertEqual(binding.labels.map(\.width), [8, 8])
        XCTAssertEqual(binding.orderedRasterSHA256.count, 64)
        XCTAssertNoThrow(try binding.validate(job: job, orderedRasters: [a, b]))
        for changed in [[b, a], [a, a], [reshaped, b]] {
            XCTAssertThrowsError(try binding.validate(job: job, orderedRasters: changed))
            XCTAssertNotEqual(try FinishingRasterBinding(job: job, orderedRasters: changed).orderedRasterSHA256,
                binding.orderedRasterSHA256)
        }
    }

    func testRasterCountByteBudgetGeometryAndCancellationRemainIndependent() throws {
        let job = try job(), bitmap = try MonochromeBitmap(width: 8, height: 1, bytes: [0x80])
        for changed in [[], [bitmap], [bitmap, bitmap, bitmap]] {
            XCTAssertThrowsError(try FinishingRasterBinding(job: job, orderedRasters: changed))
        }
        for limit in [0, -1, FinishingRasterBinding.maximumTotalBytes + 1, Int.max] {
            XCTAssertThrowsError(try FinishingRasterBinding(job: job, orderedRasters: [bitmap, bitmap], maximumTotalBytes: limit))
        }
        XCTAssertThrowsError(try FinishingRasterBinding(job: job, orderedRasters: [bitmap, bitmap], maximumTotalBytes: 1))
        XCTAssertNoThrow(try FinishingRasterBinding(job: job, orderedRasters: [bitmap, bitmap], maximumTotalBytes: 2))
        let wide = try MonochromeBitmap(width: 8193, height: 1, bytes: Array(repeating: 0, count: 1025))
        XCTAssertThrowsError(try FinishingRasterBinding(job: job, orderedRasters: [wide, bitmap]))
        let tall = try MonochromeBitmap(width: 1, height: 65536, bytes: Array(repeating: 0, count: 65536))
        XCTAssertThrowsError(try FinishingRasterBinding(job: job, orderedRasters: [tall, bitmap]))
        let pixels = try MonochromeBitmap(width: 8192, height: 4097,
            bytes: Array(repeating: 0, count: 1024 * 4097))
        XCTAssertThrowsError(try FinishingRasterBinding(job: job, orderedRasters: [pixels, bitmap]))
        let cancelled = OfflineRenderWorkerCancellation(); cancelled.cancel()
        XCTAssertThrowsError(try FinishingRasterBinding(job: job, orderedRasters: [bitmap, bitmap], cancellation: cancelled)) {
            XCTAssertEqual($0 as? FinishingRasterBinding.Error, .cancelled)
        }
    }

    func testRasterBindingRejectsChangedProfileModeAndScheduleDespiteSameRasterInputs() throws {
        let store = try store(), reference = try store.save(id: "synthetic-finishing", profile: profile())
        let old = try store.finishingPlan(reference: reference, mode: .cut, outputLabelCount: 1, schedule: .endOfJob)
        let bitmap = try MonochromeBitmap(width: 8, height: 1, bytes: [0x80])
        let binding = try FinishingRasterBinding(job: old, orderedRasters: [bitmap])
        let next = try store.save(id: reference.id, profile: profile(revision: 12))
        for changed in [try store.finishingPlan(reference: next, mode: .cut, outputLabelCount: 1, schedule: .endOfJob),
                        try store.finishingPlan(reference: reference, mode: .cut, outputLabelCount: 1, schedule: .everyLabel),
                        try store.finishingPlan(reference: reference, mode: .peel, outputLabelCount: 1)] {
            XCTAssertThrowsError(try binding.validate(job: changed, orderedRasters: [bitmap]))
        }
        XCTAssertNoThrow(try binding.validate(job: old, orderedRasters: [bitmap]))
    }

    func testColdStorePlansEveryModeUsingTheExactRevisionAndCompleteCount() throws {
        let store = try store(), original = try profile()
        let reference = try store.save(id: "synthetic-finishing", profile: original)
        let cold = try PrinterProfileStore(root: store.root)
        for mode in modes {
            let schedule: CutSchedule? = mode == .cut ? .batch(size: 3, cutRemainderAtJobEnd: true) : nil
            let result = try cold.finishingPlan(reference: reference, mode: mode, outputLabelCount: 7, schedule: schedule)
            XCTAssertEqual(result.printer.reference, reference)
            XCTAssertEqual(result.printer.profile, original)
            XCTAssertEqual(result.plan.media, original.media)
            XCTAssertEqual(result.plan.cutAfterOutputLabels, mode == .cut ? [3, 6, 7] : [])
            XCTAssertNoThrow(try result.validateBinding(printer: reference, outputLabelCount: 7, mode: mode, schedule: schedule))
            XCTAssertThrowsError(try original.resolveControls(job: .init(finishing: mode)))
        }
    }

    func testEveryBindingComponentRejectsSubstitutionIncludingPartialBatchPolicy() throws {
        let store = try store(), reference = try store.save(id: "synthetic-finishing", profile: profile())
        let schedule = CutSchedule.batch(size: 3, cutRemainderAtJobEnd: true)
        let result = try store.finishingPlan(reference: reference, mode: .cut, outputLabelCount: 7, schedule: schedule)
        for changed in [try ImmutableProfileReference(id: "other", schemaVersion: 8, revision: reference.revision, sha256: reference.sha256),
                        try ImmutableProfileReference(id: reference.id, schemaVersion: 7, revision: reference.revision, sha256: reference.sha256),
                        try ImmutableProfileReference(id: reference.id, schemaVersion: 8, revision: reference.revision + 1, sha256: reference.sha256),
                        try ImmutableProfileReference(id: reference.id, schemaVersion: 8, revision: reference.revision, sha256: String(repeating: "a", count: 64))] {
            XCTAssertThrowsError(try result.validateBinding(printer: changed, outputLabelCount: 7, mode: .cut, schedule: schedule))
        }
        XCTAssertThrowsError(try result.validateBinding(printer: reference, outputLabelCount: 6, mode: .cut, schedule: schedule))
        XCTAssertThrowsError(try result.validateBinding(printer: reference, outputLabelCount: 7, mode: .peel, schedule: schedule))
        for changed in [CutSchedule.endOfJob, .batch(size: 3, cutRemainderAtJobEnd: false), .batch(size: 2, cutRemainderAtJobEnd: true)] {
            XCTAssertThrowsError(try result.validateBinding(printer: reference, outputLabelCount: 7, mode: .cut, schedule: changed))
        }
    }

    func testLaterRevisionCannotAlterOldPlanOrItsBatchLimit() throws {
        let store = try store(), old = try store.save(id: "synthetic-finishing", profile: profile())
        let result = try store.finishingPlan(reference: old, mode: .cut, outputLabelCount: 7, schedule: .endOfJob)
        let next = try store.save(id: old.id, profile: profile(revision: 12, maximumBatch: 5))
        XCTAssertThrowsError(try store.finishingPlan(reference: old, mode: .cut, outputLabelCount: 7,
            schedule: .batch(size: 4, cutRemainderAtJobEnd: true)))
        XCTAssertEqual(try store.finishingPlan(reference: next, mode: .cut, outputLabelCount: 7,
            schedule: .batch(size: 4, cutRemainderAtJobEnd: true)).plan.cutAfterOutputLabels, [4, 7])
        XCTAssertEqual(result.printer.reference, old)
        XCTAssertEqual(result.plan.scheduleQualification.maximumBatchSize, 3)
        XCTAssertEqual(result.plan.cutAfterOutputLabels, [7])
    }

    func testMissingConfigurationLegacyAndForgedDigestFailBeforePlanning() throws {
        let store = try store()
        let missing = try store.save(id: "missing", profile: profile(includeConfiguration: false))
        XCTAssertThrowsError(try store.finishingPlan(reference: missing, mode: .tearOff, outputLabelCount: 1))
        let legacy = try store.save(id: "legacy", profile: PrinterProfile.gc420dUSBReference())
        XCTAssertThrowsError(try store.finishingPlan(reference: legacy, mode: .tearOff, outputLabelCount: 1))
        let good = try store.save(id: "synthetic-finishing", profile: profile())
        let forged = try ImmutableProfileReference(id: good.id, schemaVersion: 8, revision: good.revision,
            sha256: String(repeating: "f", count: 64))
        XCTAssertThrowsError(try store.finishingPlan(reference: forged, mode: .cut, outputLabelCount: 1, schedule: .endOfJob))
    }
}
