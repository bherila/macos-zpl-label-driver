import Foundation

/// The single authoritative finishing-mode literal table.
///
/// Every site that emits a finishing mode command derives its bytes from here:
/// the bounded offline-inspection route in `FinishingControlQualification`, the
/// documented-control and ordinary control encoders, and the production framed
/// output route in LabelMac. Before this table the literals were restated at
/// each site, so a change at one could silently diverge from the others and
/// from the coverage rows below (issue #103).
///
/// Provenance: R45 ^MM table, printed pages305–306; ~JK is the separate
/// delayed-cut trigger, not part of ^MM. Membership here is protocol mapping
/// only. It grants no model support, no accessory presence and no authority to
/// reach a device; each emitting site keeps its own capability gate.
public enum ZPLFinishingControlLiteral: String, CaseIterable, Equatable, Sendable {
    case tearOff = "^MMT"
    case immediateCut = "^MMC"
    case delayedCut = "^MMD"
    case peel = "^MMP"
    case peelExplicitNoPrepeel = "^MMP,N"
    case rewind = "^MMR"
    case delayedCutTrigger = "~JK"

    /// One complete command line. Nothing is interpolated into a literal: no
    /// profile string and no document content ever reaches these bytes.
    public var line: Data { Data((rawValue + "\n").utf8) }

    /// Bounded offline inspection. `^MMC` alone schedules no cutting policy and
    /// no trigger follows it, so this route deliberately never reaches
    /// `.delayedCut` or `.delayedCutTrigger`.
    public static func offlineInspection(of mode: FinishingMode) -> Self {
        switch mode {
        case .tearOff: return .tearOff
        case .cut: return .immediateCut
        case .peel: return .peel
        case .rewind: return .rewind
        }
    }

    /// Production framed output. The cut route is the separately qualified
    /// delayed-cut mode, paired with `delayedCutTrigger` in its own later file
    /// after observed readiness; it is never `.immediateCut`.
    public static func framedMode(of policy: FinishingOutputQualification.ModePolicy) -> Self {
        switch policy {
        case .tearOff: return .tearOff
        case .rewind: return .rewind
        case .peelExplicitNoPrepeel: return .peelExplicitNoPrepeel
        case .peelPrepeelNotApplicable: return .peel
        case .delayedCutSeparateFiles: return .delayedCut
        }
    }

    /// Every literal either route may emit for `mode`, in documentation order.
    /// The coverage rows below are derived from this, so a literal cannot be
    /// emitted by a route without also appearing in the documented mapping.
    public static func documented(of mode: FinishingMode) -> [Self] {
        switch mode {
        case .tearOff: return [.tearOff]
        case .cut: return [.immediateCut, .delayedCut, .delayedCutTrigger]
        case .peel: return [.peelExplicitNoPrepeel, .peel]
        case .rewind: return [.rewind]
        }
    }

    /// The coverage row's `command` field, derived rather than restated.
    public static func documentedCommand(of mode: FinishingMode) -> String {
        documented(of: mode).map(\.rawValue).joined(separator: "/")
    }
}

extension ZPLControlProtocol {
    /// Inspection metadata only; never used to construct commands or grant support.
    public static let documentedControls: [ZPLDocumentedControl.Kind: Self] = [
        .printRate: qualifiedMotorSpeedTuple,
        .absoluteDarkness: qualifiedAbsoluteDarkness,
        .directThermal: qualifiedThermalMethod,
        .thermalTransfer: qualifiedThermalMethod,
        .gapTracking: .init(option: "gapTracking", command: "^MNY", sourceID: "R45",
            lifetime: .modelSpecificOrUnverified,
            notes: "Exclusive with mark/continuous tracking; pre-cut stock is not sensing evidence.",
            implementedRange: "Y", modelLimits: "Independently qualified gap tracking; reference sensing unknown"),
        .continuousTracking: .init(option: "continuousTracking/labelLengthDots", command: "^MNN/^LL", sourceID: "R46",
            lifetime: .modelSpecificOrUnverified,
            notes: "Mode precedes explicit length; does not normalize a later gap/mark format.",
            implementedRange: "N and 1...32000 dots", modelLimits: "Length intersects supplied qualified model/memory maximum"),
        .blackMarkTracking: .init(option: "blackMarkTracking/offsetDots", command: "^MNM,offset", sourceID: "R45",
            lifetime: .modelSpecificOrUnverified,
            notes: "Exclusive tracking; mark offset is separate from home, shift and top.",
            implementedRange: "-75...283 dots", modelLimits: "Conservative subset intersects qualified model offset range"),
        .printWidth: .init(option: "printWidthDots", command: "^PW", sourceID: "R45",
            lifetime: .modelSpecificOrUnverified,
            notes: "32000 is an implementation subset, not a universal protocol ceiling; reject known clipping or printer clamping.",
            implementedRange: "2...32000 dots", modelLimits: "Requested and declared maxima both bounded; intersect label/head/model width"),
        .labelHome: .init(option: "labelHomeXDot/labelHomeYDot", command: "^LHx,y", sourceID: "R45",
            lifetime: .modelSpecificOrUnverified,
            notes: "Both axes explicit; known origin plus raster extent must fit, without hidden scaling.",
            implementedRange: "0...32000 dots per axis", modelLimits: "Independent qualified origin/extent bounds and clipping checks"),
        .labelShiftLeft: .init(option: "shiftLeftDots", command: "^LS", sourceID: "R45",
            lifetime: .modelSpecificOrUnverified,
            notes: "Signed independent horizontal adjustment, not home or mark offset.",
            implementedRange: "-9999...9999 dots", modelLimits: "Intersects separately qualified shift bounds"),
        .labelTop: .init(option: "labelTopDots", command: "^LT", sourceID: "R45",
            lifetime: .modelSpecificOrUnverified,
            notes: "Signed independent top adjustment; no silent substitution for another offset.",
            implementedRange: "-120...120 dots", modelLimits: "Intersects separately qualified top bounds"),
        .tearOff: .init(option: "tearOff",
            command: ZPLFinishingControlLiteral.documentedCommand(of: .tearOff), sourceID: "R45",
            lifetime: .modelSpecificOrUnverified, notes: "No cutter/peeler command inferred.",
            implementedRange: "T", modelLimits: "Supported enabled mode; selected GC420d baseline is tear-off")
    ]

    /// Qualified accessory route is separate from ordinary documented fragments.
    public static let qualifiedFinishingControls: [FinishingMode: Self] = [
        .tearOff: documentedControls[.tearOff]!,
        .cut: .init(option: "cutSchedule",
            command: ZPLFinishingControlLiteral.documentedCommand(of: .cut), sourceID: "R45",
            lifetime: .modelSpecificOrUnverified,
            notes: "Offline fragments use ^MMC without scheduling authority. Native framing uses separately qualified delayed-cut mode and separate trigger files after observed readiness; quantity 1 per already-expanded output. Never infer cut completion from sent bytes.",
            implementedRange: "each label / qualified batch / job end", modelLimits: "Observed cutter/compatible stock; independently supported policies and batch maximum; exact framing qualification"),
        .peel: .init(option: "peel",
            command: ZPLFinishingControlLiteral.documentedCommand(of: .peel), sourceID: "R45",
            lifetime: .modelSpecificOrUnverified,
            notes: "Prepeel policy separately qualified; label-taken wait retains ownership; missing status is unknown.",
            implementedRange: "P with explicitly qualified prepeel policy", modelLimits: "Observed peeler and compatible stock; qualified status/readiness contract"),
        .rewind: .init(option: "rewind",
            command: ZPLFinishingControlLiteral.documentedCommand(of: .rewind), sourceID: "R45",
            lifetime: .modelSpecificOrUnverified,
            notes: "Independent finishing support and installation; no accessory inferred from another mode.",
            implementedRange: "R", modelLimits: "Observed rewind installation and compatible stock; supported enabled mode")
    ]
}
