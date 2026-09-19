import CryptoKit
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

/// Offline provider-path checks. Nothing here opens a transport, and every
/// satisfied status is synthetic simulator input rather than a device receipt.
final class BoundedFinishingDeliveryTests: XCTestCase {
    private let documented = CapabilityFact(state: .supported,
        evidence: .documentedModel(sourceID: "synthetic-finishing-provider"))
    private let allDispositions: [FinishingDeliveryDisposition] = [
        .allStepsSatisfied, .failedBeforeAttempt, .cancelledBeforeAttempt, .timedOutBeforeAttempt,
        .cancelledAfterAttempt(step: 2), .timedOutAfterAttempt(step: 2),
        .partialTransmission(step: 2, accepted: 32, expected: 64), .ambiguousPublication(step: 0),
        .statusUnknown(step: 1), .statusNotSatisfied(step: 1), .ownershipLost(step: 1),
        .providerFailedAfterAttempt(step: 1)]

    /// Forwards to the inert provider and lets one case observe or disturb the
    /// executor at an exact step. It performs no transport of its own.
    private final class ObservingProvider: FinishingDeliveryProvider {
        let inner: InertFinishingDeliveryProvider
        private let beforePrepare: (FinishingDeviceOwnership) throws -> Void
        private let beforeStep: (Int, FinishingDeviceOwnership) throws -> Void
        init(_ inner: InertFinishingDeliveryProvider,
             beforePrepare: @escaping (FinishingDeviceOwnership) throws -> Void = { _ in },
             beforeStep: @escaping (Int, FinishingDeviceOwnership) throws -> Void = { _, _ in }) {
            self.inner = inner; self.beforePrepare = beforePrepare; self.beforeStep = beforeStep
        }
        func prepare(ownership: FinishingDeviceOwnership) throws -> FinishingDeliveryReadiness {
            try beforePrepare(ownership)
            return try inner.prepare(ownership: ownership)
        }
        func transmit(stepIndex: Int, file: FinishingOutputStep, bytes: Data,
                      ownership: FinishingDeviceOwnership,
                      accepted: (Int) throws -> Void) throws -> FinishingFilePublication {
            try beforeStep(stepIndex, ownership)
            return try inner.transmit(stepIndex: stepIndex, file: file, bytes: bytes,
                                      ownership: ownership, accepted: accepted)
        }
        func awaitStatus(stepIndex: Int, requirement: FinishingOutputStep,
                         ownership: FinishingDeviceOwnership) throws -> FinishingStatusReading {
            try beforeStep(stepIndex, ownership)
            return try inner.awaitStatus(stepIndex: stepIndex, requirement: requirement, ownership: ownership)
        }
    }

    private struct Harness {
        let root: URL
        let leases: URL
        let store: FinishingDeliveryOutcomeStore
        let reference: FinishingArtifactReference
        let domain: PhysicalDeviceCoordinationID
    }

    private func harness(_ name: String, framed: FinishingFramedOutput, in directory: URL) throws -> Harness {
        let root = directory.appending(path: "delivery-\(name)")
        let leases = directory.appending(path: "leases-\(name)")
        try FileManager.default.createDirectory(at: leases, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let archives = try FinishingArtifactStore(root: root)
        let reference = try archives.save(id: "synthetic-delivery-\(name)", revision: 1, output: framed)
        let store = try FinishingDeliveryOutcomeStore(root: root)
        let domain = try PhysicalDeviceCoordinationID(sha256: String(repeating: "a", count: 64))
        return Harness(root: root, leases: leases, store: store, reference: reference, domain: domain)
    }

    private func deliver(_ harness: Harness, framed: FinishingFramedOutput,
                         provider: FinishingDeliveryProvider, deadlineSeconds: Double = 60,
                         cancellation: OfflineRenderWorkerCancellation = .init())
        throws -> BoundedFinishingDelivery.Outcome {
        try BoundedFinishingDelivery.run(output: framed, reference: harness.reference, store: harness.store,
            provider: provider, coordinationID: harness.domain, leaseDirectory: harness.leases,
            deadlineSeconds: deadlineSeconds, cancellation: cancellation)
    }

    private func fileBytes(_ step: FinishingOutputStep) -> Data? {
        switch step {
        case let .formatFile(_, bytes), let .delayedCutFile(_, bytes): return bytes
        default: return nil
        }
    }

    private func profileStore() throws -> PrinterProfileStore {
        let root = FileManager.default.temporaryDirectory.appending(path: "FinishingProviderProfiles-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try PrinterProfileStore(root: root)
    }

    private func profile() throws -> PrinterProfile {
        let modes: [FinishingMode] = [.tearOff, .cut, .peel, .rewind]
        let base = try PrinterProfile.gc420dUSBReference(), capabilities = base.capabilities
        let installed = CapabilityFact(state: .supported, evidence: .reportedInstallation)
        return try .init(schemaVersion: 8, revision: 11,
            capabilities: .init(model: "synthetic-finishing-model", thermalTransfer: capabilities.thermalTransfer,
                cutter: documented, peeler: documented, rewind: documented, tracking: capabilities.tracking,
                printSpeedChoicesIps: capabilities.printSpeedChoicesIps, darkness: documented,
                physicalGeometry: .init(width: .init(fact: documented, maximumDots: 200),
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
            finishingConfiguration: .init(finishing: .init(
                modes: Dictionary(uniqueKeysWithValues: modes.map { ($0, documented) }), enabledModes: Set(modes),
                installed: .init(cutter: .observed(true, evidence: .reportedInstallation),
                    peeler: .observed(true, evidence: .reportedInstallation),
                    rewinder: .observed(true, evidence: .reportedInstallation))),
                stock: .init(media: base.media, compatibleModes: Dictionary(uniqueKeysWithValues: modes.map {
                    ($0, .observed(true, evidence: .reportedInstallation))
                })), schedules: .init(everyLabel: documented, batch: documented, endOfJob: documented,
                    maximumBatchSize: 3)))
    }

    /// Delayed-cut framing gives both complete-file kinds and every status wait.
    @MainActor
    private func makeFramed() throws -> (FinishingFramedOutput, URL) {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let source = try Data(contentsOf: root.appending(path: "Fixtures/generated/native-vector.pdf"))
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let worker = root.appending(path: "Packages/LabelMac/.build/\(configuration)/label-render-worker")
        let directory = FileManager.default.temporaryDirectory.appending(path: "FinishingProvider-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let model = try WorkflowEditorBootstrap.makeModel(originalPDF: source,
            store: WorkflowProfileStore(root: directory))
        let pages = try QuartzPDFRenderer.documentPageBoxes(originalPDF: source)
        let canvas = try DotCanvas(physicalSize: model.profile.outputStock,
            resolution: DotResolution(xDotsPerMillimeter: 1, yDotsPerMillimeter: 1))
        let profiles = try profileStore()
        let reference = try profiles.save(id: "synthetic-provider", profile: profile())
        let count = 3
        let plan = try ExtractionPlanner.plan(sourcePages: pages, profile: model.profile,
            copyPolicy: .engine(copies: count, collated: true))
        let job = try profiles.finishingPlan(reference: reference, mode: .cut, outputLabelCount: count,
            schedule: .batch(size: 2, cutRemainderAtJobEnd: true))
        let preparation = try FinishingRasterPreparation.prepare(job: job,
            controlRequest: .init(finishing: .cut, printSpeedIps: 3, darkness: 0), originalPDF: source,
            extraction: plan, canvas: canvas, conversion: .textAndBarcodeThreshold(cutoff: 128),
            workerExecutable: worker)
        let nonRFID = CapabilityFact(state: .unsupported,
            evidence: .documentedModel(sourceID: "synthetic-provider-non-rfid"))
        let qualification = FinishingOutputQualification(profile: job.printer.profile,
            model: job.printer.profile.capabilities.model, quantityOne: documented,
            labelCompletion: documented, rfid: nonRFID, delayedCutter: documented,
            delayedCutReadiness: documented, cutCompletion: documented,
            completeFileDelivery: .observed(true, evidence: .reportedInstallation),
            peelLabelTaken: documented, prepeel: documented)
        return (try FinishingFramedOutput.prepare(preparation, qualification: qualification), directory)
    }

    @MainActor
    func testEachTerminalDeliveryStateIsDistinctObservableAndDurable() throws {
        let (framed, directory) = try makeFramed()
        let files = framed.steps.indices.filter { fileBytes(framed.steps[$0]) != nil }
        let waits = framed.steps.indices.filter { fileBytes(framed.steps[$0]) == nil }
        XCTAssertGreaterThanOrEqual(files.count, 2)
        XCTAssertGreaterThanOrEqual(waits.count, 2)

        // Success: every framed step satisfied, synthetically and never physically.
        let success = try harness("success", framed: framed, in: directory)
        let satisfied = try InertFinishingDeliveryProvider()
        let confirmed = try deliver(success, framed: framed, provider: satisfied)
        XCTAssertEqual(confirmed.disposition, .allStepsSatisfied)
        XCTAssertFalse(confirmed.isUncertain)
        XCTAssertFalse(confirmed.establishesPhysicalCompletion)
        XCTAssertFalse(confirmed.authorizesBoundedRetry)
        XCTAssertEqual(confirmed.tracker.state, .confirmed)
        XCTAssertEqual(confirmed.tracker.bytesAccepted, framed.totalEncodedBytes)
        XCTAssertEqual(satisfied.discardedBytes, framed.totalEncodedBytes)
        XCTAssertEqual(try success.store.observation(reference: success.reference, against: framed),
                       .recorded(.allStepsSatisfied))

        // Refusal before any byte: the only state that authorizes a bounded retry.
        let refused = try harness("refused", framed: framed, in: directory)
        let refusing = try InertFinishingDeliveryProvider(script: .init(refuseBeforeAnyBytes: true))
        let notSent = try deliver(refused, framed: framed, provider: refusing)
        XCTAssertEqual(notSent.disposition, .failedBeforeAttempt)
        XCTAssertFalse(notSent.isUncertain)
        XCTAssertTrue(notSent.authorizesBoundedRetry)
        XCTAssertEqual(refusing.discardedBytes, 0)
        XCTAssertEqual(notSent.tracker.bytesAccepted, 0)
        XCTAssertFalse(notSent.tracker.attemptedAnyFile)
        XCTAssertEqual(try refused.store.observation(reference: refused.reference, against: framed),
                       .recorded(.failedBeforeAttempt))

        // Cancellation before any attempt leaves no durable intent.
        let stopped = try harness("cancelled-early", framed: framed, in: directory)
        let preCancelled = OfflineRenderWorkerCancellation(); preCancelled.cancel()
        let idle = try InertFinishingDeliveryProvider()
        let earlyCancel = try deliver(stopped, framed: framed, provider: idle, cancellation: preCancelled)
        XCTAssertEqual(earlyCancel.disposition, .cancelledBeforeAttempt)
        XCTAssertFalse(earlyCancel.isUncertain)
        XCTAssertFalse(earlyCancel.authorizesBoundedRetry)
        XCTAssertEqual(earlyCancel.tracker.state, .cancelledBeforeAttempt)
        XCTAssertEqual(idle.events, []) // Nothing is offered, not even a readiness check.
        XCTAssertEqual(try stopped.store.observation(reference: stopped.reference, against: framed),
                       .recorded(.cancelledBeforeAttempt))

        // Cancellation after an attempted file is uncertain, never cancelled-clean.
        let late = try harness("cancelled-late", framed: framed, in: directory)
        let token = OfflineRenderWorkerCancellation()
        let cancellingInner = try InertFinishingDeliveryProvider()
        let cancelling = ObservingProvider(cancellingInner) { index, _ in
            if index == waits[0] { token.cancel() }
        }
        let lateCancel = try deliver(late, framed: framed, provider: cancelling, cancellation: token)
        XCTAssertEqual(lateCancel.disposition, .cancelledAfterAttempt(step: files[1]))
        XCTAssertTrue(lateCancel.isUncertain)
        XCTAssertFalse(lateCancel.authorizesBoundedRetry)
        XCTAssertEqual(lateCancel.tracker.state, .uncertain)
        XCTAssertEqual(try late.store.observation(reference: late.reference, against: framed),
                       .recorded(.cancelledAfterAttempt(step: files[1])))

        // Timeout before any attempt is distinct from a proven refusal.
        let earlyDeadline = try harness("timed-out-early", framed: framed, in: directory)
        let slowInner = try InertFinishingDeliveryProvider()
        let slowPrepare = ObservingProvider(slowInner,
                                            beforePrepare: { _ in Thread.sleep(forTimeInterval: 1.05) })
        let earlyTimeout = try deliver(earlyDeadline, framed: framed, provider: slowPrepare, deadlineSeconds: 1)
        XCTAssertEqual(earlyTimeout.disposition, .timedOutBeforeAttempt)
        XCTAssertFalse(earlyTimeout.isUncertain)
        XCTAssertFalse(earlyTimeout.authorizesBoundedRetry)
        XCTAssertEqual(earlyTimeout.tracker.state, .failedBeforeAttempt)

        // Timeout during a status wait after an attempted file stays uncertain.
        let lateDeadline = try harness("timed-out-late", framed: framed, in: directory)
        let slowStatus = try InertFinishingDeliveryProvider(script: .init(statusWaitSeconds: 1))
        let lateTimeout = try deliver(lateDeadline, framed: framed, provider: slowStatus, deadlineSeconds: 1)
        XCTAssertEqual(lateTimeout.disposition, .timedOutAfterAttempt(step: files[1]))
        XCTAssertTrue(lateTimeout.isUncertain)
        XCTAssertFalse(lateTimeout.authorizesBoundedRetry)
        XCTAssertEqual(lateTimeout.tracker.state, .uncertain)

        // Partial transmission retains the exact step and accepted/expected counts.
        let partial = try harness("partial", framed: framed, in: directory)
        let expected = try XCTUnwrap(fileBytes(framed.steps[files[1]]))
        XCTAssertGreaterThan(expected.count, 32)
        let truncating = try InertFinishingDeliveryProvider(script: .init(maximumChunkBytes: 16,
            stopAcceptingAtStep: files[1], acceptedBytesBeforeStopping: 32))
        let short = try deliver(partial, framed: framed, provider: truncating)
        XCTAssertEqual(short.disposition,
            .partialTransmission(step: files[1], accepted: 32, expected: expected.count))
        XCTAssertTrue(short.isUncertain)
        XCTAssertFalse(short.authorizesBoundedRetry)
        XCTAssertEqual(short.tracker.acceptedBytesInCurrentFile, 32)
        XCTAssertEqual(short.tracker.state, .uncertain)

        // Ambiguous publication of a complete file is neither success nor failure.
        let ambiguous = try harness("ambiguous", framed: framed, in: directory)
        let unacknowledged = try InertFinishingDeliveryProvider(
            script: .init(ambiguousPublicationAtStep: files[0]))
        let unresolved = try deliver(ambiguous, framed: framed, provider: unacknowledged)
        XCTAssertEqual(unresolved.disposition, .ambiguousPublication(step: files[0]))
        XCTAssertTrue(unresolved.isUncertain)
        XCTAssertFalse(unresolved.authorizesBoundedRetry)
        XCTAssertEqual(unresolved.tracker.state, .uncertain)
        XCTAssertEqual(try ambiguous.store.observation(reference: ambiguous.reference, against: framed),
                       .recorded(.ambiguousPublication(step: files[0])))

        // Unknown status is never completion, and a real negative stays distinct.
        let unknown = try harness("unknown-status", framed: framed, in: directory)
        let silent = try InertFinishingDeliveryProvider(script: .init(unknownStatusAtStep: waits[0]))
        let unresolvedStatus = try deliver(unknown, framed: framed, provider: silent)
        XCTAssertEqual(unresolvedStatus.disposition, .statusUnknown(step: waits[0]))
        XCTAssertTrue(unresolvedStatus.isUncertain)
        XCTAssertEqual(unresolvedStatus.tracker.nextStepIndex, waits[0])
        let negative = try harness("unsatisfied-status", framed: framed, in: directory)
        let refusedStatus = try InertFinishingDeliveryProvider(script: .init(notSatisfiedStatusAtStep: waits[0]))
        let unsatisfied = try deliver(negative, framed: framed, provider: refusedStatus)
        XCTAssertEqual(unsatisfied.disposition, .statusNotSatisfied(step: waits[0]))
        XCTAssertTrue(unsatisfied.isUncertain)

        // A provider failure after an attempted file cannot become not-sent.
        let broken = try harness("provider-failure", framed: framed, in: directory)
        let failing = try InertFinishingDeliveryProvider(script: .init(failAtStep: waits[0]))
        let failed = try deliver(broken, framed: framed, provider: failing)
        XCTAssertEqual(failed.disposition, .providerFailedAfterAttempt(step: waits[0]))
        XCTAssertTrue(failed.isUncertain)
        XCTAssertFalse(failed.authorizesBoundedRetry)
    }

    @MainActor
    func testColdRecoveryOwnershipAndReplayNegatives() throws {
        let (framed, directory) = try makeFramed()
        let files = framed.steps.indices.filter { fileBytes(framed.steps[$0]) != nil }
        let waits = framed.steps.indices.filter { fileBytes(framed.steps[$0]) == nil }

        // No case, including synthetic full satisfaction, is physical completion,
        // and only a proven pre-attempt refusal authorizes a bounded retry.
        for disposition in allDispositions {
            XCTAssertFalse(disposition.establishesPhysicalCompletion)
            XCTAssertEqual(disposition.authorizesBoundedRetry, disposition == .failedBeforeAttempt)
        }

        // Absence is only absence: it authorizes nothing and is not uncertainty.
        let absent = try harness("absent", framed: framed, in: directory)
        XCTAssertEqual(try absent.store.observation(reference: absent.reference, against: framed),
                       .noRecordedDelivery)
        XCTAssertFalse(try absent.store.observation(reference: absent.reference,
                                                    against: framed).authorizesBoundedRetry)
        XCTAssertFalse(try absent.store.observation(reference: absent.reference, against: framed).isUncertain)
        // Uncertainty can never be recorded as though no attempt had been made.
        XCTAssertThrowsError(try absent.store.recordOutcome(reference: absent.reference, against: framed,
            disposition: .ambiguousPublication(step: files[0]))) {
                XCTAssertEqual($0 as? FinishingDeliveryOutcomeStore.Error, .missingIntent)
        }
        XCTAssertEqual(try absent.store.observation(reference: absent.reference, against: framed),
                       .noRecordedDelivery)

        // A partial transmission survives a restart-like cold reopen exactly, with
        // no provider call and no byte callback during recovery.
        let partial = try harness("cold-partial", framed: framed, in: directory)
        let expected = try XCTUnwrap(fileBytes(framed.steps[files[0]]))
        let truncating = try InertFinishingDeliveryProvider(script: .init(maximumChunkBytes: 8,
            stopAcceptingAtStep: files[0], acceptedBytesBeforeStopping: 24))
        let short = try deliver(partial, framed: framed, provider: truncating)
        let recorded = FinishingDeliveryDisposition.partialTransmission(step: files[0], accepted: 24,
                                                                        expected: expected.count)
        XCTAssertEqual(short.disposition, recorded)
        let discarded = truncating.discardedBytes
        let reopened = try FinishingDeliveryOutcomeStore(root: partial.root)
        XCTAssertEqual(try reopened.observation(reference: partial.reference, against: framed), .recorded(recorded))
        XCTAssertTrue(try reopened.observation(reference: partial.reference, against: framed).isUncertain)
        XCTAssertFalse(try reopened.observation(reference: partial.reference,
                                                against: framed).authorizesBoundedRetry)
        XCTAssertEqual(truncating.discardedBytes, discarded)
        XCTAssertEqual(truncating.events.filter { $0 == .prepared }.count, 1)
        // No path replays after ambiguity: a fresh provider is never even reached.
        let replay = try InertFinishingDeliveryProvider()
        XCTAssertThrowsError(try deliver(partial, framed: framed, provider: replay)) {
            XCTAssertEqual($0 as? BoundedFinishingDelivery.Error, .recordedDeliveryRequiresReview)
        }
        XCTAssertEqual(replay.events, [])
        XCTAssertEqual(replay.discardedBytes, 0)

        // Synthetic completion does not authorize another run either.
        let completed = try harness("cold-complete", framed: framed, in: directory)
        let first = try InertFinishingDeliveryProvider()
        XCTAssertEqual(try deliver(completed, framed: framed, provider: first).disposition, .allStepsSatisfied)
        let afterCompletion = try FinishingDeliveryOutcomeStore(root: completed.root)
        XCTAssertEqual(try afterCompletion.observation(reference: completed.reference, against: framed),
                       .recorded(.allStepsSatisfied))
        let second = try InertFinishingDeliveryProvider()
        XCTAssertThrowsError(try deliver(completed, framed: framed, provider: second)) {
            XCTAssertEqual($0 as? BoundedFinishingDelivery.Error, .recordedDeliveryRequiresReview)
        }
        XCTAssertEqual(second.events, [])

        // Ownership spans every complete file and every status wait, and losing it
        // mid-wait is uncertain rather than a retryable not-sent state.
        let owned = try harness("ownership", framed: framed, in: directory)
        let identity = PhysicalDeviceIdentity(coordinationID: owned.domain)
        let competingInner = try InertFinishingDeliveryProvider()
        let competing = ObservingProvider(competingInner) { index, ownership in
            XCTAssertTrue(ownership.isHeld)
            XCTAssertThrowsError(try PhysicalDeviceLease(acquiring: identity,
                                                         inExistingDirectory: owned.leases)) {
                XCTAssertEqual($0 as? PhysicalDeviceLeaseError, .alreadyHeld)
            }
            XCTAssertThrowsError(try PhysicalDeviceLease(
                acquiring: BoundedFinishingDelivery.artifactIdentity(for: owned.reference),
                inExistingDirectory: owned.leases)) {
                    XCTAssertEqual($0 as? PhysicalDeviceLeaseError, .alreadyHeld)
            }
            if index == waits[0] { ownership.device.release() }
        }
        let lost = try deliver(owned, framed: framed, provider: competing)
        XCTAssertEqual(lost.disposition, .ownershipLost(step: waits[0]))
        XCTAssertTrue(lost.isUncertain)
        XCTAssertFalse(lost.authorizesBoundedRetry)
        XCTAssertEqual(try owned.store.observation(reference: owned.reference, against: framed),
                       .recorded(.ownershipLost(step: waits[0])))
        // Both leases are released on scope exit, including this uncertain exit.
        let free = try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: owned.leases)
        free.release()
        let freeArtifact = try PhysicalDeviceLease(
            acquiring: BoundedFinishingDelivery.artifactIdentity(for: owned.reference),
            inExistingDirectory: owned.leases)
        freeArtifact.release()

        // The closed record codec rejects an alternate spelling of a known state
        // and a record bound to a different reference.
        let forged = try harness("forged", framed: framed, in: directory)
        let name = SHA256.hash(data: Data(forged.reference.id.utf8)).map { String(format: "%02x", $0) }.joined()
        let recordDirectory = forged.root.appending(path: "finishing-deliveries")
        try FileManager.default.createDirectory(at: recordDirectory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let file = recordDirectory.appending(path: "\(name)-r1-o.bin")
        let prefix = "LABEL_FINISHING_DELIVERY_OUTCOME_V1\n\(forged.reference.id)\n1\n\(forged.reference.sha256)\n"
        for token in ["partialTransmission,0,024,64", "partialTransmission,0,64,64", "ownershipLost",
                      "ownershipLost,-1", "allStepsSatisfied,0", "printedAndCut,0", ""] {
            try Data("\(prefix)\(token)\n".utf8).write(to: file)
            XCTAssertThrowsError(try forged.store.observation(reference: forged.reference, against: framed)) {
                XCTAssertEqual($0 as? FinishingDeliveryOutcomeStore.Error, .invalidRecord)
            }
        }
        try Data("LABEL_FINISHING_DELIVERY_OUTCOME_V1\n\(forged.reference.id)\n2\n\(forged.reference.sha256)\nallStepsSatisfied\n".utf8).write(to: file)
        XCTAssertThrowsError(try forged.store.observation(reference: forged.reference, against: framed)) {
            XCTAssertEqual($0 as? FinishingDeliveryOutcomeStore.Error, .invalidRecord)
        }
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(try forged.store.observation(reference: forged.reference, against: framed),
                       .noRecordedDelivery)
    }
}
