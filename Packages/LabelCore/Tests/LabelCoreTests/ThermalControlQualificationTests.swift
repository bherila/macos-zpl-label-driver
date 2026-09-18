import Foundation
import XCTest
@testable import LabelCore

final class ThermalControlQualificationTests: XCTestCase {
    private let supported = CapabilityFact(state: .supported,
        evidence: .documentedModel(sourceID: "synthetic-thermal-fixture"))
    private var policy: ThermalControlQualification {
        .init(directThermal: supported, thermalTransfer: supported)
    }

    func testEachMethodNeedsCompatibleObservedMediaAndRibbonAndProducesExactBytes() throws {
        for method in [ThermalMethod.directThermal, .thermalTransfer] {
            let bytes = try ZPLDocumentedControlEncoder().encodeThermalMethod(method, policy: policy,
                media: .observed(method, evidence: .reportedInstallation),
                ribbonPresent: .observed(method == .thermalTransfer, evidence: .reportedInstallation))
            XCTAssertEqual(bytes, Data((method == .directThermal ? "^MTD\n" : "^MTT\n").utf8))
            XCTAssertThrowsError(try policy.control(for: method,
                media: .observed(method, evidence: .reportedInstallation),
                ribbonPresent: .observed(method != .thermalTransfer, evidence: .reportedInstallation)))
            XCTAssertThrowsError(try policy.control(for: method,
                media: .observed(method == .directThermal ? .thermalTransfer : .directThermal,
                                 evidence: .reportedInstallation),
                ribbonPresent: .observed(method == .thermalTransfer, evidence: .reportedInstallation)))
        }
    }

    func testDocumentationCannotStandInForLoadedConfigurationAndUnknownIsNotFalse() throws {
        for method in [ThermalMethod.directThermal, .thermalTransfer] {
            let goodMedia = Observation<ThermalMethod>.observed(method, evidence: .reportedInstallation)
            let goodRibbon = Observation<Bool>.observed(method == .thermalTransfer, evidence: .reportedInstallation)
            for media in [Observation<ThermalMethod>.unobserved,
                .observed(method, evidence: .unobserved),
                .observed(method, evidence: .documentedModel(sourceID: "synthetic-thermal-fixture"))] {
                XCTAssertThrowsError(try policy.control(for: method, media: media, ribbonPresent: goodRibbon))
            }
            for ribbon in [Observation<Bool>.unobserved,
                .observed(method == .thermalTransfer, evidence: .unobserved),
                .observed(method == .thermalTransfer,
                          evidence: .documentedModel(sourceID: "synthetic-thermal-fixture"))] {
                XCTAssertThrowsError(try policy.control(for: method, media: goodMedia, ribbonPresent: ribbon))
            }
        }
    }

    func testEachModelFactIsIndependentAndCannotUseUnobservedSupport() throws {
        for method in [ThermalMethod.directThermal, .thermalTransfer] {
            for fact in [CapabilityFact(state: .unknown, evidence: .unobserved),
                         .init(state: .unsupported, evidence: supported.evidence),
                         .init(state: .supported, evidence: .unobserved)] {
                let restricted = ThermalControlQualification(
                    directThermal: method == .directThermal ? fact : supported,
                    thermalTransfer: method == .thermalTransfer ? fact : supported)
                XCTAssertThrowsError(try restricted.control(for: method,
                    media: .observed(method, evidence: .reportedInstallation),
                    ribbonPresent: .observed(method == .thermalTransfer, evidence: .reportedInstallation)))
            }
        }
    }

    func testOutputCapAndReferenceThermalTransferRestrictionRemain() throws {
        XCTAssertThrowsError(try ZPLDocumentedControlEncoder(maximumOutputBytes: 4).encodeThermalMethod(
            .thermalTransfer, policy: policy, media: .observed(.thermalTransfer, evidence: .reportedInstallation),
            ribbonPresent: .observed(true, evidence: .reportedInstallation)))
        XCTAssertThrowsError(try PrinterProfile.gc420dUSBReference().validate(.init(thermalMethod: .thermalTransfer)))
    }
}
