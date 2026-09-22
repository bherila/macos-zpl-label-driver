import Foundation
import XCTest
@testable import LabelCore

final class VirtualQueueDefinitionTests: XCTestCase {
    func testExactIntegerIdentityAcrossLargeQueueRevisions() throws {
        let p = try PrinterProfile.gc420dUSBReference(revision: 7)
        for value in [9_007_199_254_740_993, Int.max] {
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: VirtualQueueJSON.encode(queue())) as? [String: Any])
            root["revision"] = value
            let bytes = try JSONSerialization.data(withJSONObject: root, options: .sortedKeys)
            XCTAssertEqual(try VirtualQueueJSON.decode(bytes, validatingAgainst: p).revision, value)
        }
    }

    private let digestA = String(repeating: "a", count: 64)
    private let digestB = String(repeating: "b", count: 64)
    private let deviceDigest = String(repeating: "c", count: 64)

    private func queue(id: String = "shipping-native", speed: Int? = 3) throws -> VirtualQueueDefinition {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 7)
        return try VirtualQueueDefinition(
            id: id,
            revision: 2,
            displayName: "Shipping labels",
            physicalDevice: PhysicalDeviceCoordinationID(sha256: deviceDigest),
            workflowProfile: ImmutableProfileReference(
                id: "native-4x6-local", revision: 4, sha256: digestA
            ),
            printerProfile: ImmutableProfileReference(
                id: "gc420d-usb", revision: 7, sha256: digestB
            ),
            workflowDefaults: PrinterControlRequest(
                thermalMethod: .directThermal, finishing: .tearOff, printSpeedIps: speed
            ),
            validatingAgainst: profile
        )
    }

    func testExactWireFormatRoundTripsImmutableBindings() throws {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 7)
        let original = try queue()
        let encoded = try VirtualQueueJSON.encode(original)
        XCTAssertEqual(
            try VirtualQueueJSON.printerProfileReference(in: encoded),
            original.printerProfile
        )
        XCTAssertEqual(try VirtualQueueJSON.decode(encoded, validatingAgainst: profile), original)
        XCTAssertEqual(original.schedulerQueueName, "label-driver-shipping-native")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), [
            "schemaVersion", "id", "revision", "displayName", "physicalDeviceSHA256",
            "workflowProfile", "printerProfile", "defaults",
        ])
    }

    func testSelectorsDigestsAndPrinterRevisionFailClosed() throws {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 7)
        for id in ["../queue", "Queue", "queue/path", ""] {
            XCTAssertThrowsError(try VirtualQueueDefinition(
                id: id, revision: 1, displayName: "Test",
                physicalDevice: PhysicalDeviceCoordinationID(sha256: deviceDigest),
                workflowProfile: ImmutableProfileReference(id: "workflow", revision: 1, sha256: digestA),
                printerProfile: ImmutableProfileReference(id: "printer", revision: 7, sha256: digestB),
                workflowDefaults: .init(), validatingAgainst: profile
            ))
        }
        XCTAssertThrowsError(try PhysicalDeviceCoordinationID(sha256: "not-a-digest"))
        let stale = try ImmutableProfileReference(id: "printer", revision: 6, sha256: digestB)
        XCTAssertThrowsError(try VirtualQueueDefinition(
            id: "queue", revision: 1, displayName: "Test",
            physicalDevice: PhysicalDeviceCoordinationID(sha256: deviceDigest),
            workflowProfile: ImmutableProfileReference(id: "workflow", revision: 1, sha256: digestA),
            printerProfile: stale, workflowDefaults: .init(), validatingAgainst: profile
        )) { XCTAssertEqual($0 as? VirtualQueueError, .printerProfileMismatch) }
        XCTAssertThrowsError(try VirtualQueueDefinition(
            id: "queue", revision: 1, displayName: "Test",
            physicalDevice: PhysicalDeviceCoordinationID(sha256: deviceDigest),
            workflowProfile: ImmutableProfileReference(id: "workflow", revision: 1, sha256: digestA),
            printerProfile: ImmutableProfileReference(id: "printer", revision: 7, sha256: digestB),
            workflowDefaults: .init(), validatingAgainst: profile
        )) { XCTAssertEqual($0 as? VirtualQueueError, .invalidDefaults) }
    }

    func testUnsupportedDefaultsCannotEnterQueueDefinitionOrJSON() throws {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 7)
        XCTAssertThrowsError(try VirtualQueueDefinition(
            id: "queue", revision: 1, displayName: "Test",
            physicalDevice: PhysicalDeviceCoordinationID(sha256: deviceDigest),
            workflowProfile: ImmutableProfileReference(id: "workflow", revision: 1, sha256: digestA),
            printerProfile: ImmutableProfileReference(id: "printer", revision: 7, sha256: digestB),
            workflowDefaults: .init(darkness: 10), validatingAgainst: profile
        )) {
            XCTAssertEqual($0 as? PrinterProfileError,
                           .controlRequiresSchemaVersion(.darkness, required: 4, profileVersion: 1))
        }

        var object = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: VirtualQueueJSON.encode(try queue())
        ) as? [String: Any])
        var defaults = try XCTUnwrap(object["defaults"] as? [String: Any])
        defaults["printSpeedIps"] = 5
        object["defaults"] = defaults
        let changed = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try VirtualQueueJSON.decode(changed, validatingAgainst: profile))
    }

    func testUnknownFieldsAndEmbeddedPayloadAttemptsAreRejected() throws {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 7)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: VirtualQueueJSON.encode(try queue())
        ) as? [String: Any])
        for (key, value) in [
            ("filterPath", "/tmp/filter"), ("rawCommand", "raw-printer-command"),
            ("document", "private label"),
        ] {
            object[key] = value
            let changed = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try VirtualQueueJSON.decode(changed, validatingAgainst: profile)) {
                XCTAssertEqual($0 as? VirtualQueueJSONError, .unknownField)
            }
            object.removeValue(forKey: key)
        }
    }

    func testCatalogGroupsSeveralWorkflowsUnderOneCoordinationDomain() throws {
        let native = try queue(id: "shipping-native")
        let letter = try queue(id: "shipping-letter", speed: nil)
        let catalog = try VirtualQueueCatalog([native, letter])
        XCTAssertEqual(catalog.targeting(native.physicalDevice).map(\.id), [
            "shipping-native", "shipping-letter",
        ])
        XCTAssertThrowsError(try VirtualQueueCatalog([native, native])) {
            XCTAssertEqual($0 as? VirtualQueueError, .duplicateQueueID("shipping-native"))
        }
    }

    func testWireInputIsBoundedBeforeParsing() throws {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 7)
        XCTAssertThrowsError(try VirtualQueueJSON.decode(
            Data(repeating: 0x20, count: VirtualQueueJSON.maximumBytes + 1),
            validatingAgainst: profile
        )) { XCTAssertEqual($0 as? VirtualQueueJSONError, .inputTooLarge) }
        XCTAssertThrowsError(try VirtualQueueJSON.encode(try queue(), maximumBytes: 1)) {
            XCTAssertEqual($0 as? VirtualQueueJSONError, .outputTooLarge)
        }
    }
}
