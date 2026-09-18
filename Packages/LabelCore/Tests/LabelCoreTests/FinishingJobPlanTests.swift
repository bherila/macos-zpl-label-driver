import XCTest
@testable import LabelCore

final class FinishingJobPlanTests: XCTestCase {
    private let modes: [FinishingMode] = [.tearOff, .cut, .peel, .rewind]
    private let fact = CapabilityFact(state: .supported,
        evidence: .documentedModel(sourceID: "synthetic-finishing-stock"))
    private var media: MediaConfiguration {
        .init(form: .observed(.preCut, evidence: .reportedInstallation),
              nominalLabelFace: .unobserved, configuredTracking: .unobserved,
              calibration: .unobserved)
    }
    private var finishing: FinishingControlQualification {
        .init(modes: Dictionary(uniqueKeysWithValues: modes.map { ($0, fact) }),
              enabledModes: Set(modes), installed: .init(
                cutter: .observed(true, evidence: .reportedInstallation),
                peeler: .observed(true, evidence: .reportedInstallation),
                rewinder: .observed(true, evidence: .reportedInstallation)))
    }
    private var qualification: CutScheduleQualification {
        .init(everyLabel: fact, batch: fact, endOfJob: fact, maximumBatchSize: 5)
    }
    private func plan(_ mode: FinishingMode, stock: FinishingStockQualification,
                      schedule: CutSchedule? = nil, count: Int = 7) throws -> FinishingJobPlan {
        try .init(mode: mode, outputLabelCount: count, media: media, stock: stock,
                  finishing: finishing, schedule: schedule, scheduleQualification: qualification)
    }
    private var stock: FinishingStockQualification {
        .init(media: media, compatibleModes: Dictionary(uniqueKeysWithValues: modes.map {
            ($0, .observed(true, evidence: .reportedInstallation))
        }))
    }

    func testEveryModeRequiresItsOwnStockDeclarationDespiteInstalledAccessories() throws {
        for mode in modes {
            for observation in [Observation<Bool>.unobserved,
                                .observed(false, evidence: .reportedInstallation),
                                .observed(true, evidence: .unobserved),
                                .observed(true, evidence: fact.evidence)] {
                var declarations = stock.compatibleModes; declarations[mode] = observation
                XCTAssertThrowsError(try plan(mode, stock: .init(media: media,
                    compatibleModes: declarations), schedule: mode == .cut ? .endOfJob : nil))
            }
            var declarations = stock.compatibleModes; declarations.removeValue(forKey: mode)
            XCTAssertThrowsError(try plan(mode, stock: .init(media: media,
                compatibleModes: declarations), schedule: mode == .cut ? .endOfJob : nil))
        }
    }

    func testSuitabilityDoesNotTransferToChangedMediaOrBecomeObservedGeometry() throws {
        let changed = MediaConfiguration(form: .observed(.continuous, evidence: .reportedInstallation),
            nominalLabelFace: .unobserved, configuredTracking: .unobserved, calibration: .unobserved)
        XCTAssertThrowsError(try FinishingJobPlan(mode: .cut, outputLabelCount: 7, media: changed,
            stock: stock, finishing: finishing, schedule: .endOfJob, scheduleQualification: qualification))
        let result = try plan(.cut, stock: stock, schedule: .batch(size: 3, cutRemainderAtJobEnd: true))
        XCTAssertEqual(result.media, media)
        XCTAssertEqual(result.media.calibration, .unobserved)
        XCTAssertEqual(result.media.configuredTracking, .unobserved)
        XCTAssertEqual(result.stock, stock)
        XCTAssertEqual(result.cutAfterOutputLabels, [3, 6, 7])
        XCTAssertEqual(result.finishing, finishing)
    }

    func testCutScheduleRequiredAndNeverSilentlyDroppedByOtherModes() throws {
        XCTAssertThrowsError(try plan(.cut, stock: stock))
        for mode in [FinishingMode.tearOff, .peel, .rewind] {
            XCTAssertThrowsError(try plan(mode, stock: stock, schedule: .endOfJob))
            XCTAssertEqual(try plan(mode, stock: stock).cutAfterOutputLabels, [])
        }
        XCTAssertThrowsError(try FinishingJobPlan(mode: .cut, outputLabelCount: 7,
            media: media, stock: stock, finishing: finishing, schedule: .endOfJob))
    }

    func testCountAndAccessoryGatesCannotBeBypassedByCompatibleStock() throws {
        for count in [0, -1, 10_001, Int.max] {
            XCTAssertThrowsError(try plan(.cut, stock: stock, schedule: .endOfJob, count: count))
        }
        XCTAssertThrowsError(try FinishingJobPlan(mode: .cut, outputLabelCount: 7,
            media: media, stock: stock,
            finishing: .init(modes: finishing.modes, enabledModes: finishing.enabledModes),
            schedule: .endOfJob, scheduleQualification: qualification))
        XCTAssertEqual(try plan(.cut, stock: stock, schedule: .endOfJob, count: 10_000)
            .cutAfterOutputLabels, [10_000])
    }
}
