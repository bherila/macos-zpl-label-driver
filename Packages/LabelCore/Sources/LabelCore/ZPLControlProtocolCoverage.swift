import Foundation

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
        .tearOff: .init(option: "tearOff", command: "^MMT", sourceID: "R45",
            lifetime: .modelSpecificOrUnverified, notes: "No cutter/peeler command inferred.",
            implementedRange: "T", modelLimits: "Supported enabled mode; selected GC420d baseline is tear-off")
    ]

    /// Qualified accessory route is separate from ordinary documented fragments.
    public static let qualifiedFinishingControls: [FinishingMode: Self] = [
        .tearOff: documentedControls[.tearOff]!,
        .cut: .init(option: "cutSchedule", command: "^MMC/^MMD/~JK", sourceID: "R45",
            lifetime: .modelSpecificOrUnverified,
            notes: "Offline fragments use ^MMC without scheduling authority. Native framing uses separately qualified delayed-cut mode and separate trigger files after observed readiness; quantity 1 per already-expanded output. Never infer cut completion from sent bytes.",
            implementedRange: "each label / qualified batch / job end", modelLimits: "Observed cutter/compatible stock; independently supported policies and batch maximum; exact framing qualification"),
        .peel: .init(option: "peel", command: "^MMP,N/^MMP", sourceID: "R45",
            lifetime: .modelSpecificOrUnverified,
            notes: "Prepeel policy separately qualified; label-taken wait retains ownership; missing status is unknown.",
            implementedRange: "P with explicitly qualified prepeel policy", modelLimits: "Observed peeler and compatible stock; qualified status/readiness contract"),
        .rewind: .init(option: "rewind", command: "^MMR", sourceID: "R45",
            lifetime: .modelSpecificOrUnverified,
            notes: "Independent finishing support and installation; no accessory inferred from another mode.",
            implementedRange: "R", modelLimits: "Observed rewind installation and compatible stock; supported enabled mode")
    ]
}
