import Foundation
import XCTest
@testable import LabelCore

/// Closes the M3-AC01 and M3-AC02 clauses that a mutation sweep of the control
/// qualification sources found unguarded by any existing test.
///
/// Two different things were measured about the twelve gaps, and because they
/// concern *different inputs* they are kept apart here as they are in the
/// record.
///
/// What removing a guard does, for the inputs these tests feed: eight of the
/// twelve let the invalid input succeed outright — a tracking mode authorised
/// from a fact nothing evidenced, a continuous or black-mark mode resolved with
/// no length or offset at all, `peelPrepeelNotApplicable` returned for an
/// unobserved mechanism, a schema-4 profile holding a schema-5 declaration.
/// Three still refuse but with a different error, and one does both depending
/// on the input.
///
/// Why the pre-existing suite stayed quiet, for the inputs *it* fed: three
/// causes, not one. For five guards no test ever supplied anything the guard
/// would refuse, so no assertion of any strength could have caught the removal.
/// For four the input was supplied and only the identity of the error went
/// unchecked, so naming it would have sufficed. For the last two — the
/// profile-layer continuous-length and black-mark-offset guards — the input the
/// suite fed carries a geometry or offsets payload, which makes a policy-type
/// copy of the same rule apply and throw the *identical* error case. There an
/// exact-error assertion would have passed too: assertion strength was not the
/// problem, and only a different input could have exposed the gap. Those two
/// guards are among the eight above, because the payload-free input these tests
/// feed reaches no copy at all. That accounts for eleven; the twelfth, the
/// output-limit bound, falls in two causes at once because its two inputs
/// differ — the zero-limit input was supplied with the error unnamed, and no
/// test ever supplied a limit above the bound.
///
/// So these tests do both things. They name the exact error, because a guard
/// whose removal merely changes the error is invisible to a bare
/// `XCTAssertThrowsError`. And they feed inputs the suite did not have: a
/// supported-looking fact with no evidence, an unknown or unsupported fact that
/// cites real model documentation, a tracking mode selected with no geometry or
/// offset payload to fall back on, a declaration stored before its schema
/// version, and an output limit above its declared bound.
///
/// When this file was first written the tracking refusal could not carry the
/// distinction at all — `unavailableTracking` reported only the tracking kind —
/// so distinctness was asserted on the facts the constructed profile retains
/// instead. That refusal now carries a `CapabilityRefusalReason`, and the
/// schema-version gate it used to absorb is a separate error, so distinctness
/// is asserted on the refusal itself as well as on the retained facts. The
/// retained-fact assertions stay: they catch a profile that normalises one
/// refusable fact into another on the way in, which no refusal could show.
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

    /// A profile whose darkness fact and schema version are the only things
    /// that vary. Darkness is stored as a non-optional fact, so unlike
    /// tracking it has no absent case to distinguish.
    private func darknessProfile(_ darkness: CapabilityFact, version: Int) throws -> PrinterProfile {
        let base = try PrinterProfile.gc420dUSBReference(revision: 3)
        let capabilities = base.capabilities
        return try PrinterProfile(
            schemaVersion: version, revision: 3,
            capabilities: .init(
                model: "synthetic-m3-darkness-profile",
                thermalTransfer: capabilities.thermalTransfer, cutter: capabilities.cutter,
                peeler: capabilities.peeler, rewind: capabilities.rewind,
                tracking: capabilities.tracking,
                printSpeedChoicesIps: capabilities.printSpeedChoicesIps,
                darkness: darkness),
            installedHardware: base.installedHardware, media: base.media,
            connection: base.connection)
    }

    /// Distinctness has two places to live and this test checks both. The
    /// facts the constructed profile retains show that nothing normalises one
    /// refusable fact into another on the way in; the refusal's
    /// `CapabilityRefusalReason` shows that the four are still four on the way
    /// out. Both halves matter — a refusal that erased the states, or retained
    /// states behind a resolver that accepted them, would each fail this test.
    /// The per-reason assertions live in
    /// `testTrackingRefusalNamesWhichCapabilityRecordProducedIt`.
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

        // And none of the three authorises the control, each under its own
        // reason rather than one shared refusal.
        let expected: [CapabilityRefusalReason] = [
            .unsupported(.documentedModel(sourceID: "synthetic-m3-coverage-fixture")),
            .unknown(.documentedModel(sourceID: "synthetic-m3-coverage-fixture")),
            .unobservedSupport,
        ]
        for (fact, reason) in zip(refusable, expected) {
            XCTAssertThrowsError(try trackingProfile(fact)
                .resolveControls(job: .init(tracking: .gap))) {
                XCTAssertEqual($0 as? PrinterProfileError, .unavailableTracking(.gap, reason))
            }
        }

        // Absent is a fourth thing: no entry at all, which is observably not a
        // stored unknown, and is refused rather than defaulted.
        let absent = try trackingProfile(nil)
        XCTAssertNil(absent.capabilities.tracking[.gap])
        XCTAssertNotEqual(absent.capabilities.tracking[.gap], documentedUnknown)
        XCTAssertThrowsError(try absent.resolveControls(job: .init(tracking: .gap))) {
            XCTAssertEqual($0 as? PrinterProfileError, .unavailableTracking(.gap, .absent))
        }
    }

    /// The invariant this closes: *Unknown capability/status is not false,
    /// zero, supported or completed.* Four materially different records used
    /// to produce one indistinguishable refusal, so a setup surface reading
    /// it could only say "unavailable" — and any wording stronger than that,
    /// such as "this printer does not support gap tracking", would have been a
    /// false claim about the device for three of the four.
    ///
    /// Each reason is asserted by name, and every pair is asserted distinct,
    /// so collapsing any two back together fails here rather than passing on
    /// the strength of a bare `XCTAssertThrowsError`.
    func testTrackingRefusalNamesWhichCapabilityRecordProducedIt() throws {
        let source = CapabilityEvidence.documentedModel(sourceID: "synthetic-m3-coverage-fixture")
        let cases: [(CapabilityFact?, CapabilityRefusalReason)] = [
            (nil, .absent),
            (documentedUnsupported, .unsupported(source)),
            (documentedUnknown, .unknown(source)),
            (CapabilityFact(state: .supported, evidence: .unobserved), .unobservedSupport),
            // An unknown fact that is also unobserved reports as unknown. The
            // state is consulted first, so "nobody decided" is never relabelled
            // as a support claim that failed its evidence check.
            (CapabilityFact(state: .unknown, evidence: .unobserved), .unknown(.unobserved)),
            (CapabilityFact(state: .unsupported, evidence: .reportedInstallation),
             .unsupported(.reportedInstallation)),
        ]
        for (fact, reason) in cases {
            XCTAssertThrowsError(try trackingProfile(fact)
                .resolveControls(job: .init(tracking: .gap))) {
                XCTAssertEqual($0 as? PrinterProfileError, .unavailableTracking(.gap, reason))
            }
        }

        // No two of these reasons are the same value, so none of them can be
        // reported in place of another.
        let reasons = cases.map(\.1)
        for (outer, first) in reasons.enumerated() {
            for (inner, second) in reasons.enumerated() where inner > outer {
                XCTAssertNotEqual(first, second, "reasons \(outer) and \(inner) collapsed")
            }
        }

        // The other side of the bracket: an evidenced, supported fact has no
        // reason at all, and the control resolves.
        XCTAssertNil(CapabilityRefusalReason.reason(for: documented))
        XCTAssertEqual(try trackingProfile(documented)
            .resolveControls(job: .init(tracking: .gap)).tracking, .value(.gap))
    }

    /// A schema-version refusal is a statement about the profile record; a
    /// capability refusal is a statement about what that record says of the
    /// printer. Folding the first into the second made a profile too old to
    /// express tracking look like a printer that cannot track.
    ///
    /// Both gates are bracketed from each side: the version one below the gate
    /// refuses and names the version, the version at the gate resolves, and the
    /// capability fact is held supported-and-documented throughout so the
    /// refusal demonstrably cannot be about the device.
    func testASchemaVersionRefusalIsSeparateFromACapabilityRefusal() throws {
        for (mode, required) in [(MediaTracking.gap, 5), (.continuous, 5), (.blackMark, 6)] {
            let below = try trackingProfile(documented, version: required - 1)
            XCTAssertEqual(below.capabilities.tracking[mode], documented)
            XCTAssertThrowsError(try below.resolveControls(job: .init(tracking: mode))) {
                XCTAssertEqual($0 as? PrinterProfileError, .controlRequiresSchemaVersion(
                    .tracking(mode), required: required, profileVersion: required - 1))
            }
            // Nothing above the gate reports the version error for this mode.
            let atGate = try trackingProfile(documented, version: required)
            if mode == .gap {
                XCTAssertEqual(try atGate.resolveControls(job: .init(tracking: mode)).tracking,
                               .value(mode))
            } else {
                // Continuous needs a length and black mark needs an offset, so
                // these resolve no further — but they are past the schema gate,
                // which is what this test is about.
                XCTAssertThrowsError(try atGate.resolveControls(job: .init(tracking: mode))) {
                    XCTAssertNil($0 as? PrinterProfileError)
                }
            }
        }

        // Which version a mode needs is part of the refusal: black mark needs
        // one more than the others, and a schema-5 profile says so.
        let five = try trackingProfile(documented, version: 5)
        XCTAssertThrowsError(try five.resolveControls(job: .init(tracking: .blackMark))) {
            XCTAssertEqual($0 as? PrinterProfileError, .controlRequiresSchemaVersion(
                .tracking(.blackMark), required: 6, profileVersion: 5))
        }
        XCTAssertNotEqual(
            PrinterProfileError.controlRequiresSchemaVersion(.tracking(.blackMark), required: 6, profileVersion: 5),
            PrinterProfileError.controlRequiresSchemaVersion(.tracking(.gap), required: 5, profileVersion: 5))
    }

    /// The darkness twin of the two tests above. Its capability is stored as a
    /// non-optional fact, so `.absent` cannot arise; the other three reasons
    /// and the schema gate all can, and each is named.
    func testDarknessRefusalSeparatesTheSchemaGateFromTheCapabilityRecord() throws {
        let source = CapabilityEvidence.documentedModel(sourceID: "synthetic-m3-coverage-fixture")

        // Schema gate: the fact is supported and documented at every version
        // here, so only the record's version refuses below 4.
        for version in 1...3 {
            XCTAssertThrowsError(try darknessProfile(documented, version: version)
                .resolveControls(job: .init(darkness: 15))) {
                XCTAssertEqual($0 as? PrinterProfileError, .controlRequiresSchemaVersion(
                    .darkness, required: 4, profileVersion: version))
            }
        }
        XCTAssertEqual(try darknessProfile(documented, version: 4)
            .resolveControls(job: .init(darkness: 15)).darkness, .value(15))

        // Capability record, at a version that can express darkness.
        let cases: [(CapabilityFact, CapabilityRefusalReason)] = [
            (documentedUnsupported, .unsupported(source)),
            (documentedUnknown, .unknown(source)),
            (CapabilityFact(state: .supported, evidence: .unobserved), .unobservedSupport),
            (CapabilityFact(state: .unknown, evidence: .unobserved), .unknown(.unobserved)),
        ]
        for (fact, reason) in cases {
            XCTAssertThrowsError(try darknessProfile(fact, version: 4)
                .resolveControls(job: .init(darkness: 15))) {
                XCTAssertEqual($0 as? PrinterProfileError, .unavailableDarkness(reason))
            }
        }
        let reasons = cases.map(\.1)
        for (outer, first) in reasons.enumerated() {
            for (inner, second) in reasons.enumerated() where inner > outer {
                XCTAssertNotEqual(first, second, "reasons \(outer) and \(inner) collapsed")
            }
        }

        // A qualified capability still refuses a value off the documented
        // range, and reports that as a value problem rather than availability.
        let qualified = try darknessProfile(documented, version: 4)
        XCTAssertEqual(try qualified.resolveControls(job: .init(darkness: 30)).darkness, .value(30))
        XCTAssertThrowsError(try qualified.resolveControls(job: .init(darkness: 31))) {
            XCTAssertEqual($0 as? PrinterProfileError, .unsupportedDarkness(31))
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
