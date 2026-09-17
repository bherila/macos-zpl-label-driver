import Foundation
import XCTest
@testable import LabelCore

final class FinishingQueueDefinitionTests: XCTestCase {
    private let documented = CapabilityFact(state: .supported,
        evidence: .documentedModel(sourceID: "synthetic-finishing-queue"))
    private func profile(maximumBatch: Int = 3, stock: Observation<Bool> = .observed(true, evidence: .reportedInstallation)) throws -> PrinterProfile {
        let base = try PrinterProfile.gc420dUSBReference(revision: 11)
        return try .init(schemaVersion: 8, revision: base.revision,
            capabilities: .init(model: "synthetic-finishing-queue", thermalTransfer: base.capabilities.thermalTransfer,
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
    private func workflow() throws -> WorkflowProfile {
        let initial = try ReferenceWorkflowDefinition.gc420dInitialSet()
        guard case let .ready(profile) = initial[0].readiness else { throw FinishingQueueDefinition.Error.invalidReference }
        return profile
    }
    private func queue(_ selection: FinishingQueueSelection = .init(mode: .cut,
                                 schedule: .batch(size: 3, cutRemainderAtJobEnd: true)),
                       printer: PrinterProfile, workflow: WorkflowProfile,
                       defaults: PrinterControlDefaults = .init(printSpeedIps: 3)) throws -> FinishingQueueDefinition {
        try .init(id: "synthetic-finishing", revision: 2, displayName: "Synthetic finishing",
            physicalDevice: .init(sha256: String(repeating: "a", count: 64)),
            workflowProfile: .init(id: workflow.id, schemaVersion: workflow.schemaVersion,
                revision: workflow.revision, sha256: String(repeating: "b", count: 64)),
            printerProfile: .init(id: "synthetic-printer", schemaVersion: printer.schemaVersion,
                revision: printer.revision, sha256: String(repeating: "c", count: 64)),
            defaultSelection: selection, workflowDefaults: defaults,
            validatingWorkflow: workflow, validatingPrinter: printer)
    }
    func testEveryModeBindsFullDefaultsAndCompleteExpandedCount() throws {
        let p = try profile(), w = try workflow()
        for mode in [FinishingMode.tearOff, .cut, .peel, .rewind] {
            let q = try queue(.init(mode: mode, schedule: mode == .cut ? .endOfJob : nil), printer: p, workflow: w)
            let resolved = try q.resolve(outputLabelCount: 7, workflow: w, printer: p)
            XCTAssertEqual(resolved.plan.outputLabelCount, 7)
            XCTAssertEqual(resolved.controls.finishing, .value(mode))
            XCTAssertEqual(resolved.controls.printSpeedIps, .value(3))
            XCTAssertEqual(resolved.plan.cutAfterOutputLabels, mode == .cut ? [7] : [])
            XCTAssertThrowsError(try ZPLControlEncoder().encode(resolved.controls)) // Ordinary admission stays closed.
        }
    }
    func testBatchRemainderAndWholeSelectionReplacementDoNotLeakCutPolicy() throws {
        let p = try profile(), w = try workflow(), q = try queue(printer: p, workflow: w)
        XCTAssertEqual(try q.resolve(outputLabelCount: 7, workflow: w, printer: p).plan.cutAfterOutputLabels, [3, 6, 7])
        let peel = try q.resolve(outputLabelCount: 7, workflow: w, printer: p, selection: .init(mode: .peel))
        XCTAssertNil(peel.plan.schedule)
        XCTAssertTrue(peel.plan.cutAfterOutputLabels.isEmpty)
        XCTAssertThrowsError(try q.resolve(outputLabelCount: 7, workflow: w, printer: p,
            selection: .init(mode: .peel), job: .init(finishing: .cut)))
        XCTAssertThrowsError(try q.resolve(outputLabelCount: 7, workflow: w, printer: p, job: .init(finishing: .peel)))
    }
    func testSameRevisionDifferentPolicyCannotSubstituteForSnapshot() throws {
        let p = try profile(), w = try workflow(), q = try queue(printer: p, workflow: w)
        XCTAssertThrowsError(try q.resolve(outputLabelCount: 7, workflow: w, printer: profile(maximumBatch: 4))) {
            XCTAssertEqual($0 as? FinishingQueueDefinition.Error, .snapshotMismatch)
        }
        let changed = try WorkflowProfile(id: w.id, revision: w.revision, outputStockID: w.outputStockID,
            outputStock: w.outputStock, monochromeConversion: .textAndBarcodeThreshold(cutoff: 99), pageRules: w.pageRules)
        XCTAssertThrowsError(try q.resolve(outputLabelCount: 7, workflow: changed, printer: p)) {
            XCTAssertEqual($0 as? FinishingQueueDefinition.Error, .snapshotMismatch)
        }
    }
    func testInvalidCountsUnverifiedStockScheduleAndDefaultsFailInsteadOfClamping() throws {
        let p = try profile(), w = try workflow(), q = try queue(printer: p, workflow: w)
        for count in [0, 10_001, Int.max] { XCTAssertThrowsError(try q.resolve(outputLabelCount: count, workflow: w, printer: p)) }
        for selection in [FinishingQueueSelection(mode: .cut), .init(mode: .peel, schedule: .endOfJob),
                          .init(mode: .cut, schedule: .batch(size: 4, cutRemainderAtJobEnd: true))] {
            XCTAssertThrowsError(try queue(selection, printer: p, workflow: w))
        }
        XCTAssertThrowsError(try queue(printer: profile(stock: .unobserved), workflow: w))
        XCTAssertThrowsError(try queue(printer: p, workflow: w, defaults: .init(finishing: .peel)))
        XCTAssertThrowsError(try queue(printer: p, workflow: w, defaults: .init(printSpeedIps: 5)))
        XCTAssertThrowsError(try queue(printer: PrinterProfile.gc420dUSBReference(), workflow: w))
    }
    func testStockMismatchAndExplicitZeroRemainIndependentOfSelection() throws {
        let p = try profile(), w = try workflow()
        let wrongStock = try WorkflowProfile(id: w.id, revision: w.revision, outputStockID: w.outputStockID,
            outputStock: PhysicalSize(width: Millimeters.inches(3), height: Millimeters.inches(6)), pageRules: w.pageRules)
        XCTAssertThrowsError(try queue(printer: p, workflow: wrongStock)) {
            XCTAssertEqual($0 as? FinishingQueueDefinition.Error, .stockMismatch)
        }
        let q = try queue(printer: p, workflow: w, defaults: .init(printSpeedIps: 3, darkness: 9))
        XCTAssertEqual(try q.resolve(outputLabelCount: 7, workflow: w, printer: p,
            job: .init(darkness: 0)).controls.darkness, .value(0))
        XCTAssertEqual(try q.resolve(outputLabelCount: 7, workflow: w, printer: p).controls.darkness, .value(9))
    }

    func testCanonicalFinishingPolicyRoundTripsEveryModeWithoutOrdinaryAdmission() throws {
        let p = try profile(), w = try workflow()
        for mode in [FinishingMode.tearOff, .cut, .peel, .rewind] {
            let q = try queue(.init(mode: mode, schedule: mode == .cut ? .batch(size: 3, cutRemainderAtJobEnd: false) : nil),
                printer: p, workflow: w, defaults: .init(printSpeedIps: 3, darkness: 0))
            let bytes = try FinishingQueueJSON.encode(q)
            XCTAssertEqual(try FinishingQueueJSON.decode(bytes, workflow: w, printer: p), q)
            let refs = try FinishingQueueJSON.references(in: bytes)
            XCTAssertEqual(refs.workflow, q.workflowProfile)
            XCTAssertEqual(refs.printer, q.printerProfile)
            XCTAssertThrowsError(try VirtualQueueJSON.decode(bytes, validatingAgainst: p))
        }
    }
    func testCanonicalPolicyRejectsDuplicateKeysBooleansAndAlteredSchedule() throws {
        let p = try profile(), w = try workflow(), q = try queue(printer: p, workflow: w)
        let bytes = try FinishingQueueJSON.encode(q)
        let text = String(decoding: bytes, as: UTF8.self)
        let duplicate = Data(("{\"id\":\"ignored\"," + text.dropFirst()).utf8)
        XCTAssertThrowsError(try FinishingQueueJSON.decode(duplicate, workflow: w, printer: p))
        for (before, after) in [("\"size\":3", "\"size\":true"),
                                 ("\"cutRemainderAtJobEnd\":true", "\"cutRemainderAtJobEnd\":1"),
                                 ("\"size\":3", "\"size\":4"),
                                 ("\"revision\":2", "\"revision\":true"),
                                 ("\"kind\":\"offlineFinishingQueue\"", "\"kind\":\"ordinaryQueue\"")] {
            XCTAssertTrue(text.contains(before))
            XCTAssertThrowsError(try FinishingQueueJSON.decode(Data(text.replacingOccurrences(of: before, with: after).utf8), workflow: w, printer: p))
        }
        XCTAssertThrowsError(try FinishingQueueJSON.decode(bytes + Data([32]), workflow: w, printer: p))
        XCTAssertThrowsError(try FinishingQueueJSON.references(in: Data(repeating: 32, count: FinishingQueueJSON.maximumBytes + 1)))
    }
}
