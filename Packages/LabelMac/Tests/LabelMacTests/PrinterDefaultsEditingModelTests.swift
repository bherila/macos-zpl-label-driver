import Combine
import Foundation
import LabelCore
import XCTest
@testable import LabelMac

@MainActor
final class PrinterDefaultsEditingModelTests: XCTestCase {
    private func root() -> URL {
        let result = FileManager.default.temporaryDirectory.appending(path: "PrinterDefaultsEditing-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: result) }
        return result
    }

    func testSaveRestartAndHistoricalReopenPreserveEveryImmutableRevision() throws {
        let store = try PrinterProfileStore(root: root())
        let baseline = try PrinterProfile.gc420dUSBReference()
        let model = try PrinterDefaultsEditingModel(store: store, initialProfile: baseline)
        XCTAssertNil(model.currentReference)
        try model.setup.selectSpeed(3)
        let first = try model.save()
        XCTAssertEqual(first.schemaVersion, 2)
        XCTAssertEqual(first.revision, 2)
        XCTAssertEqual(try store.load(reference: first).configuredDefaults.printSpeedIps, 3)
        try model.setup.selectSpeed(4)
        let second = try model.save()
        XCTAssertEqual(second.revision, 3)
        let restarted = try PrinterDefaultsEditingModel(store: store, initialProfile: baseline)
        XCTAssertEqual(restarted.currentReference, second)
        XCTAssertEqual(restarted.setup.selectedSpeedIps, 4)
        try restarted.reopen(first)
        XCTAssertEqual(restarted.setup.selectedSpeedIps, 3)
        try restarted.setup.selectSpeed(2)
        let third = try restarted.save()
        XCTAssertEqual(third.revision, 4)
        XCTAssertEqual(try store.load(reference: first).configuredDefaults.printSpeedIps, 3)
        XCTAssertEqual(try store.load(reference: second).configuredDefaults.printSpeedIps, 4)
        XCTAssertEqual(try store.load(reference: third).configuredDefaults.printSpeedIps, 2)
        XCTAssertEqual(baseline.schemaVersion, 1)
        XCTAssertFalse(restarted.setup.canInstallQueue)
    }

    func testInvalidDraftCannotPublishOrReplaceItsCurrentModel() throws {
        let store = try PrinterProfileStore(root: root())
        let model = try PrinterDefaultsEditingModel(store: store, initialProfile: PrinterProfile.gc420dUSBReference())
        let original = model.setup
        model.setup.offsetDraft[.shiftLeft] = "0"
        XCTAssertThrowsError(try model.save())
        XCTAssertTrue(model.setup === original)
        XCTAssertEqual(model.setup.offsetDraft[.shiftLeft], "0")
        XCTAssertTrue(try store.savedProfiles(id: model.profileID).isEmpty)
        XCTAssertNil(model.currentReference)
    }

    func testRevisionOverflowAndWrongReferenceFailBeforeStateReplacement() throws {
        let store = try PrinterProfileStore(root: root())
        let model = try PrinterDefaultsEditingModel(store: store,
            initialProfile: PrinterProfile.gc420dUSBReference(revision: Int.max))
        XCTAssertThrowsError(try model.save()) {
            XCTAssertEqual($0 as? PrinterDefaultsEditingModel.Error, .revisionOverflow)
        }
        let wrong = try ImmutableProfileReference(id: "another-profile", revision: 1, sha256: String(repeating: "0", count: 64))
        XCTAssertThrowsError(try model.reopen(wrong))
        XCTAssertNil(model.currentReference)
        XCTAssertTrue(try store.savedProfiles(id: model.profileID).isEmpty)
    }

    func testDraftChangesAreObservableByTheContainingSaveControls() throws {
        let store = try PrinterProfileStore(root: root())
        let model = try PrinterDefaultsEditingModel(store: store, initialProfile: PrinterProfile.gc420dUSBReference())
        var changes = 0
        let observation = model.objectWillChange.sink { _ in changes += 1 }
        model.setup.geometryDraft[.width] = "broken"
        XCTAssertGreaterThan(changes, 0)
        XCTAssertNotNil(model.setup.validationMessage)
        model.setup.geometryDraft = [:]
        _ = try model.save()
        let before = changes
        model.setup.offsetDraft[.labelTop] = "broken"
        XCTAssertGreaterThan(changes, before)
        withExtendedLifetime(observation) {}
    }

    func testUncertainPublicationKeepsDraftAndReportsWithoutAutomaticRetry() throws {
        let destination = root()
        let storage = try PrivateImmutableDirectory(root: destination, syncDirectory: { _ in -1 })
        let store = PrinterProfileStore(root: destination, storage: storage)
        let model = try PrinterDefaultsEditingModel(store: store, initialProfile: PrinterProfile.gc420dUSBReference())
        try model.setup.selectSpeed(3)
        let original = model.setup
        do {
            _ = try model.save()
            XCTFail("expected uncertain publication")
        } catch {
            guard case PrinterProfileStore.Error.commitUncertain = error else { return XCTFail("wrong publication outcome") }
            model.report(error)
        }
        XCTAssertTrue(model.setup === original)
        XCTAssertEqual(model.setup.selectedSpeedIps, 3)
        XCTAssertNil(model.currentReference)
        XCTAssertTrue(model.message?.contains("could not be confirmed") == true)
    }
    func testRefreshDoesNotReplaceAnEditedDraftWithAnotherSavedRevision() throws {
        let store = try PrinterProfileStore(root: root())
        let baseline = try PrinterProfile.gc420dUSBReference()
        let first = try PrinterDefaultsEditingModel(store: store, initialProfile: baseline)
        try first.setup.selectSpeed(3)
        let reference = try first.save()
        let other = try PrinterDefaultsEditingModel(store: store, initialProfile: baseline)
        try other.setup.selectSpeed(4)
        let newer = try other.save()
        try first.setup.selectSpeed(2)
        try first.refresh()
        XCTAssertEqual(first.currentReference, reference)
        XCTAssertEqual(first.setup.selectedSpeedIps, 2)
        XCTAssertEqual(first.savedProfiles.first?.reference, newer)
    }

    func testQualifiedSchemasSixAndSevenSaveAndRestartRetainAllIndependentDefaults() throws {
        for version in [6, 7] {
            let b = try PrinterProfile.gc420dUSBReference(revision: 7)
            let c = b.capabilities
            let fact = CapabilityFact(state: .supported, evidence: .documentedModel(sourceID: "synthetic-default-fixture"))
            var tracking = c.tracking; tracking[.continuous] = fact
            func limit(_ value: Int) -> QualifiedDotLimit { .init(fact: fact, maximumDots: value) }
            let profile = try PrinterProfile(schemaVersion: version, revision: 7,
                capabilities: .init(model: c.model, thermalTransfer: c.thermalTransfer, cutter: c.cutter, peeler: c.peeler,
                    rewind: c.rewind, tracking: tracking, printSpeedChoicesIps: c.printSpeedChoicesIps, darkness: fact,
                    feedSpeeds: .init(fact: fact, choicesIps: [2, 4]), backfeedSpeeds: .init(fact: fact, choicesIps: [2, 3]),
                    physicalGeometry: .init(width: limit(832), continuousLength: limit(1500), homeX: limit(100), homeY: limit(200)),
                    offsets: .init(shiftLeft: .init(fact: fact, range: -30...40), labelTop: .init(fact: fact, range: -5...6)),
                    directThermal: version == 7 ? fact : .init(state: .unknown, evidence: .unobserved)),
                installedHardware: b.installedHardware, media: b.media, connection: b.connection,
                configuredDefaults: .init(thermalMethod: version == 7 ? .directThermal : nil, printSpeedIps: 3, feedSpeedIps: 4, backfeedSpeedIps: 3, darkness: 15,
                    tracking: .continuous, mediaGeometry: MediaGeometryRequest(widthDots: 832, lengthDots: 1300, originXDot: 0, originYDot: 0),
                    offsets: .init(shiftLeftDots: 0, labelTopDots: 0)),
                thermalMedia: version == 7 ? .init(method: .observed(.directThermal, evidence: .reportedInstallation),
                    ribbonPresent: .observed(false, evidence: .reportedInstallation)) : .unobserved)
            let store = try PrinterProfileStore(root: root())
            let model = try PrinterDefaultsEditingModel(store: store, profileID: "synthetic-printer", initialProfile: profile)
            try model.setup.selectSpeed(4)
            try model.setup.selectDarkness(0)
            model.setup.geometryDraft[.width] = "813"
            model.setup.offsetDraft[.labelTop] = "1"
            let expected = try model.setup.workflowDefaults()
            let reference = try model.save()
            XCTAssertEqual(reference.schemaVersion, version)
            let saved = try store.load(reference: reference)
            XCTAssertEqual(saved.capabilities, profile.capabilities)
            XCTAssertEqual(saved.media, profile.media)
            XCTAssertEqual(saved.thermalMedia, profile.thermalMedia)
            XCTAssertEqual(saved.connection, profile.connection)
            let restarted = try PrinterDefaultsEditingModel(store: store, profileID: "synthetic-printer", initialProfile: profile)
            XCTAssertEqual(try restarted.setup.workflowDefaults(), expected)
            XCTAssertEqual(saved.configuredDefaults.darkness, 0)
            XCTAssertEqual(saved.configuredDefaults.offsets, .init(shiftLeftDots: 0, labelTopDots: 1))
            XCTAssertEqual(profile.configuredDefaults.darkness, 15)
            XCTAssertEqual(profile.configuredDefaults.offsets?.labelTopDots, 0)
        }
    }

    func testThermalProfileSaveAndStartupPreserveReportedConsumablesAndQualification() throws {
        let baseline = try PrinterProfile.gc420dUSBReference()
        let c = baseline.capabilities
        let fact = CapabilityFact(state: .supported,
            evidence: .documentedModel(sourceID: "synthetic-thermal-fixture"))
        let consumables = ThermalMediaConfiguration(
            method: .observed(.directThermal, evidence: .reportedInstallation),
            ribbonPresent: .observed(false, evidence: .reportedInstallation))
        let profile = try PrinterProfile(schemaVersion: 7, revision: 1,
            capabilities: .init(model: "synthetic-thermal-model", thermalTransfer: c.thermalTransfer,
                cutter: c.cutter, peeler: c.peeler, rewind: c.rewind, tracking: c.tracking,
                printSpeedChoicesIps: c.printSpeedChoicesIps, darkness: c.darkness, directThermal: fact),
            installedHardware: baseline.installedHardware, media: baseline.media, connection: baseline.connection,
            configuredDefaults: .init(thermalMethod: .directThermal, finishing: .tearOff, printSpeedIps: 3),
            thermalMedia: consumables)
        let store = try PrinterProfileStore(root: root())
        let model = try PrinterDefaultsEditingModel(store: store, profileID: "synthetic-printer", initialProfile: profile)
        try model.setup.selectSpeed(4)
        let reference = try model.save()
        XCTAssertEqual(reference.schemaVersion, 7)
        XCTAssertEqual(reference.revision, 2)
        let saved = try store.load(reference: reference)
        XCTAssertEqual(saved.thermalMedia, consumables)
        XCTAssertEqual(saved.capabilities.directThermal, fact)
        XCTAssertEqual(saved.configuredDefaults.printSpeedIps, 4)
        let reopened = try PrinterDefaultsEditingModel(store: store, profileID: "synthetic-printer", initialProfile: baseline)
        XCTAssertEqual(reopened.currentReference, reference)
        XCTAssertEqual(reopened.setup.profile.thermalMedia, consumables)
        XCTAssertEqual(reopened.setup.profile.capabilities, saved.capabilities)
        XCTAssertEqual(profile.revision, 1)
        XCTAssertEqual(profile.configuredDefaults.printSpeedIps, 3)
    }

}
