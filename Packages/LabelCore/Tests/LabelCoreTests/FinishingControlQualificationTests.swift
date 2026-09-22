import Foundation
import XCTest
@testable import LabelCore

final class FinishingControlQualificationTests: XCTestCase {
    private let supported = CapabilityFact(state: .supported,
        evidence: .documentedModel(sourceID: "synthetic-finishing-fixture"))
    private var policy: FinishingControlQualification {
        .init(modes: [.tearOff: supported, .cut: supported, .peel: supported, .rewind: supported],
            enabledModes: [.tearOff, .cut, .peel, .rewind], installed: .init(
                cutter: .observed(true, evidence: .reportedInstallation),
                peeler: .observed(true, evidence: .reportedInstallation),
                rewinder: .observed(true, evidence: .reportedInstallation)))
    }
    private var schedules: CutScheduleQualification {
        .init(everyLabel: supported, batch: supported, endOfJob: supported, maximumBatchSize: 5)
    }

    func testEveryModeRequiresIndependentSupportEnabledConfigurationAndExactBytes() throws {
        for (mode, command) in [(FinishingMode.tearOff, "^MMT\n"), (.cut, "^MMC\n"),
                                (.peel, "^MMP\n"), (.rewind, "^MMR\n")] {
            XCTAssertEqual(try policy.encodeMode(mode), Data(command.utf8))
            XCTAssertThrowsError(try FinishingControlQualification(modes: policy.modes,
                enabledModes: [], installed: policy.installed).encodeMode(mode))
            for fact in [CapabilityFact(state: .unknown, evidence: .unobserved),
                         .init(state: .unsupported, evidence: supported.evidence),
                         .init(state: .supported, evidence: .unobserved)] {
                var modes = policy.modes; modes[mode] = fact
                XCTAssertThrowsError(try FinishingControlQualification(modes: modes,
                    enabledModes: policy.enabledModes, installed: policy.installed).encodeMode(mode))
            }
        }
        XCTAssertEqual(try FinishingControlQualification(modes: [.tearOff: supported],
            enabledModes: [.tearOff]).encodeMode(.tearOff), Data("^MMT\n".utf8))
    }

    func testEachAccessoryNeedsTrueInstallationObservationAndCannotUseModelDocumentation() throws {
        for mode in [FinishingMode.cut, .peel, .rewind] {
            for bad in [Observation<Bool>.unobserved, .observed(false, evidence: .reportedInstallation),
                        .observed(true, evidence: .unobserved), .observed(true, evidence: supported.evidence)] {
                let installed = InstalledFinishingAccessories(
                    cutter: mode == .cut ? bad : policy.installed.cutter,
                    peeler: mode == .peel ? bad : policy.installed.peeler,
                    rewinder: mode == .rewind ? bad : policy.installed.rewinder)
                XCTAssertThrowsError(try FinishingControlQualification(modes: policy.modes,
                    enabledModes: policy.enabledModes, installed: installed).encodeMode(mode))
            }
        }
    }

    func testModesRemainOfflineAndDoNotSelectCutIntervalsCopiesOrDestructiveCommands() throws {
        for mode in [FinishingMode.tearOff, .cut, .peel, .rewind] {
            let text = String(decoding: try policy.encodeMode(mode), as: UTF8.self)
            for forbidden in ["^PQ", "~JK", "^CN", "~JC", "^JU", "~JR", "^XA", "^XZ"] {
                XCTAssertFalse(text.contains(forbidden))
            }
        }
        XCTAssertThrowsError(try policy.encodeMode(.cut, maximumOutputBytes: 4))
        XCTAssertThrowsError(try policy.encodeMode(.cut, maximumOutputBytes: 0))
        let baseline = try PrinterProfile.gc420dUSBReference()
        for mode in [FinishingMode.cut, .peel, .rewind] {
            XCTAssertThrowsError(try baseline.validate(.init(finishing: mode)))
        }
    }

    func testCutSchedulesUseCompleteOutputOrderAndExplicitRemainderPolicy() throws {
        func plan(_ schedule: CutSchedule, count: Int = 7) throws -> [Int] {
            try CutSchedulePlanner.boundaries(afterOutputLabels: count, schedule: schedule,
                finishing: policy, qualification: schedules)
        }
        XCTAssertEqual(try plan(.everyLabel), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(try plan(.endOfJob), [7])
        XCTAssertEqual(try plan(.batch(size: 3, cutRemainderAtJobEnd: true)), [3, 6, 7])
        XCTAssertEqual(try plan(.batch(size: 3, cutRemainderAtJobEnd: false)), [3, 6])
        XCTAssertEqual(try plan(.batch(size: 5, cutRemainderAtJobEnd: true), count: 2), [2])
        XCTAssertEqual(try plan(.batch(size: 5, cutRemainderAtJobEnd: false), count: 2), [])
        XCTAssertEqual(try plan(.batch(size: 3, cutRemainderAtJobEnd: true), count: 6), [3, 6])
        XCTAssertEqual(try plan(.everyLabel, count: 10_000).count, 10_000)
    }

    /// Names the exact refusal, so a schedule admission failure can never be
    /// satisfied by an unrelated rule that happens to reject the same input.
    private func refusal(_ count: Int, _ schedule: CutSchedule,
                         finishing: FinishingControlQualification,
                         qualification: CutScheduleQualification,
                         file: StaticString = #filePath, line: UInt = #line) -> Error? {
        var captured: Error?
        XCTAssertThrowsError(try CutSchedulePlanner.boundaries(afterOutputLabels: count,
            schedule: schedule, finishing: finishing, qualification: qualification),
            file: file, line: line) { captured = $0 }
        return captured
    }

    func testCutModeSupportCannotSubstituteForEachScheduleOrInstalledCutter() throws {
        for schedule in [CutSchedule.everyLabel, .batch(size: 2, cutRemainderAtJobEnd: true), .endOfJob] {
            XCTAssertEqual(refusal(3, schedule, finishing: policy, qualification: .init())
                as? CutSchedulePlanner.Error, .unavailableSchedule(.unknown))
            XCTAssertEqual(refusal(3, schedule,
                finishing: .init(modes: policy.modes, enabledModes: [.cut]), qualification: schedules)
                as? FinishingControlQualification.Error, .unverifiedAccessory(.cut))
        }
        for size in [0, -1, 6, Int.min, Int.max] {
            XCTAssertEqual(refusal(7, .batch(size: size, cutRemainderAtJobEnd: true),
                finishing: policy, qualification: schedules)
                as? CutSchedulePlanner.Error, .invalidBatchSize)
        }
        // Both sides of the declared 1...maximumBatchSize interval.
        XCTAssertEqual(try CutSchedulePlanner.boundaries(afterOutputLabels: 7,
            schedule: .batch(size: 1, cutRemainderAtJobEnd: false), finishing: policy,
            qualification: schedules), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(try CutSchedulePlanner.boundaries(afterOutputLabels: 7,
            schedule: .batch(size: 5, cutRemainderAtJobEnd: false), finishing: policy,
            qualification: schedules), [5])
        for count in [0, -1, 10_001, Int.max] {
            XCTAssertEqual(refusal(count, .endOfJob, finishing: policy, qualification: schedules)
                as? CutSchedulePlanner.Error, .invalidLabelCount)
        }
        // Both sides of the 1...maximumLabels output-count interval.
        XCTAssertEqual(try CutSchedulePlanner.boundaries(afterOutputLabels: 1, schedule: .endOfJob,
            finishing: policy, qualification: schedules), [1])
        XCTAssertEqual(try CutSchedulePlanner.boundaries(afterOutputLabels: 10_000, schedule: .endOfJob,
            finishing: policy, qualification: schedules), [10_000])
    }

    func testMalformedBatchDeclarationsDoNotTurnUnknownIntoUnlimited() throws {
        let unevidenced = CapabilityFact(state: .supported, evidence: .unobserved)
        // Every declaration below is asked about the batch schedule it actually
        // describes. Asking about a different schedule would be refused by the
        // per-schedule support rule instead, which hides this rule entirely.
        for qualification: CutScheduleQualification in [
            .init(batch: supported),
            .init(batch: supported, maximumBatchSize: 0),
            .init(batch: supported, maximumBatchSize: 10_001),
            .init(batch: supported, maximumBatchSize: Int.max),
            .init(batch: unevidenced, maximumBatchSize: 5),
            // A maximum without a supported batch declaration is not a limit.
            .init(everyLabel: supported, endOfJob: supported, maximumBatchSize: 5),
            .init(maximumBatchSize: 0),
        ] {
            XCTAssertEqual(refusal(3, .batch(size: 2, cutRemainderAtJobEnd: true),
                finishing: policy, qualification: qualification)
                as? CutSchedulePlanner.Error, .invalidBatchDeclaration)
        }
        // Both sides of the 1...maximumLabels batch-maximum interval.
        for maximum in [1, CutSchedulePlanner.maximumLabels] {
            XCTAssertEqual(try CutSchedulePlanner.boundaries(afterOutputLabels: 3,
                schedule: .batch(size: 1, cutRemainderAtJobEnd: false), finishing: policy,
                qualification: .init(batch: supported, maximumBatchSize: maximum)), [1, 2, 3])
        }
    }

    func testUnknownUnsupportedAndUnevidencedSchedulesAreRefusedPerSchedule() throws {
        let unevidenced = CapabilityFact(state: .supported, evidence: .unobserved)
        let unsupported = CapabilityFact(state: .unsupported, evidence: supported.evidence)
        for (schedule, make) in [
            (CutSchedule.everyLabel, { (fact: CapabilityFact) in
                CutScheduleQualification(everyLabel: fact) }),
            (.endOfJob, { CutScheduleQualification(endOfJob: $0) }),
        ] as [(CutSchedule, (CapabilityFact) -> CutScheduleQualification)] {
            // An unknown schedule is not a usable one, and an unsupported one
            // keeps its own distinct state in the refusal.
            XCTAssertEqual(refusal(3, schedule, finishing: policy,
                qualification: make(.init(state: .unknown, evidence: .unobserved)))
                as? CutSchedulePlanner.Error, .unavailableSchedule(.unknown))
            XCTAssertEqual(refusal(3, schedule, finishing: policy, qualification: make(unsupported))
                as? CutSchedulePlanner.Error, .unavailableSchedule(.unsupported))
            // Supported with no evidence at all is a separate refusal, never a
            // qualified schedule and never collapsed into `unavailableSchedule`.
            XCTAssertEqual(refusal(3, schedule, finishing: policy, qualification: make(unevidenced))
                as? CutSchedulePlanner.Error, .missingScheduleEvidence)
        }
        // A supported batch declaration carrying no evidence is refused by the
        // stricter declaration rule before the per-schedule evidence rule.
        XCTAssertEqual(refusal(3, .batch(size: 2, cutRemainderAtJobEnd: true), finishing: policy,
            qualification: .init(batch: unsupported))
            as? CutSchedulePlanner.Error, .unavailableSchedule(.unsupported))
        // One qualified schedule never qualifies another.
        XCTAssertEqual(refusal(3, .endOfJob, finishing: policy,
            qualification: .init(everyLabel: supported))
            as? CutSchedulePlanner.Error, .unavailableSchedule(.unknown))
    }
}
