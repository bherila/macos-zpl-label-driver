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
}
