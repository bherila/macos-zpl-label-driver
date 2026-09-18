import Foundation
import XCTest
@testable import LabelCore

final class FinishingProfilePersistenceTests: XCTestCase {
    private let fact = CapabilityFact(state: .supported,
        evidence: .documentedModel(sourceID: "synthetic-finishing-persistence"))
    private func configuration(_ base: PrinterProfile) -> FinishingProfileConfiguration {
        .init(finishing: .init(modes: [.tearOff: fact], enabledModes: [.tearOff],
            installed: .init(cutter: .observed(false, evidence: .reportedInstallation))),
            stock: .init(media: base.media, compatibleModes: [
                .tearOff: .observed(true, evidence: .reportedInstallation),
                .cut: .observed(false, evidence: .reportedInstallation), .peel: .unobserved]),
            schedules: .init(everyLabel: fact, batch: fact, endOfJob: fact, maximumBatchSize: 5))
    }
    private func profile(_ configuration: FinishingProfileConfiguration?, version: Int = 8) throws -> PrinterProfile {
        let base = try PrinterProfile.gc420dUSBReference()
        return try .init(schemaVersion: version, revision: 11, capabilities: base.capabilities,
            installedHardware: base.installedHardware, media: base.media, connection: base.connection,
            finishingConfiguration: configuration)
    }
    func testOfflineFinishingResolutionSharesEffectiveControlValidationAndKeepsOrdinaryGate() throws {
        for method in [ThermalMethod.directThermal, .thermalTransfer] {
            let base = try ThermalControlTestFixture.profile(method: method)
            let configuration = configuration(base)
            let stored = try PrinterProfile(schemaVersion: 8, revision: base.revision,
                capabilities: base.capabilities, installedHardware: base.installedHardware,
                media: base.media, connection: base.connection, configuredDefaults: base.configuredDefaults,
                thermalMedia: base.thermalMedia, finishingConfiguration: configuration)
            let plan = try FinishingJobPlan(mode: .tearOff, outputLabelCount: 2, media: stored.media,
                stock: configuration.stock, finishing: configuration.finishing,
                scheduleQualification: configuration.schedules)
            let job = PrinterControlRequest(thermalMethod: method, finishing: .tearOff,
                printSpeedIps: 3, darkness: 0, mediaGeometry: try .init(originXDot: 0),
                offsets: .init(labelTopDots: 0))
            let workflow = PrinterControlDefaults(darkness: 9,
                mediaGeometry: try .init(originYDot: 1), offsets: .init(shiftLeftDots: 1))
            let legacy = try base.resolveControls(job: job, workflowDefaults: workflow)
            let expected = ResolvedPrinterControls(profileSchemaVersion: 8, profileRevision: legacy.profileRevision,
                thermalMethod: legacy.thermalMethod, finishing: legacy.finishing,
                printSpeedIps: legacy.printSpeedIps, feedSpeedIps: legacy.feedSpeedIps,
                backfeedSpeedIps: legacy.backfeedSpeedIps, darkness: legacy.darkness,
                tracking: legacy.tracking, mediaGeometry: legacy.mediaGeometry, offsets: legacy.offsets)
            let resolved = try stored.resolveFinishingControls(plan: plan, job: job, workflowDefaults: workflow)
            XCTAssertEqual(resolved, expected)
            let normalization = try ZPLControlEncoder().prepareFinishingNormalization(
                profile: stored, plan: plan, job: job, workflowDefaults: workflow)
            XCTAssertEqual(normalization.profile, stored)
            XCTAssertEqual(normalization.plan, plan)
            XCTAssertEqual(normalization.controls, resolved)
            let expectedText = String(decoding: try ZPLControlEncoder().encode(legacy), as: UTF8.self)
                .replacingOccurrences(of: "^MMT\n", with: "")
            XCTAssertEqual(String(decoding: normalization.bytes, as: UTF8.self), expectedText)
            XCTAssertTrue(expectedText.hasPrefix(method == .directThermal ? "^MTD\n" : "^MTT\n"))
            XCTAssertThrowsError(try ZPLControlEncoder(maxOutputBytes: normalization.bytes.count - 1)
                .prepareFinishingNormalization(profile: stored, plan: plan, job: job, workflowDefaults: workflow))
            XCTAssertEqual(resolved.darkness, .value(0))
            XCTAssertThrowsError(try stored.resolveControls(job: job))
            XCTAssertThrowsError(try ZPLControlEncoder().encode(resolved))
            XCTAssertThrowsError(try ZPLPreparedLabelEncoder().encode(
                bitmap: MonochromeBitmap(width: 8, height: 1, bytes: [0]), controls: resolved))
            XCTAssertThrowsError(try stored.resolveFinishingControls(plan: plan, job: .init(finishing: .cut))) {
                XCTAssertEqual($0 as? FinishingControlResolutionError, .modeMismatch)
            }
            let other = method == .directThermal ? ThermalMethod.thermalTransfer : .directThermal
            XCTAssertThrowsError(try stored.resolveFinishingControls(plan: plan,
                job: .init(thermalMethod: other, finishing: .tearOff)))
            XCTAssertThrowsError(try stored.resolveFinishingControls(plan: plan,
                job: .init(finishing: .tearOff, printSpeedIps: 99)))
            XCTAssertThrowsError(try stored.resolveFinishingControls(plan: plan,
                job: .init(finishing: .tearOff, darkness: 31)))
            XCTAssertThrowsError(try stored.resolveFinishingControls(plan: plan,
                job: .init(finishing: .tearOff, tracking: .blackMark)))
            XCTAssertThrowsError(try base.resolveFinishingControls(plan: plan, job: job))
            let changedConfiguration = FinishingProfileConfiguration(finishing: configuration.finishing,
                stock: configuration.stock, schedules: .init(everyLabel: fact, batch: fact,
                    endOfJob: fact, maximumBatchSize: 4))
            let changed = try PrinterProfile(schemaVersion: 8, revision: base.revision + 1,
                capabilities: base.capabilities, installedHardware: base.installedHardware,
                media: base.media, connection: base.connection, configuredDefaults: base.configuredDefaults,
                thermalMedia: base.thermalMedia, finishingConfiguration: changedConfiguration)
            XCTAssertThrowsError(try changed.resolveFinishingControls(plan: plan, job: job)) {
                XCTAssertEqual($0 as? FinishingControlResolutionError, .planMismatch)
            }
        }
    }

    func testEveryQualifiedFinishingModeResolvesWithoutAdmittingMechanicalEncoding() throws {
        let base = try ThermalControlTestFixture.profile(method: .directThermal), c = base.capabilities
        let installation = CapabilityFact(state: .supported, evidence: .reportedInstallation)
        let modes: [FinishingMode] = [.tearOff, .cut, .peel, .rewind]
        let configuration = FinishingProfileConfiguration(finishing: .init(
            modes: Dictionary(uniqueKeysWithValues: modes.map { ($0, fact) }), enabledModes: Set(modes),
            installed: .init(cutter: .observed(true, evidence: .reportedInstallation),
                peeler: .observed(true, evidence: .reportedInstallation),
                rewinder: .observed(true, evidence: .reportedInstallation))),
            stock: .init(media: base.media, compatibleModes: Dictionary(uniqueKeysWithValues: modes.map {
                ($0, .observed(true, evidence: .reportedInstallation))
            })), schedules: .init(everyLabel: fact, batch: fact, endOfJob: fact, maximumBatchSize: 5))
        let profile = try PrinterProfile(schemaVersion: 8, revision: base.revision,
            capabilities: .init(model: "synthetic-finishing-controls", thermalTransfer: c.thermalTransfer,
                cutter: fact, peeler: fact, rewind: fact, tracking: c.tracking,
                printSpeedChoicesIps: c.printSpeedChoicesIps, darkness: c.darkness,
                feedSpeeds: c.feedSpeeds, backfeedSpeeds: c.backfeedSpeeds,
                physicalGeometry: c.physicalGeometry, offsets: c.offsets, directThermal: c.directThermal),
            installedHardware: .init(transport: .usb, selectedFinishing: .tearOff,
                cutter: installation, peeler: installation, observedSpeedIps: nil,
                observedDarkness: nil, observedTracking: nil), media: base.media, connection: base.connection,
            configuredDefaults: base.configuredDefaults, thermalMedia: base.thermalMedia,
            finishingConfiguration: configuration)
        for mode in modes {
            let plan = try FinishingJobPlan(mode: mode, outputLabelCount: 7, media: profile.media,
                stock: configuration.stock, finishing: configuration.finishing,
                schedule: mode == .cut ? .batch(size: 3, cutRemainderAtJobEnd: true) : nil,
                scheduleQualification: configuration.schedules)
            let resolved = try profile.resolveFinishingControls(plan: plan,
                job: .init(finishing: mode, darkness: 0))
            XCTAssertEqual(resolved.finishing, .value(mode))
            let normalization = try ZPLControlEncoder().prepareFinishingNormalization(profile: profile,
                plan: plan, job: .init(finishing: mode, darkness: 0))
            XCTAssertEqual(normalization.controls, resolved)
            let nonRFID = CapabilityFact(state: .unsupported,
                evidence: .documentedModel(sourceID: "synthetic-non-rfid"))
            func wire(model: String = profile.capabilities.model,
                      delayed: CapabilityFact? = nil, readiness: CapabilityFact? = nil,
                      files: Observation<Bool> = .observed(true, evidence: .reportedInstallation),
                      taken: CapabilityFact? = nil, prepeel: CapabilityFact? = nil,
                      rfid: CapabilityFact? = nil, quantity: CapabilityFact? = nil,
                      completion: CapabilityFact? = nil, cutDone: CapabilityFact? = nil,
                      boundProfile: PrinterProfile? = nil) -> FinishingOutputQualification {
                .init(profile: boundProfile ?? profile, model: model, quantityOne: quantity ?? fact, labelCompletion: completion ?? fact, rfid: rfid ?? nonRFID,
                    delayedCutter: delayed ?? fact, delayedCutReadiness: readiness ?? fact, cutCompletion: cutDone ?? fact,
                    completeFileDelivery: files, peelLabelTaken: taken ?? fact, prepeel: prepeel ?? fact)
            }
            let expectedPolicy: FinishingOutputQualification.ModePolicy
            switch mode {
            case .tearOff: expectedPolicy = .tearOff
            case .rewind: expectedPolicy = .rewind
            case .cut: expectedPolicy = .delayedCutSeparateFiles
            case .peel: expectedPolicy = .peelExplicitNoPrepeel
            }
            XCTAssertEqual(try wire().validate(normalization), expectedPolicy)
            XCTAssertThrowsError(try wire(model: "synthetic-other-model").validate(normalization))
            let changedUnitSnapshot = try PrinterProfile(schemaVersion: 8, revision: profile.revision + 1,
                capabilities: profile.capabilities, installedHardware: profile.installedHardware,
                media: profile.media, connection: profile.connection, configuredDefaults: profile.configuredDefaults,
                thermalMedia: profile.thermalMedia, finishingConfiguration: profile.finishingConfiguration)
            XCTAssertEqual(changedUnitSnapshot.capabilities.model, profile.capabilities.model)
            XCTAssertThrowsError(try wire(boundProfile: changedUnitSnapshot).validate(normalization)) {
                XCTAssertEqual($0 as? FinishingOutputQualification.Error, .profileMismatch)
            }
            XCTAssertThrowsError(try wire(rfid: .init(state: .unknown, evidence: .unobserved)).validate(normalization))
            XCTAssertThrowsError(try wire(rfid: fact).validate(normalization)) {
                XCTAssertEqual($0 as? FinishingOutputQualification.Error, .unsupportedRFID)
            }
            let unknown = CapabilityFact(state: .unknown, evidence: .unobserved)
            let reported = CapabilityFact(state: .supported, evidence: .reportedInstallation)
            XCTAssertThrowsError(try wire(quantity: unknown).validate(normalization))
            XCTAssertThrowsError(try wire(completion: unknown).validate(normalization))
            XCTAssertThrowsError(try wire(quantity: reported).validate(normalization))
            XCTAssertThrowsError(try wire(completion: reported).validate(normalization))
            XCTAssertThrowsError(try wire(rfid: .init(state: .unsupported, evidence: .unobserved)).validate(normalization))
            for invalidModel in ["", String(repeating: "x", count: 257), "synthetic\nmodel"] {
                XCTAssertThrowsError(try wire(model: invalidModel).validate(normalization)) {
                    XCTAssertEqual($0 as? FinishingOutputQualification.Error, .invalidModel)
                }
            }
            if mode == .cut {
                XCTAssertThrowsError(try wire(delayed: unknown).validate(normalization))
                XCTAssertThrowsError(try wire(delayed: reported).validate(normalization))
                XCTAssertThrowsError(try wire(readiness: unknown).validate(normalization))
                XCTAssertThrowsError(try wire(cutDone: unknown).validate(normalization))
                XCTAssertThrowsError(try wire(files: .unobserved).validate(normalization)) {
                    XCTAssertEqual($0 as? FinishingOutputQualification.Error, .unverifiedFileBoundaries)
                }
                XCTAssertThrowsError(try wire(files: .observed(false, evidence: .reportedInstallation)).validate(normalization)) {
                    XCTAssertEqual($0 as? FinishingOutputQualification.Error, .absentFileBoundaries)
                }
                XCTAssertThrowsError(try wire(files: .observed(true, evidence: .documentedModel(sourceID: "synthetic-file-model"))).validate(normalization))
            } else if mode == .peel {
                XCTAssertThrowsError(try wire(taken: unknown).validate(normalization))
                XCTAssertThrowsError(try wire(prepeel: unknown).validate(normalization))
                XCTAssertThrowsError(try wire(prepeel: reported).validate(normalization))
                XCTAssertEqual(try wire(prepeel: .init(state: .unsupported,
                    evidence: .documentedModel(sourceID: "synthetic-prepeel-not-applicable")))
                    .validate(normalization), .peelPrepeelNotApplicable)
            } else {
                XCTAssertEqual(try wire(delayed: unknown, readiness: unknown, files: .unobserved,
                    taken: unknown, prepeel: unknown).validate(normalization), expectedPolicy)
            }
            XCTAssertThrowsError(try FinishingOutputQualification(profile: profile, model: profile.capabilities.model).validate(normalization))
            let prefix = String(decoding: normalization.bytes, as: UTF8.self)
            XCTAssertTrue(prefix.hasPrefix("^MTD\n"))
            XCTAssertTrue(prefix.contains("^MD0\n~SD00\n"))
            for forbidden in ["^MM", "^PQ", "~JK", "^XA", "^XZ", "^GF"] {
                XCTAssertFalse(prefix.contains(forbidden))
            }
            XCTAssertEqual(resolved.thermalMethod, .value(.directThermal))
            XCTAssertEqual(resolved.darkness, .value(0))
            XCTAssertEqual(plan.cutAfterOutputLabels, mode == .cut ? [3, 6, 7] : [])
            XCTAssertThrowsError(try profile.resolveFinishingControls(plan: plan,
                job: .init(finishing: mode, darkness: 31)))
            XCTAssertThrowsError(try ZPLControlEncoder().encode(resolved))
            XCTAssertThrowsError(try profile.resolveControls(job: .init(finishing: mode)))
        }
    }

    func testStorageOnlyProfileCannotResolveOrEncodeThroughEitherOrdinaryEntryPath() throws {
        let base = try ThermalControlTestFixture.profile(method: .directThermal)
        let stored = try PrinterProfile(schemaVersion: 8, revision: base.revision,
            capabilities: base.capabilities, installedHardware: base.installedHardware,
            media: base.media, connection: base.connection, configuredDefaults: base.configuredDefaults,
            thermalMedia: base.thermalMedia)
        XCTAssertThrowsError(try stored.resolveControls(job: .init())) {
            XCTAssertEqual($0 as? PrinterProfileError, .invalidProfileVersion)
        }
        let valid = try base.resolveControls(job: .init())
        let forged = ResolvedPrinterControls(profileSchemaVersion: 8, profileRevision: valid.profileRevision,
            thermalMethod: valid.thermalMethod, finishing: valid.finishing, printSpeedIps: valid.printSpeedIps,
            feedSpeedIps: valid.feedSpeedIps, backfeedSpeedIps: valid.backfeedSpeedIps,
            darkness: valid.darkness, tracking: valid.tracking, mediaGeometry: valid.mediaGeometry, offsets: valid.offsets)
        let bitmap = try MonochromeBitmap(width: 8, height: 2, bytes: [0x80, 0x80])
        XCTAssertThrowsError(try ZPLControlEncoder().encode(forged)) {
            XCTAssertEqual($0 as? PrinterProfileError, .invalidProfileVersion)
        }
        XCTAssertThrowsError(try ZPLPreparedLabelEncoder().encode(bitmap: bitmap, controls: forged)) {
            XCTAssertEqual($0 as? PrinterProfileError, .invalidProfileVersion)
        }
        XCTAssertThrowsError(try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: stored)) {
            XCTAssertEqual($0 as? PrinterProfileError, .invalidProfileVersion)
        }
        XCTAssertNoThrow(try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: base))
    }

    func testCanonicalRoundTripPreservesEachDeclarationUnknownAndAbsentValue() throws {
        let base = try PrinterProfile.gc420dUSBReference()
        let original = try profile(configuration(base))
        let bytes = try PrinterProfileJSON.encode(original)
        let restored = try PrinterProfileJSON.decode(bytes)
        XCTAssertEqual(restored, original)
        XCTAssertEqual(try PrinterProfileJSON.encode(restored), bytes)
        XCTAssertEqual(restored.finishingConfiguration?.stock.compatibleModes[.peel], .unobserved)
        XCTAssertNil(restored.finishingConfiguration?.stock.compatibleModes[.rewind])
        XCTAssertEqual(restored.finishingConfiguration?.schedules.maximumBatchSize, 5)
        XCTAssertThrowsError(try restored.validate(.init(finishing: .cut)))
        XCTAssertThrowsError(try profile(configuration(base), version: 7))
        let legacy = try PrinterProfileJSON.encode(base)
        XCTAssertEqual(try PrinterProfileJSON.encode(PrinterProfileJSON.decode(legacy)), legacy)
        XCTAssertNil(try PrinterProfileJSON.decode(legacy).finishingConfiguration)
        XCTAssertEqual(try PrinterProfileJSON.decode(PrinterProfileJSON.encode(profile(nil))), try profile(nil))
    }
    func testModelInventoryStockAndBatchDeclarationsCannotContradictBoundProfile() throws {
        let base = try PrinterProfile.gc420dUSBReference(), good = configuration(base)
        let changed = MediaConfiguration(form: .observed(.continuous, evidence: .reportedInstallation),
            nominalLabelFace: .unobserved, configuredTracking: .unobserved, calibration: .unobserved)
        XCTAssertThrowsError(try profile(.init(finishing: good.finishing,
            stock: .init(media: changed, compatibleModes: good.stock.compatibleModes))))
        XCTAssertThrowsError(try profile(.init(finishing: .init(modes: [.cut: fact]), stock: good.stock)))
        XCTAssertThrowsError(try profile(.init(finishing: .init(installed: .init(
            cutter: .observed(true, evidence: .reportedInstallation))), stock: good.stock)))
        XCTAssertThrowsError(try profile(.init(finishing: good.finishing,
            stock: .init(media: base.media, compatibleModes: [.tearOff: .unobserved]))))
        XCTAssertThrowsError(try profile(.init(finishing: good.finishing, stock: good.stock,
            schedules: .init(batch: fact))))
    }
    func testStrictKeysBooleanTypesEnabledSetAndRequiredVersionFields() throws {
        let base = try PrinterProfile.gc420dUSBReference()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:
            PrinterProfileJSON.encode(profile(configuration(base)))) as? [String: Any])
        for bad in [0 as Any, 1 as Any, "true" as Any, NSNull()] {
            var changed = root
            var config = try XCTUnwrap(changed["finishingConfiguration"] as? [String: Any])
            var installed = try XCTUnwrap(config["installed"] as? [String: Any])
            var cutter = try XCTUnwrap(installed["cutter"] as? [String: Any]); cutter["value"] = bad
            installed["cutter"] = cutter; config["installed"] = installed; changed["finishingConfiguration"] = config
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
        for bad in [0 as Any, 1 as Any, "true" as Any, NSNull()] {
            var changed = root
            var config = try XCTUnwrap(changed["finishingConfiguration"] as? [String: Any])
            var stock = try XCTUnwrap(config["stock"] as? [String: Any])
            var modes = try XCTUnwrap(stock["compatibleModes"] as? [String: Any])
            var tear = try XCTUnwrap(modes["tearOff"] as? [String: Any]); tear["value"] = bad
            modes["tearOff"] = tear; stock["compatibleModes"] = modes
            config["stock"] = stock; changed["finishingConfiguration"] = config
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
        for enabled in [["tearOff", "tearOff"], ["raw"], ["tearOff", "cut"]] {
            var changed = root, config = try XCTUnwrap(root["finishingConfiguration"] as? [String: Any])
            config["enabledModes"] = enabled; changed["finishingConfiguration"] = config
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
        var changed = root; changed.removeValue(forKey: "finishingConfiguration")
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        changed = root; changed["schemaVersion"] = 7
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        changed = root; changed["schemaVersion"] = 9
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        changed = root
        var config = try XCTUnwrap(root["finishingConfiguration"] as? [String: Any]); config["rawCommand"] = "synthetic"
        changed["finishingConfiguration"] = config
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
    }
}
