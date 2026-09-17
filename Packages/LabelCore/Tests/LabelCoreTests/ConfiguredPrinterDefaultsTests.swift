import Foundation
import XCTest
@testable import LabelCore

final class ConfiguredPrinterDefaultsTests: XCTestCase {
    private func profile(_ defaults: PrinterControlDefaults, version: Int = 2) throws -> PrinterProfile {
        let base = try PrinterProfile.gc420dUSBReference()
        return try PrinterProfile(schemaVersion: version, revision: 2,
            capabilities: base.capabilities, installedHardware: base.installedHardware,
            media: base.media, connection: base.connection, configuredDefaults: defaults)
    }

    func testJobThenWorkflowThenImmutablePrinterPrecedence() throws {
        let printer = try profile(.init(printSpeedIps: 2))
        XCTAssertEqual(try printer.resolveControls(job: .init()).printSpeedIps, .value(2))
        XCTAssertEqual(try printer.resolveControls(job: .init(),
            workflowDefaults: .init(printSpeedIps: 3)).printSpeedIps, .value(3))
        let explicit = try printer.resolveControls(job: .init(printSpeedIps: 4),
            workflowDefaults: .init(printSpeedIps: 3))
        XCTAssertEqual(explicit.printSpeedIps, .value(4))
        XCTAssertEqual(explicit.profileSchemaVersion, 2)
        XCTAssertEqual(String(decoding: try ZPLControlEncoder().encode(explicit), as: UTF8.self),
                       "^MMT\n^PR4\n")
        XCTAssertEqual(try PrinterProfile.gc420dUSBReference().resolveControls(job: .init()).printSpeedIps,
                       .leaveUnchanged)
    }

    func testDefaultsDoNotAuthorizeUnsupportedOrUnqualifiedControls() throws {
        for defaults in [PrinterControlDefaults(printSpeedIps: 5), .init(darkness: 15),
            .init(tracking: .gap), .init(finishing: .cut), .init(thermalMethod: .thermalTransfer),
            .init(mediaGeometry: try MediaGeometryRequest(widthDots: 813))] {
            XCTAssertThrowsError(try profile(defaults))
        }
        XCTAssertThrowsError(try profile(.init(printSpeedIps: 2), version: 1)) {
            XCTAssertEqual($0 as? PrinterProfileError, .invalidProfileVersion)
        }
        let printer = try profile(.init(printSpeedIps: 2))
        XCTAssertThrowsError(try printer.resolveControls(job: .init(printSpeedIps: 5)))
        XCTAssertThrowsError(try printer.resolveControls(job: .init(),
            workflowDefaults: .init(darkness: 15)))
    }

    func testReadOnlyObservationsNeverBecomeConfiguredDefaults() throws {
        let base = try PrinterProfile.gc420dUSBReference()
        let observed = InstalledHardware(transport: .usb, selectedFinishing: .tearOff,
            cutter: base.installedHardware.cutter, peeler: base.installedHardware.peeler,
            observedSpeedIps: 4, observedDarkness: 12, observedTracking: .gap)
        for defaults in [PrinterControlDefaults(), .init(printSpeedIps: 2)] {
            let printer = try PrinterProfile(schemaVersion: 2, revision: 2,
                capabilities: base.capabilities, installedHardware: observed,
                media: base.media, connection: base.connection, configuredDefaults: defaults)
            let resolved = try printer.resolveControls(job: .init())
            XCTAssertEqual(resolved.printSpeedIps, defaults.printSpeedIps.map(ResolvedSetting.value) ?? .leaveUnchanged)
            XCTAssertEqual(resolved.darkness, .leaveUnchanged)
            XCTAssertEqual(resolved.tracking, .leaveUnchanged)
        }
    }

    func testVersionTwoDefaultsRoundTripAndLegacyFieldSetRemainsUnchanged() throws {
        let value = try profile(.init(thermalMethod: .directThermal, finishing: .tearOff, printSpeedIps: 2))
        let bytes = try PrinterProfileJSON.encode(value)
        XCTAssertEqual(try PrinterProfileJSON.decode(bytes), value)
        XCTAssertEqual(try PrinterProfileJSON.encode(PrinterProfileJSON.decode(bytes)), bytes)
        let legacy = try PrinterProfile.gc420dUSBReference()
        let legacyBytes = try PrinterProfileJSON.encode(legacy)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: legacyBytes) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["schemaVersion", "revision", "capabilities", "installedHardware", "media", "connection"])
        XCTAssertEqual(try PrinterProfileJSON.decode(legacyBytes).configuredDefaults, .init())
    }

    func testVersionSpecificDefaultFieldsFailClosed() throws {
        let bytes = try PrinterProfileJSON.encode(profile(.init(printSpeedIps: 2)))
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        root["schemaVersion"] = 1
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: root)))
        root["schemaVersion"] = 7
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: root))) {
            XCTAssertEqual($0 as? PrinterProfileJSONError, .unsupportedSchema)
        }
        root["schemaVersion"] = 2
        root.removeValue(forKey: "configuredDefaults")
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: root)))
        for defaults: [String: Any] in [
            ["thermalMethod": NSNull(), "finishing": NSNull(), "printSpeedIps": true],
            ["thermalMethod": NSNull(), "finishing": NSNull(), "printSpeedIps": 5],
            ["thermalMethod": NSNull(), "finishing": NSNull(), "printSpeedIps": 2, "darkness": 15],
            ["thermalMethod": "thermalTransfer", "finishing": NSNull(), "printSpeedIps": 2],
        ] {
            root["configuredDefaults"] = defaults
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: root)))
        }
    }
}
