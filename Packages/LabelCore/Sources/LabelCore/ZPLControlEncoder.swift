import Foundation

/// Provenance for a supported control command. This is a compact protocol
/// table, not a claim that every documented ZPL command is valid for GC420d.
public struct ZPLControlProtocol: Equatable, Sendable {
    public enum Lifetime: Equatable, Sendable {
        case formatOrSession
        case applicationUntilReissuedOrPowerOff
        case modelSpecificOrUnverified
    }

    public let option: String
    public let command: String
    public let sourceID: String
    public let lifetime: Lifetime
    public let notes: String
    public let implementedRange: String
    public let modelLimits: String

    public init(option: String, command: String, sourceID: String, lifetime: Lifetime, notes: String,
                implementedRange: String = "Model-specific or unverified",
                modelLimits: String = "Requires separate profile qualification") {
        self.option = option
        self.command = command
        self.sourceID = sourceID
        self.lifetime = lifetime
        self.notes = notes
        self.implementedRange = implementedRange
        self.modelLimits = modelLimits
    }

    public static let qualifiedMotorSpeedTuple: ZPLControlProtocol = .init(
        option: "printSpeedIps/feedSpeedIps/backfeedSpeedIps", command: "^PRp,s,b", sourceID: "R45",
        lifetime: .applicationUntilReissuedOrPowerOff,
        notes: "All three values explicit; feed/backfeed need separate profile qualification. Reference remains unknown.",
        implementedRange: "2...12 ips independently", modelLimits: "Each supplied speed-choice set intersects this subset; GC420d print speed remains 2/3/4 ips")

    public static let qualifiedThermalMethod: ZPLControlProtocol = .init(
        option: "thermalMethod", command: "^MTD/^MTT", sourceID: "R45",
        lifetime: .modelSpecificOrUnverified,
        notes: "Profile7 requires separate evidenced method support and matching declared loaded media/ribbon; reissued per label, not physical state-isolation proof.",
        implementedRange: "D/T", modelLimits: "Independent evidenced method and loaded consumables; GC420d direct-only")

    public static let qualifiedAbsoluteDarkness: ZPLControlProtocol = .init(
        option: "darkness", command: "^MD0/~SD", sourceID: "R45",
        lifetime: .applicationUntilReissuedOrPowerOff,
        notes: "Explicit integer 0..30; relative adjustment normalized. Requires qualified profile4 fact; reference remains unknown.",
        implementedRange: "0...30 integer", modelLimits: "Qualified absolute-darkness support; installed reference value unknown")

    public static let gc420dBaseline: [ZPLControlProtocol] = [
        .init(option: "printSpeedIps", command: "^PRp", sourceID: "R11",
              lifetime: .applicationUntilReissuedOrPowerOff,
              notes: "Only model-documented 2, 3, or 4 ips values are admitted.",
              implementedRange: "2/3/4 ips", modelLimits: "GC420d documented print-speed choices only"),
        .init(option: "finishing", command: "^MMT", sourceID: "R22",
              lifetime: .modelSpecificOrUnverified,
              notes: "Tear-off is the only selected installed baseline mode.",
              implementedRange: "T", modelLimits: "GC420d selected tear-off; cutter absent and peel disabled"),
    ]
}

public enum ZPLControlEncodingError: Error, Equatable, Sendable {
    case unsupportedPrintSpeed(Int)
    case unqualifiedDarkness
    case unqualifiedTracking
    case unsupportedThermalMethod
    case unsupportedFinishing
    case incompleteMotorSpeeds
    case unqualifiedMotorSpeeds
    case outputLimit
}

/// Encodes the provenance-backed subset of resolved qualified controls. Resolution
/// validates immutable model and installation declarations before creating controls.
/// No raw strings, reset, calibration, save, erase, firmware, copies or transport.
public struct ZPLControlEncoder: Sendable {
    public let maxOutputBytes: Int

    public init(maxOutputBytes: Int = 1_024) throws {
        guard maxOutputBytes > 0 else { throw ZPLControlEncodingError.outputLimit }
        self.maxOutputBytes = maxOutputBytes
    }

    public func encode(_ controls: ResolvedPrinterControls) throws -> Data {
        try OrdinaryPrinterProfileAdmission.validate(controls.profileSchemaVersion)
        return try encodeResolved(controls, excludeFinishing: false)
    }

    /// Normal control prefix only. Finishing commands, cut boundaries, format
    /// framing and peel handling require a separate qualified output policy.
    public func prepareFinishingNormalization(
        profile: PrinterProfile, plan: FinishingJobPlan, job: PrinterControlRequest,
        workflowDefaults: PrinterControlDefaults = .init()
    ) throws -> FinishingControlNormalization {
        let controls = try profile.resolveFinishingControls(plan: plan, job: job,
            workflowDefaults: workflowDefaults)
        return try .init(profile: profile, plan: plan, controls: controls,
            bytes: encodeResolved(controls, excludeFinishing: true))
    }

    private func encodeResolved(_ controls: ResolvedPrinterControls, excludeFinishing: Bool) throws -> Data {
        switch controls.thermalMethod {
        case .leaveUnchanged, .value(.directThermal): break
        case .value(.thermalTransfer):
            guard controls.profileSchemaVersion == 7 || (excludeFinishing && controls.profileSchemaVersion == 8) else { throw ZPLControlEncodingError.unsupportedThermalMethod }
        }
        switch controls.finishing {
        case .leaveUnchanged: break
        case .value(.tearOff):
            // The explicitly selected setup mode. It is a printer-mode command,
            // not a cutter or peel command.
            break
        case .value:
            guard excludeFinishing && controls.profileSchemaVersion == 8 else { throw ZPLControlEncodingError.unsupportedFinishing }
        }
        var darknessBytes: Data?
        if case let .value(value) = controls.darkness {
            guard controls.profileSchemaVersion >= 4 else { throw ZPLControlEncodingError.unqualifiedDarkness }
            darknessBytes = try ZPLDocumentedControlEncoder().encode([.absoluteDarkness(value)],
                qualification: [.absoluteDarkness: .supported])
        }
        var physical: [ZPLDocumentedControl] = []
        var width: Int?
        var length: Int?
        if case let .value(tracking) = controls.tracking {
            guard controls.profileSchemaVersion >= 5 else { throw ZPLControlEncodingError.unqualifiedTracking }
            switch tracking {
            case .gap: physical.append(.gapTracking)
            case .continuous:
                guard case let .value(geometry) = controls.mediaGeometry, let value = geometry.lengthDots else {
                    throw PhysicalGeometryQualification.Error.continuousLengthRequired
                }
                length = value
                physical.append(.continuousTracking(labelLengthDots: value))
            case .blackMark:
                guard controls.profileSchemaVersion >= 6, case let .value(offsets) = controls.offsets,
                      offsets.blackMarkOffsetDots != nil else { throw ZPLControlEncodingError.unqualifiedTracking }
            }
        }
        if case let .value(geometry) = controls.mediaGeometry {
            guard controls.profileSchemaVersion >= 5 else { throw PrinterProfileError.unavailableMediaGeometry }
            if geometry.lengthDots != nil && length == nil { throw PhysicalGeometryQualification.Error.continuousModeRequired }
            guard (geometry.originXDot == nil) == (geometry.originYDot == nil) else {
                throw PhysicalGeometryQualification.Error.incompleteHome
            }
            if let value = geometry.widthDots {
                guard (2...32_000).contains(value) else { throw ZPLDocumentedControlEncoder.Error.invalidValue(.printWidth) }
                width = value; physical.append(.printWidth(dots: value))
            }
            if let x = geometry.originXDot, let y = geometry.originYDot { physical.append(.labelHome(xDots: x, yDots: y)) }
            guard geometry.widthDots != nil || geometry.lengthDots != nil || geometry.originXDot != nil else {
                throw PhysicalGeometryQualification.Error.emptyRequest
            }
        }
        var offsetControls: [ZPLDocumentedControl] = []
        var markRange: ClosedRange<Int>?
        var topRange: ClosedRange<Int>?
        if case let .value(offsets) = controls.offsets {
            guard controls.profileSchemaVersion >= 6 else { throw PrinterProfileError.invalidProfileVersion }
            if let value = offsets.blackMarkOffsetDots {
                guard controls.tracking == .value(.blackMark) else { throw OffsetControlQualification.Error.blackMarkModeRequired }
                offsetControls.append(.blackMarkTracking(offsetDots: value)); markRange = value...value
            }
            if let value = offsets.shiftLeftDots { offsetControls.append(.labelShiftLeft(dots: value)) }
            if let value = offsets.labelTopDots { offsetControls.append(.labelTop(dots: value)); topRange = value...value }
            guard !offsetControls.isEmpty else { throw OffsetControlQualification.Error.emptyRequest }
        }
        let offsetBytes = try ZPLDocumentedControlEncoder().encode(offsetControls,
            qualification: Dictionary(uniqueKeysWithValues: offsetControls.map { ($0.kind, CapabilityState.supported) }),
            limits: .init(blackMarkOffsetDots: markRange, labelTopDots: topRange))
        let physicalBytes = try ZPLDocumentedControlEncoder().encode(physical,
            qualification: Dictionary(uniqueKeysWithValues: physical.map { ($0.kind, CapabilityState.supported) }),
            limits: .init(maximumPrintWidthDots: width, maximumContinuousLabelLengthDots: length))
        // This encoder implements only the documented GC420d subset. A caller's
        // capability declaration cannot widen the documented command subset.
        if case let .value(speed) = controls.printSpeedIps, ![2, 3, 4].contains(speed) {
            throw ZPLControlEncodingError.unsupportedPrintSpeed(speed)
        }

        var motorBytes: Data?
        if controls.feedSpeedIps != .notExplicitlyControlled || controls.backfeedSpeedIps != .notExplicitlyControlled {
            guard controls.profileSchemaVersion >= 3 else { throw ZPLControlEncodingError.unqualifiedMotorSpeeds }
            guard case let .value(printSpeed) = controls.printSpeedIps,
                  case let .value(feedSpeed) = controls.feedSpeedIps,
                  case let .value(backfeedSpeed) = controls.backfeedSpeedIps else {
                throw ZPLControlEncodingError.incompleteMotorSpeeds
            }
            motorBytes = try ZPLDocumentedControlEncoder().encode(
                [.printRate(printIps: printSpeed, feedIps: feedSpeed, backfeedIps: backfeedSpeed)],
                qualification: [.printRate: .supported],
                limits: .init(printSpeedChoicesIps: [printSpeed], feedSpeedChoicesIps: [feedSpeed],
                              backfeedSpeedChoicesIps: [backfeedSpeed]))
        }
        var output = Data()
        if controls.profileSchemaVersion >= 7 {
            guard case let .value(method) = controls.thermalMethod else {
                throw ThermalControlQualification.Error.explicitMethodRequired
            }
            let control = ZPLDocumentedControl.thermalMethod(method)
            output.append(try ZPLDocumentedControlEncoder().encode([control],
                qualification: [control.kind: .supported]))
        }
        if !excludeFinishing && controls.finishing == .value(.tearOff) { output.append(contentsOf: "^MMT\n".utf8) }
        if let motorBytes { output.append(motorBytes) }
        else if case let .value(speed) = controls.printSpeedIps {
            output.append(contentsOf: "^PR\(speed)\n".utf8)
        }
        if let darknessBytes { output.append(darknessBytes) }
        output.append(physicalBytes)
        output.append(offsetBytes)
        guard output.count <= maxOutputBytes else { throw ZPLControlEncodingError.outputLimit }
        return output
    }
}

/// Validated offline normal-control bytes with their complete immutable context.
/// There are deliberately no finishing commands or format/copy/cut triggers.
public struct FinishingControlNormalization: Equatable, Sendable {
    public let profile: PrinterProfile
    public let plan: FinishingJobPlan
    public let controls: ResolvedPrinterControls
    public let bytes: Data

    fileprivate init(profile: PrinterProfile, plan: FinishingJobPlan,
                     controls: ResolvedPrinterControls, bytes: Data) {
        self.profile = profile; self.plan = plan; self.controls = controls; self.bytes = bytes
    }
}
