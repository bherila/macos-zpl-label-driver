import Foundation
import LabelCore
import XCTest
@testable import LabelMac

@MainActor
final class ThermalPrinterSetupTests: XCTestCase {
    private let fact = CapabilityFact(state: .supported,
        evidence: .documentedModel(sourceID: "synthetic-thermal-editor-fixture"))

    private func profile(configured: Bool = true, media: ThermalMediaConfiguration? = nil,
                         transfer: CapabilityFact? = nil) throws -> PrinterProfile {
        let b = try PrinterProfile.gc420dUSBReference()
        let c = b.capabilities
        func limit(_ n: Int) -> QualifiedDotLimit { .init(fact: fact, maximumDots: n) }
        var tracking = c.tracking; tracking[.continuous] = fact
        return try PrinterProfile(schemaVersion: 7, revision: 1,
            capabilities: .init(model: "synthetic-thermal-editor", thermalTransfer: transfer ?? fact,
                cutter: c.cutter, peeler: c.peeler, rewind: c.rewind, tracking: tracking,
                printSpeedChoicesIps: c.printSpeedChoicesIps, darkness: fact,
                feedSpeeds: .init(fact: fact, choicesIps: [2, 4]), backfeedSpeeds: .init(fact: fact, choicesIps: [2, 3]),
                physicalGeometry: .init(width: limit(832), continuousLength: limit(1500), homeX: limit(100), homeY: limit(200)),
                offsets: .init(shiftLeft: .init(fact: fact, range: -30...40), labelTop: .init(fact: fact, range: -5...6)),
                directThermal: fact),
            installedHardware: b.installedHardware, media: b.media, connection: b.connection,
            configuredDefaults: .init(thermalMethod: configured ? .thermalTransfer : nil,
                finishing: .tearOff, printSpeedIps: 3, feedSpeedIps: 4, backfeedSpeedIps: 3, darkness: 0,
                tracking: .continuous, mediaGeometry: MediaGeometryRequest(widthDots: 832, lengthDots: 1300, originXDot: 0, originYDot: 0),
                offsets: .init(shiftLeftDots: 0, labelTopDots: 0)),
            thermalMedia: media ?? .init(method: .observed(.thermalTransfer, evidence: .reportedInstallation),
                ribbonPresent: .observed(true, evidence: .reportedInstallation)))
    }

    func testConfiguredTransferAndAllIndependentDefaultsSurviveUtilityDraft() throws {
        let p = try profile()
        let model = ReferencePrinterSetupModel(profile: p)
        XCTAssertEqual(model.selectedThermalMethod, .thermalTransfer)
        XCTAssertEqual(model.thermalMethodChoices, [.directThermal, .thermalTransfer])
        let controls = try model.workflowDefaults()
        XCTAssertEqual(controls.thermalMethod, .thermalTransfer)
        XCTAssertEqual(controls.feedSpeedIps, 4)
        XCTAssertEqual(controls.backfeedSpeedIps, 3)
        XCTAssertEqual(controls.darkness, 0)
        XCTAssertEqual(controls.mediaGeometry, p.configuredDefaults.mediaGeometry)
        XCTAssertEqual(controls.offsets, .init(shiftLeftDots: 0, labelTopDots: 0))
        XCTAssertNil(model.validationMessage)
        XCTAssertFalse(model.stockLoadedConfirmed)
        XCTAssertFalse(model.tearOffConfirmed)
        XCTAssertFalse(model.canInstallQueue)
        XCTAssertEqual(model.thermalFacts.first(where: { $0.id == "thermal-media" })?.status, .configured)
        XCTAssertTrue(model.thermalFacts.first(where: { $0.id == "thermal-ribbon" })?.value.contains("Present") == true)
        XCTAssertEqual(model.facts.first(where: { $0.id == "stock" })?.status, .unknown)
    }

    func testSupportedButIncompatibleSelectionRemainsDraftAndNeverChangesConsumables() throws {
        let p = try profile()
        let model = ReferencePrinterSetupModel(profile: p)
        try model.selectThermalMethod(.directThermal)
        XCTAssertEqual(model.selectedThermalMethod, .directThermal)
        XCTAssertThrowsError(try model.workflowDefaults())
        XCTAssertTrue(model.validationMessage?.contains("does not match") == true)
        XCTAssertEqual(model.profile.thermalMedia, p.thermalMedia)
        XCTAssertEqual(model.profile.configuredDefaults.thermalMethod, .thermalTransfer)
        try model.selectThermalMethod(nil)
        XCTAssertEqual(try model.workflowDefaults().thermalMethod, .thermalTransfer)
        XCTAssertEqual(model.profile.thermalMedia, p.thermalMedia)
        XCTAssertFalse(model.stockLoadedConfirmed)
    }

    func testUnknownModelSupportCannotBecomeAChoiceOrAnImplicitDefault() throws {
        let p = try profile(configured: false, transfer: .init(state: .unknown, evidence: .unobserved))
        let model = ReferencePrinterSetupModel(profile: p)
        XCTAssertEqual(model.thermalMethodChoices, [.directThermal])
        XCTAssertEqual(model.thermalFacts.first(where: { $0.id == "thermal-transfer-support" })?.status, .unknown)
        XCTAssertThrowsError(try model.selectThermalMethod(.thermalTransfer))
        XCTAssertNil(model.selectedThermalMethod)
        XCTAssertThrowsError(try model.workflowDefaults())
        XCTAssertTrue(model.validationMessage?.contains("Choose a qualified thermal method") == true)
        let legacy = try ReferencePrinterSetupModel.gc420dUSB()
        XCTAssertEqual(legacy.thermalMethodChoices, [.directThermal])
        XCTAssertThrowsError(try legacy.selectThermalMethod(.thermalTransfer))
        XCTAssertEqual(try legacy.workflowDefaults().thermalMethod, .directThermal)
        XCTAssertTrue(legacy.thermalFacts.isEmpty)
    }

    func testUnknownMediaAndRibbonRemainUnknownDespiteChoicesAndConfirmationFlags() throws {
        let unknown = ReferencePrinterSetupModel(profile: try profile(configured: false, media: .unobserved))
        XCTAssertTrue(unknown.thermalFacts.filter { ["thermal-media", "thermal-ribbon"].contains($0.id) }.allSatisfy { $0.status == .unknown })
        try unknown.selectThermalMethod(.thermalTransfer)
        unknown.stockLoadedConfirmed = true; unknown.tearOffConfirmed = true
        XCTAssertThrowsError(try unknown.workflowDefaults())
        XCTAssertTrue(unknown.validationMessage?.contains("installation declaration") == true)
        XCTAssertEqual(unknown.profile.thermalMedia, .unobserved)
        XCTAssertFalse(unknown.canInstallQueue)
        let ribbonUnknown = ReferencePrinterSetupModel(profile: try profile(configured: false, media: .init(
            method: .observed(.thermalTransfer, evidence: .reportedInstallation), ribbonPresent: .unobserved)))
        try ribbonUnknown.selectThermalMethod(.thermalTransfer)
        XCTAssertTrue(ribbonUnknown.validationMessage?.contains("Unknown is not absent") == true)
        XCTAssertEqual(ribbonUnknown.thermalFacts.first(where: { $0.id == "thermal-ribbon" })?.status, .unknown)
    }

    func testTransferSaveRestartAndInvalidSavePreserveImmutableDeclarationsAndDraft() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ThermalEditor-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try PrinterProfileStore(root: root)
        let p = try profile()
        let model = try PrinterDefaultsEditingModel(store: store, profileID: "synthetic-printer", initialProfile: p)
        let first = try model.save()
        XCTAssertEqual(first.schemaVersion, 7)
        let restarted = try PrinterDefaultsEditingModel(store: store, profileID: "synthetic-printer", initialProfile: p)
        XCTAssertEqual(restarted.setup.selectedThermalMethod, .thermalTransfer)
        XCTAssertEqual(restarted.setup.profile.thermalMedia, p.thermalMedia)
        XCTAssertEqual(try restarted.setup.workflowDefaults().darkness, 0)
        let draft = restarted.setup
        try draft.selectThermalMethod(.directThermal)
        XCTAssertThrowsError(try restarted.save())
        XCTAssertTrue(restarted.setup === draft)
        XCTAssertEqual(restarted.currentReference, first)
        XCTAssertEqual(restarted.setup.selectedThermalMethod, .directThermal)
        XCTAssertEqual(try store.savedProfiles(id: "synthetic-printer").count, 1)
        try draft.selectThermalMethod(nil)
        let second = try restarted.save()
        XCTAssertEqual(second.revision, first.revision + 1)
        XCTAssertEqual(try store.load(reference: first).thermalMedia, p.thermalMedia)
        XCTAssertEqual(try store.load(reference: second).thermalMedia, p.thermalMedia)
        XCTAssertEqual(try store.load(reference: second).configuredDefaults.thermalMethod, .thermalTransfer)
    }
}
