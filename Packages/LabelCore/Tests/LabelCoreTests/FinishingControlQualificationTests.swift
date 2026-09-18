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

    func testCutModeSupportCannotSubstituteForEachScheduleOrInstalledCutter() throws {
        for schedule in [CutSchedule.everyLabel, .batch(size: 2, cutRemainderAtJobEnd: true), .endOfJob] {
            XCTAssertThrowsError(try CutSchedulePlanner.boundaries(afterOutputLabels: 3,
                schedule: schedule, finishing: policy))
            XCTAssertThrowsError(try CutSchedulePlanner.boundaries(afterOutputLabels: 3,
                schedule: schedule, finishing: .init(modes: policy.modes, enabledModes: [.cut]), qualification: schedules))
        }
        for size in [0, -1, 6, Int.min, Int.max] {
            XCTAssertThrowsError(try CutSchedulePlanner.boundaries(afterOutputLabels: 7,
                schedule: .batch(size: size, cutRemainderAtJobEnd: true), finishing: policy, qualification: schedules))
        }
        for count in [0, -1, 10_001, Int.max] {
            XCTAssertThrowsError(try CutSchedulePlanner.boundaries(afterOutputLabels: count,
                schedule: .endOfJob, finishing: policy, qualification: schedules))
        }
    }

    func testMalformedBatchDeclarationsDoNotTurnUnknownIntoUnlimited() throws {
        for qualification in [CutScheduleQualification(batch: supported),
                              .init(maximumBatchSize: 0),
                              .init(batch: supported, maximumBatchSize: Int.max),
                              .init(batch: .init(state: .supported, evidence: .unobserved), maximumBatchSize: 5)] {
            XCTAssertThrowsError(try CutSchedulePlanner.boundaries(afterOutputLabels: 3,
                schedule: .everyLabel, finishing: policy, qualification: qualification))
        }
    }
}
