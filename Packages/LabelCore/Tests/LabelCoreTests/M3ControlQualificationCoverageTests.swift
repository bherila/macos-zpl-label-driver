import Foundation
import XCTest
@testable import LabelCore

/// Closes the M3-AC01 and M3-AC02 clauses that a mutation sweep of the control
/// qualification sources found unguarded by any existing test.
///
/// Every assertion names the exact error. The gaps found were not guards whose
/// removal let an invalid request succeed outright; they were guards whose
/// removal left a *later* guard to throw a different error, so an assertion
/// that only demands "some error" cannot see them. A supported-looking fact
/// with no evidence, an unknown fact that carries real model documentation, and
/// a declaration stored before its schema version all have to be refused as
/// themselves, not as whatever the next check happens to say.
///
/// Nothing here observes a device. All facts are synthetic fixtures.
final class M3ControlQualificationCoverageTests: XCTestCase {
    private let documented = CapabilityFact(state: .supported,
        evidence: .documentedModel(sourceID: "synthetic-m3-coverage-fixture"))
    private let documentedUnsupported = CapabilityFact(state: .unsupported,
        evidence: .documentedModel(sourceID: "synthetic-m3-coverage-fixture"))
    private let documentedUnknown = CapabilityFact(state: .unknown,
        evidence: .documentedModel(sourceID: "synthetic-m3-coverage-fixture"))

    // MARK: - Profile-layer tracking qualification (M3-AC01)

    /// A profile whose gap-tracking fact is the only thing that varies; `nil`
    /// leaves the mode out of the table entirely, which is the *absent* case
    /// rather than an unknown one. The reference GC420d profile is schema 1, so
    /// its tracking request is refused by the schema clause long before the
    /// capability clauses are reached; these need a schema that admits tracking
    /// at all.
    private func trackingProfile(_ gap: CapabilityFact?, version: Int = 6) throws -> PrinterProfile {
        let base = try PrinterProfile.gc420dUSBReference(revision: 3)
        let capabilities = base.capabilities
        var tracking: [MediaTracking: CapabilityFact] =
            [.blackMark: documented, .continuous: documented]
        tracking[.gap] = gap
        return try PrinterProfile(
            schemaVersion: version, revision: 3,
            capabilities: .init(
                model: "synthetic-m3-tracking-profile",
                thermalTransfer: capabilities.thermalTransfer, cutter: capabilities.cutter,
                peeler: capabilities.peeler, rewind: capabilities.rewind,
                tracking: tracking,
                printSpeedChoicesIps: capabilities.printSpeedChoicesIps,
                darkness: capabilities.darkness),
            installedHardware: base.installedHardware, media: base.media,
            connection: base.connection)
    }

    /// `PrinterProfileError.unavailableTracking` carries the tracking *kind*
    /// and not the capability state, so the refusal alone cannot show that
    /// unsupported, unknown, unevidenced-supported and absent stayed four
    /// things. Distinctness is therefore asserted where it is observable: on
    /// the facts the constructed profile retains. Both halves matter — a
    /// refusal that erased the states, or retained states behind a resolver
    /// that accepted them, would each fail this test.
    func testTrackingStateAndEvidenceAreSeparateRequirementsAtTheProfileLayer() throws {
        XCTAssertEqual(try trackingProfile(documented)
            .resolveControls(job: .init(tracking: .gap)).tracking, .value(.gap))

        let unevidenced = CapabilityFact(state: .supported, evidence: .unobserved)
        let refusable = [documentedUnsupported, documentedUnknown, unevidenced]

        // Nothing normalises one refusable fact into another on the way into
        // the profile: three inputs, three retained states, and the third is
        // told apart from a supported one by its evidence alone.
        let retained = try refusable.map {
            try XCTUnwrap(trackingProfile($0).capabilities.tracking[.gap])
        }
        XCTAssertEqual(retained, refusable)
        XCTAssertEqual(retained.map(\.state), [.unsupported, .unknown, .supported])
        XCTAssertEqual(Set(retained.map(\.state)).count, 3)
        XCTAssertEqual(retained[2].state, documented.state)
        XCTAssertNotEqual(retained[2].evidence, documented.evidence)

        // And none of the three authorises the control.
        for fact in refusable {
            XCTAssertThrowsError(try trackingProfile(fact)
                .resolveControls(job: .init(tracking: .gap))) {
                XCTAssertEqual($0 as? PrinterProfileError, .unavailableTracking(.gap))
            }
        }

        // Absent is a fourth thing: no entry at all, which is observably not a
        // stored unknown, and is refused rather than defaulted.
        let absent = try trackingProfile(nil)
        XCTAssertNil(absent.capabilities.tracking[.gap])
        XCTAssertNotEqual(absent.capabilities.tracking[.gap], documentedUnknown)
        XCTAssertThrowsError(try absent.resolveControls(job: .init(tracking: .gap))) {
            XCTAssertEqual($0 as? PrinterProfileError, .unavailableTracking(.gap))
        }
    }

    func testProfileLayerRequiresALengthWithContinuousAndAnOffsetWithBlackMark() throws {
        let profile = try trackingProfile(documented)
        XCTAssertThrowsError(try profile.resolveControls(job: .init(tracking: .continuous))) {
            XCTAssertEqual($0 as? PhysicalGeometryQualification.Error, .continuousLengthRequired)
        }
        XCTAssertThrowsError(try profile.resolveControls(job: .init(tracking: .blackMark))) {
            XCTAssertEqual($0 as? OffsetControlQualification.Error, .blackMarkOffsetRequired)
        }
    }

    // MARK: - Settings validation (M3-AC02)

    func testAnOffsetRequestBelowSchemaSixFailsAsAVersionErrorNotAnUnknownRange() throws {
        let profile = try trackingProfile(documented, version: 5)
        XCTAssertThrowsError(try profile.resolveControls(job: .init(offsets: .init(shiftLeftDots: 0)))) {
            XCTAssertEqual($0 as? PrinterProfileError, .invalidProfileVersion)
        }
    }

    func testBackfeedUnavailabilityIsReportedApartFromAnUnsupportedChoice() throws {
        let request = PrinterControlRequest(printSpeedIps: 3, feedSpeedIps: 4, backfeedSpeedIps: 2)
        let feed = QualifiedSpeedChoices(fact: documented, choicesIps: [2, 4])
        for fact in [documentedUnknown, documentedUnsupported,
                     CapabilityFact(state: .unknown, evidence: .unobserved)] {
            let profile = try MotorSpeedTestFixture.profile(
                defaults: .init(), feed: feed,
                backfeed: .init(fact: fact, choicesIps: []))
            XCTAssertThrowsError(try profile.resolveControls(job: request)) {
                XCTAssertEqual($0 as? PrinterProfileError, .unavailableBackfeedSpeed(fact.state))
            }
        }
        // A qualified backfeed capability still refuses a value off its list.
        let qualified = try MotorSpeedTestFixture.profile(
            defaults: .init(), feed: feed, backfeed: .init(fact: documented, choicesIps: [2, 3]))
        XCTAssertThrowsError(try qualified.resolveControls(
            job: .init(printSpeedIps: 3, feedSpeedIps: 4, backfeedSpeedIps: 4))) {
            XCTAssertEqual($0 as? PrinterProfileError, .unsupportedBackfeedSpeed(4))
        }
    }

    func testFinishingOutputLimitDeclarationIsCheckedApartFromTheEmittedBudget() throws {
        let policy = FinishingControlQualification(modes: [.tearOff: documented], enabledModes: [.tearOff])
        XCTAssertEqual(try policy.encodeMode(.tearOff), Data("^MMT\n".utf8))
        for limit in [0, -1, Int.min, 64 * 1024 + 1, Int.max] {
            XCTAssertThrowsError(try policy.encodeMode(.tearOff, maximumOutputBytes: limit)) {
                XCTAssertEqual($0 as? FinishingControlQualification.Error, .invalidOutputLimit)
            }
        }
        // A limit inside the declared bound is a budget, and reports as one.
        XCTAssertThrowsError(try policy.encodeMode(.tearOff, maximumOutputBytes: 4)) {
            XCTAssertEqual($0 as? FinishingControlQualification.Error, .outputLimit)
        }
    }

    func testQualificationDeclarationsCannotBeStoredBeforeTheirSchemaVersion() throws {
        let base = try PrinterProfile.gc420dUSBReference(revision: 2)
        let capabilities = base.capabilities
        let geometry = PhysicalGeometryQualification(width: .init(fact: documented, maximumDots: 832))
        let offsets = OffsetControlQualification(shiftLeft: .init(fact: documented, range: -30...40))
        // Both declarations are individually well formed; only the version gate
        // stands between them and a profile that has no business holding them.
        XCTAssertNoThrow(try geometry.validateDeclaration())
        XCTAssertNoThrow(try offsets.validateDeclaration())

        func profile(version: Int, geometry: PhysicalGeometryQualification = .unverified,
                     offsets: OffsetControlQualification = .unverified) throws -> PrinterProfile {
            try PrinterProfile(
                schemaVersion: version, revision: 2,
                capabilities: .init(
                    model: "synthetic-m3-schema-gate", thermalTransfer: capabilities.thermalTransfer,
                    cutter: capabilities.cutter, peeler: capabilities.peeler,
                    rewind: capabilities.rewind, tracking: capabilities.tracking,
                    printSpeedChoicesIps: capabilities.printSpeedChoicesIps,
                    darkness: capabilities.darkness,
                    physicalGeometry: geometry, offsets: offsets),
                installedHardware: base.installedHardware, media: base.media,
                connection: base.connection)
        }

        XCTAssertThrowsError(try profile(version: 4, geometry: geometry)) {
            XCTAssertEqual($0 as? PrinterProfileError, .invalidProfileVersion)
        }
        XCTAssertNoThrow(try profile(version: 5, geometry: geometry))
        XCTAssertThrowsError(try profile(version: 5, offsets: offsets)) {
            XCTAssertEqual($0 as? PrinterProfileError, .invalidProfileVersion)
        }
        XCTAssertNoThrow(try profile(version: 6, geometry: geometry, offsets: offsets))
    }

    // MARK: - Wire-boundary finishing facts (M3-AC01)

    private struct FinishingFixture {
        let profile: PrinterProfile
        let normalization: FinishingControlNormalization
    }

    private func finishingFixture(mode: FinishingMode) throws -> FinishingFixture {
        let base = try ThermalControlTestFixture.profile(method: .directThermal)
        let capabilities = base.capabilities
        let installation = CapabilityFact(state: .supported, evidence: .reportedInstallation)
        let modes: [FinishingMode] = [.tearOff, .cut, .peel, .rewind]
        let configuration = FinishingProfileConfiguration(
            finishing: .init(
                modes: Dictionary(uniqueKeysWithValues: modes.map { ($0, documented) }),
                enabledModes: Set(modes),
                installed: .init(cutter: .observed(true, evidence: .reportedInstallation),
                                 peeler: .observed(true, evidence: .reportedInstallation),
                                 rewinder: .observed(true, evidence: .reportedInstallation))),
            stock: .init(media: base.media,
                compatibleModes: Dictionary(uniqueKeysWithValues: modes.map {
                    ($0, Observation<Bool>.observed(true, evidence: .reportedInstallation))
                })),
            schedules: .init(everyLabel: documented, batch: documented,
                             endOfJob: documented, maximumBatchSize: 5))
        let profile = try PrinterProfile(
            schemaVersion: 8, revision: base.revision,
            capabilities: .init(
                model: "synthetic-m3-coverage-finishing",
                thermalTransfer: capabilities.thermalTransfer, cutter: documented,
                peeler: documented, rewind: documented, tracking: capabilities.tracking,
                printSpeedChoicesIps: capabilities.printSpeedChoicesIps,
                darkness: capabilities.darkness, feedSpeeds: capabilities.feedSpeeds,
                backfeedSpeeds: capabilities.backfeedSpeeds,
                physicalGeometry: capabilities.physicalGeometry, offsets: capabilities.offsets,
                directThermal: capabilities.directThermal),
            installedHardware: .init(transport: .usb, selectedFinishing: .tearOff,
                cutter: installation, peeler: installation, observedSpeedIps: nil,
                observedDarkness: nil, observedTracking: nil),
            media: base.media, connection: base.connection,
            configuredDefaults: base.configuredDefaults, thermalMedia: base.thermalMedia,
            finishingConfiguration: configuration)
        let plan = try FinishingJobPlan(
            mode: mode, outputLabelCount: 7, media: profile.media, stock: configuration.stock,
            finishing: configuration.finishing,
            schedule: mode == .cut ? .batch(size: 3, cutRemainderAtJobEnd: true) : nil,
            scheduleQualification: configuration.schedules)
        let normalization = try ZPLControlEncoder().prepareFinishingNormalization(
            profile: profile, plan: plan, job: .init(finishing: mode, darkness: 0))
        return .init(profile: profile, normalization: normalization)
    }

    private func wire(_ fixture: FinishingFixture,
                      quantity: CapabilityFact? = nil, completion: CapabilityFact? = nil,
                      rfid: CapabilityFact? = nil, delayed: CapabilityFact? = nil,
                      readiness: CapabilityFact? = nil, cutDone: CapabilityFact? = nil,
                      taken: CapabilityFact? = nil, prepeel: CapabilityFact? = nil)
        -> FinishingOutputQualification {
        let nonRFID = CapabilityFact(state: .unsupported,
            evidence: .documentedModel(sourceID: "synthetic-m3-coverage-non-rfid"))
        return .init(profile: fixture.profile, model: fixture.profile.capabilities.model,
            quantityOne: quantity ?? documented, labelCompletion: completion ?? documented,
            rfid: rfid ?? nonRFID, delayedCutter: delayed ?? documented,
            delayedCutReadiness: readiness ?? documented, cutCompletion: cutDone ?? documented,
            completeFileDelivery: .observed(true, evidence: .reportedInstallation),
            peelLabelTaken: taken ?? documented, prepeel: prepeel ?? documented)
    }

    func testADocumentedUnknownWireFactIsRefusedRatherThanReadAsAbsent() throws {
        let cut = try finishingFixture(mode: .cut)
        XCTAssertEqual(try wire(cut).validate(cut.normalization), .delayedCutSeparateFiles)
        // Documentation that says nothing about RFID is not documentation that
        // says the printer has none.
        XCTAssertThrowsError(try wire(cut, rfid: documentedUnknown).validate(cut.normalization)) {
            XCTAssertEqual($0 as? FinishingOutputQualification.Error, .unavailable(.rfid, .unknown))
        }

        let peel = try finishingFixture(mode: .peel)
        XCTAssertEqual(try wire(peel).validate(peel.normalization), .peelExplicitNoPrepeel)
        // Unknown prepeel must not resolve to "prepeel not applicable", which is
        // a positive claim about the mechanism.
        XCTAssertThrowsError(try wire(peel, prepeel: documentedUnknown).validate(peel.normalization)) {
            XCTAssertEqual($0 as? FinishingOutputQualification.Error, .unavailable(.prepeel, .unknown))
        }
    }

    func testDocumentedUnsupportedWireFactsAreRefusedComponentByComponent() throws {
        let cut = try finishingFixture(mode: .cut)
        let cutCases: [(FinishingOutputQualification, FinishingOutputQualification.Component)] = [
            (wire(cut, quantity: documentedUnsupported), .quantityOne),
            (wire(cut, completion: documentedUnsupported), .labelCompletion),
            (wire(cut, delayed: documentedUnsupported), .delayedCutter),
            (wire(cut, readiness: documentedUnsupported), .delayedCutReadiness),
            (wire(cut, cutDone: documentedUnsupported), .cutCompletion),
        ]
        for (qualification, component) in cutCases {
            XCTAssertThrowsError(try qualification.validate(cut.normalization)) {
                XCTAssertEqual($0 as? FinishingOutputQualification.Error,
                               .unavailable(component, .unsupported))
            }
        }

        let peel = try finishingFixture(mode: .peel)
        XCTAssertThrowsError(try wire(peel, taken: documentedUnsupported).validate(peel.normalization)) {
            XCTAssertEqual($0 as? FinishingOutputQualification.Error,
                           .unavailable(.peelLabelTaken, .unsupported))
        }
    }
}
