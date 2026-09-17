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
                printSpeedChoicesIps: c.printSpeedChoicesIps, darkness: c.darkness),
            installedHardware: .init(transport: .usb, selectedFinishing: .tearOff, cutter: installed,
                peeler: installed, observedSpeedIps: nil, observedDarkness: nil, observedTracking: nil),
            media: base.media, connection: base.connection,
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
