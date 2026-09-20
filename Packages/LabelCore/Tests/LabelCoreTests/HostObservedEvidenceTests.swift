import XCTest
@testable import LabelCore

/// `CapabilityEvidence.observedByHost` and the provenance boundary it draws.
///
/// Before #131 a fact this Mac read out of the I/O Registry was stored with the
/// same evidence class as a fact a person asserted — "I loaded 4x6 stock".
/// This project separates compiled, simulated, GUI-tested and physically
/// printed precisely so that provenance cannot be flattened, and those two are
/// different strengths of evidence.
///
/// Adding a case is the easy half. The half worth testing is that the new case
/// does not quietly become a *stronger* one: a host observation must not
/// satisfy a guard that exists to require a human declaration.
final class HostObservedEvidenceTests: XCTestCase {
    private let hostObserved = CapabilityEvidence.observedByHost(method: .ioRegistryProperty)

    private struct FixedDigest: StableIdentityDigest {
        let value: String
        func hexDigest(_ bytes: [UInt8]) -> String { value }
    }

    private func hostObservedProfile() throws -> PrinterProfile {
        let qualified = try USBIdentityQualification.qualify(
            vendorID: 0x0A5F, productID: 0x00D1,
            serialNumber: .reported("36J153900185"),
            digest: FixedDigest(value: String(repeating: "a", count: 64)))
        return try PrinterProfile.gc420dUSBReference().adoptingStableIdentity(qualified.identity)
    }

    // MARK: - A host observation is not a human declaration

    /// The load-bearing negative test. `ThermalControlQualification` requires
    /// `reportedInstallation` because only a person can state what is loaded in
    /// the printer right now. A registry read cannot know that, so the new case
    /// must fail those guards exactly as any other non-declaration does.
    func testAHostObservationCannotSatisfyAnInstallationDeclaration() throws {
        let policy = ThermalControlQualification(
            directThermal: CapabilityFact(state: .supported,
                                          evidence: .documentedModel(sourceID: "R26")),
            thermalTransfer: CapabilityFact(state: .unsupported,
                                            evidence: .documentedModel(sourceID: "R26")))

        // Loaded media claimed by host observation: refused.
        XCTAssertThrowsError(try policy.control(
            for: .directThermal,
            media: .observed(.directThermal, evidence: hostObserved),
            ribbonPresent: .observed(false, evidence: .reportedInstallation))) {
            XCTAssertEqual($0 as? ThermalControlQualification.Error, .unverifiedMedia)
        }

        // Ribbon presence claimed by host observation: refused.
        XCTAssertThrowsError(try policy.control(
            for: .directThermal,
            media: .observed(.directThermal, evidence: .reportedInstallation),
            ribbonPresent: .observed(false, evidence: hostObserved))) {
            XCTAssertEqual($0 as? ThermalControlQualification.Error, .unverifiedRibbon)
        }

        // The same call with both declared by a person still succeeds, so the
        // two refusals above are the evidence class being rejected and not
        // something else in the fixture.
        XCTAssertEqual(try policy.control(
            for: .directThermal,
            media: .observed(.directThermal, evidence: .reportedInstallation),
            ribbonPresent: .observed(false, evidence: .reportedInstallation)),
            .thermalMethod(.directThermal))
    }

    /// The four cases are four values. A test that only round-tripped would
    /// pass against an implementation that aliased the new case onto an old one.
    func testTheFourEvidenceCasesAreMutuallyDistinct() {
        let all: [CapabilityEvidence] = [
            .documentedModel(sourceID: "R26"), .reportedInstallation, hostObserved, .unobserved,
        ]
        for (i, a) in all.enumerated() {
            for (j, b) in all.enumerated() where i != j {
                XCTAssertNotEqual(a, b)
            }
        }
        XCTAssertNotEqual(hostObserved, .reportedInstallation)
    }

    // MARK: - The codec

    func testAHostObservedIdentitySurvivesTheProfileCodecWithItsMethod() throws {
        let profile = try hostObservedProfile()
        XCTAssertEqual(profile.connection.stableIdentity.evidenceForTesting, hostObserved)
        let decoded = try PrinterProfileJSON.decode(PrinterProfileJSON.encode(profile))
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.connection.stableIdentity.evidenceForTesting, hostObserved)
    }

    /// The encoded shape matters as much as the round trip. A host observation
    /// has no source document, so it carries `method` and no `sourceID`; the
    /// three pre-existing kinds keep their exact shape, because
    /// `object(_:allowed:)` demands an exact key match and every profile
    /// already written to disk has to keep decoding.
    func testEncodedEvidenceShapesAreExactAndUnchangedForTheOldKinds() throws {
        let encoded = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: PrinterProfileJSON.encode(try hostObservedProfile())) as? [String: Any])
        let connection = try XCTUnwrap(encoded["connection"] as? [String: Any])
        let identity = try XCTUnwrap(connection["stableIdentity"] as? [String: Any])
        let evidence = try XCTUnwrap(identity["evidence"] as? [String: Any])
        XCTAssertEqual(Set(evidence.keys), ["kind", "method"])
        XCTAssertEqual(evidence["kind"] as? String, "observedByHost")
        XCTAssertEqual(evidence["method"] as? String, "ioRegistryProperty")

        // An untouched reference profile still encodes the old shape exactly.
        let plain = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: PrinterProfileJSON.encode(
                    try PrinterProfile.gc420dUSBReference())) as? [String: Any])
        let capabilities = try XCTUnwrap(plain["capabilities"] as? [String: Any])
        let cutter = try XCTUnwrap(capabilities["cutter"] as? [String: Any])
        let cutterEvidence = try XCTUnwrap(cutter["evidence"] as? [String: Any])
        XCTAssertEqual(Set(cutterEvidence.keys), ["kind", "sourceID"])
    }

    /// An unrecognised method is refused rather than defaulted, and a host
    /// observation carrying a `sourceID` is refused rather than tolerated.
    /// Both are the fail-closed direction: an evidence value this build does
    /// not understand must not decode into one it does.
    func testMalformedHostObservationsFailClosed() throws {
        func decodeEvidence(_ evidence: [String: Any]) throws -> PrinterProfile {
            var root = try XCTUnwrap(
                try JSONSerialization.jsonObject(
                    with: PrinterProfileJSON.encode(try hostObservedProfile())) as? [String: Any])
            var connection = try XCTUnwrap(root["connection"] as? [String: Any])
            var identity = try XCTUnwrap(connection["stableIdentity"] as? [String: Any])
            identity["evidence"] = evidence
            connection["stableIdentity"] = identity
            root["connection"] = connection
            return try PrinterProfileJSON.decode(
                try JSONSerialization.data(withJSONObject: root))
        }

        XCTAssertThrowsError(try decodeEvidence(
            ["kind": "observedByHost", "method": "someFutureMethod"])) {
            XCTAssertEqual($0 as? PrinterProfileJSONError, .invalidValue("method"))
        }
        XCTAssertThrowsError(try decodeEvidence(
            ["kind": "observedByHost", "method": "ioRegistryProperty", "sourceID": NSNull()])) {
            XCTAssertEqual($0 as? PrinterProfileJSONError, .unknownField)
        }
        XCTAssertThrowsError(try decodeEvidence(["kind": "observedByHost"])) {
            XCTAssertEqual($0 as? PrinterProfileJSONError, .missingField("method"))
        }
    }

}

private extension Observation {
    /// Reaches the evidence without unwrapping at each call site.
    var evidenceForTesting: CapabilityEvidence? {
        guard case let .observed(_, evidence) = self else { return nil }
        return evidence
    }
}
