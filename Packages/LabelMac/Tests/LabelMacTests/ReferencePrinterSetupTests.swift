import XCTest
import LabelCore
@testable import LabelMac

@MainActor
final class ReferencePrinterSetupTests: XCTestCase {
    func testReferenceSetupNeverTreatsReportedUSBAsDiscoveredDevice() throws {
        let model = try ReferencePrinterSetupModel.gc420dUSB()
        XCTAssertTrue(model.canEditOfflineWorkflows)
        XCTAssertFalse(model.stockLoadedConfirmed)
        XCTAssertFalse(model.tearOffConfirmed)
        XCTAssertFalse(model.canInstallQueue)
        model.stockLoadedConfirmed = true
        model.tearOffConfirmed = true
        XCTAssertTrue(model.canEditOfflineWorkflows)
        XCTAssertFalse(model.canInstallQueue)
        XCTAssertEqual(
            model.facts.first(where: { $0.id == "transport" })?.status,
            .unknown
        )
    }

    func testOnlyQualifiedSpeedChoicesCanBecomeWorkflowDefaults() throws {
        let model = try ReferencePrinterSetupModel.gc420dUSB()
        XCTAssertEqual(model.speedChoices, [2, 3, 4])
        XCTAssertNil(try model.workflowDefaults().printSpeedIps)
        for speed in model.speedChoices {
            try model.selectSpeed(speed)
            XCTAssertEqual(try model.workflowDefaults().printSpeedIps, speed)
        }
        XCTAssertThrowsError(try model.selectSpeed(5)) {
            XCTAssertEqual($0 as? ReferencePrinterSetupModel.Error, .unsupportedSpeed(5))
        }
        XCTAssertEqual(model.selectedSpeedIps, 4)
    }

    func testOfflineEditingNeverReplacesPhysicalReadinessRequirements() throws {
        let reference = try PrinterProfile.gc420dUSBReference()
        let fixture = try PrinterProfile(schemaVersion: reference.schemaVersion,
            revision: reference.revision, capabilities: reference.capabilities,
            installedHardware: reference.installedHardware, media: reference.media,
            connection: ConnectionConfiguration(transport: .usb,
                stableIdentity: .observed(StableConnectionIdentity(opaqueValue: "synthetic-device"),
                    evidence: .reportedInstallation)))
        let model = ReferencePrinterSetupModel(profile: fixture)
        for stock in [false, true] {
            for tearOff in [false, true] {
                model.stockLoadedConfirmed = stock
                model.tearOffConfirmed = tearOff
                XCTAssertTrue(model.canEditOfflineWorkflows)
                XCTAssertEqual(model.canInstallQueue, stock && tearOff)
                XCTAssertEqual(model.stockLoadedConfirmed, stock)
                XCTAssertEqual(model.tearOffConfirmed, tearOff)
            }
        }
    }

    func testUnsupportedAndUnknownFeaturesAreNotPresentedAsSupported() throws {
        let model = try ReferencePrinterSetupModel.gc420dUSB()
        let facts = Dictionary(uniqueKeysWithValues: model.facts.map { ($0.id, $0) })
        XCTAssertEqual(facts["cutter"]?.status, .unavailable)
        XCTAssertEqual(facts["peeler"]?.status, .unknown)
        XCTAssertEqual(facts["darkness"]?.status, .unknown)
        XCTAssertEqual(facts["tracking"]?.status, .unknown)
        XCTAssertFalse(model.facts.map(\.value).joined().contains("StableConnectionIdentity"))
    }

    func testReferenceSetupViewCanBeConstructed() throws {
        _ = ReferencePrinterSetupView(model: try .gc420dUSB())
    }
    private func configuredMotorProfile() throws -> PrinterProfile {
        let b = try PrinterProfile.gc420dUSBReference()
        let c = b.capabilities
        let fact = CapabilityFact(state: .supported, evidence: .documentedModel(sourceID: "synthetic-speed-fixture"))
        return try PrinterProfile(schemaVersion: 3, revision: 2,
            capabilities: PrinterCapabilities(model: "synthetic-qualified-speed-profile",
                thermalTransfer: c.thermalTransfer, cutter: c.cutter, peeler: c.peeler,
                rewind: c.rewind, tracking: c.tracking, printSpeedChoicesIps: c.printSpeedChoicesIps,
                darkness: c.darkness, feedSpeeds: .init(fact: fact, choicesIps: [2, 4]),
                backfeedSpeeds: .init(fact: fact, choicesIps: [2, 3])),
            installedHardware: b.installedHardware, media: b.media, connection: b.connection,
            configuredDefaults: .init(printSpeedIps: 3, feedSpeedIps: 4, backfeedSpeedIps: 2))
    }

    func testConfiguredMotorDefaultsSurviveSetupEditing() throws {
        let model = ReferencePrinterSetupModel(profile: try configuredMotorProfile())
        XCTAssertEqual(model.selectedSpeedIps, 3)
        let initial = try model.workflowDefaults()
        XCTAssertEqual(initial.printSpeedIps, 3)
        XCTAssertEqual(initial.feedSpeedIps, 4)
        XCTAssertEqual(initial.backfeedSpeedIps, 2)
        try model.selectSpeed(4)
        let edited = try model.workflowDefaults()
        XCTAssertEqual(edited.printSpeedIps, 4)
        XCTAssertEqual(edited.feedSpeedIps, 4)
        XCTAssertEqual(edited.backfeedSpeedIps, 2)
        XCTAssertEqual(model.profile.revision, 2)
        XCTAssertEqual(model.profile.configuredDefaults.printSpeedIps, 3)
    }

    func testUnqualifiedSecondarySpeedsRemainUnavailable() throws {
        let model = try ReferencePrinterSetupModel.gc420dUSB()
        for kind in [ReferencePrinterSetupModel.MotorSpeedKind.feed, .backfeed] {
            XCTAssertEqual(model.speedChoices(for: kind), [])
            XCTAssertNil(model.selectedSpeed(for: kind))
            XCTAssertThrowsError(try model.selectSpeed(4, kind: kind)) {
                XCTAssertEqual($0 as? ReferencePrinterSetupModel.Error,
                               .unavailableMotorSpeed(kind, .unknown))
            }
            XCTAssertNil(model.selectedSpeed(for: kind))
        }
        for id in ["feedSpeed", "backfeedSpeed"] {
            XCTAssertEqual(model.facts.first { $0.id == id }?.status, .unknown)
        }
    }

    func testMotorChoicesAreIndependentAndNilUsesConfiguredFallback() throws {
        let model = ReferencePrinterSetupModel(profile: try configuredMotorProfile())
        try model.selectSpeed(2, kind: .feed)
        try model.selectSpeed(3, kind: .backfeed)
        XCTAssertEqual(try model.workflowDefaults().feedSpeedIps, 2)
        XCTAssertEqual(try model.workflowDefaults().backfeedSpeedIps, 3)
        XCTAssertThrowsError(try model.selectSpeed(3, kind: .feed)) {
            XCTAssertEqual($0 as? ReferencePrinterSetupModel.Error, .unsupportedMotorSpeed(.feed, 3))
        }
        XCTAssertThrowsError(try model.selectSpeed(4, kind: .backfeed)) {
            XCTAssertEqual($0 as? ReferencePrinterSetupModel.Error, .unsupportedMotorSpeed(.backfeed, 4))
        }
        XCTAssertEqual(model.selectedSpeed(for: .feed), 2)
        XCTAssertEqual(model.selectedSpeed(for: .backfeed), 3)
        for kind in [ReferencePrinterSetupModel.MotorSpeedKind.print, .feed, .backfeed] {
            try model.selectSpeed(nil, kind: kind)
            XCTAssertTrue(model.defaultChoiceLabel(for: kind).contains("configured device default"))
        }
        let fallback = try model.workflowDefaults()
        XCTAssertEqual(fallback.printSpeedIps, 3)
        XCTAssertEqual(fallback.feedSpeedIps, 4)
        XCTAssertEqual(fallback.backfeedSpeedIps, 2)
        XCTAssertNil(model.validationMessage)
    }

    func testIncompleteDraftCannotBecomeInstallationReady() throws {
        let b = try configuredMotorProfile()
        let profile = try PrinterProfile(schemaVersion: 3, revision: b.revision,
            capabilities: b.capabilities, installedHardware: b.installedHardware,
            media: b.media, connection: .init(transport: .usb,
                stableIdentity: .observed(.init(opaqueValue: "synthetic-device"),
                    evidence: .reportedInstallation)))
        let model = ReferencePrinterSetupModel(profile: profile)
        model.stockLoadedConfirmed = true
        model.tearOffConfirmed = true
        XCTAssertTrue(model.canInstallQueue)
        try model.selectSpeed(4, kind: .feed)
        XCTAssertTrue(model.canEditOfflineWorkflows)
        XCTAssertFalse(model.canInstallQueue)
        XCTAssertNotNil(model.validationMessage)
        XCTAssertEqual(model.installationReadinessMessage, model.validationMessage)
        XCTAssertThrowsError(try model.workflowDefaults()) {
            XCTAssertEqual($0 as? PrinterProfileError, .incompleteMotorSpeeds)
        }
        try model.selectSpeed(3)
        try model.selectSpeed(2, kind: .backfeed)
        XCTAssertNil(model.validationMessage)
        XCTAssertTrue(model.canInstallQueue)
        XCTAssertEqual(try model.workflowDefaults().feedSpeedIps, 4)
    }

}
