/// An explicit choice to preserve a printer's existing setting is distinct
/// from a numeric or enum value. It prevents unknown installed values from
/// silently becoming zero or a guessed factory default.
public enum ResolvedSetting<Value: Equatable & Sendable>: Equatable, Sendable {
    case leaveUnchanged
    case value(Value)
}

/// Unspecified secondary speeds are not a promise to preserve device state:
/// a legacy ^PRp command may apply omitted-argument defaults on the device.
public enum ResolvedMotorSpeed: Equatable, Sendable {
    case notExplicitlyControlled
    case value(Int)

    public var explicitValue: Int? {
        if case let .value(value) = self { return value }
        return nil
    }
}

public struct PrinterControlDefaults: Equatable, Sendable {
    public var thermalMethod: ThermalMethod?
    public var finishing: FinishingMode?
    public var printSpeedIps: Int?
    public var feedSpeedIps: Int?
    public var backfeedSpeedIps: Int?
    public var darkness: Int?
    public var tracking: MediaTracking?
    public var mediaGeometry: MediaGeometryRequest?
    public var offsets: OffsetControlRequest?

    public init(
        thermalMethod: ThermalMethod? = nil,
        finishing: FinishingMode? = nil,
        printSpeedIps: Int? = nil,
        feedSpeedIps: Int? = nil,
        backfeedSpeedIps: Int? = nil,
        darkness: Int? = nil,
        tracking: MediaTracking? = nil,
        mediaGeometry: MediaGeometryRequest? = nil,
        offsets: OffsetControlRequest? = nil
    ) {
        self.thermalMethod = thermalMethod
        self.finishing = finishing
        self.printSpeedIps = printSpeedIps
        self.feedSpeedIps = feedSpeedIps
        self.backfeedSpeedIps = backfeedSpeedIps
        self.darkness = darkness
        self.tracking = tracking
        self.mediaGeometry = mediaGeometry
        self.offsets = offsets
    }
}

public struct ResolvedPrinterControls: Equatable, Sendable {
    public let profileSchemaVersion: Int
    public let profileRevision: Int
    public let thermalMethod: ResolvedSetting<ThermalMethod>
    public let finishing: ResolvedSetting<FinishingMode>
    public let printSpeedIps: ResolvedSetting<Int>
    public let feedSpeedIps: ResolvedMotorSpeed
    public let backfeedSpeedIps: ResolvedMotorSpeed
    public let darkness: ResolvedSetting<Int>
    public let tracking: ResolvedSetting<MediaTracking>
    public let mediaGeometry: ResolvedSetting<MediaGeometryRequest>
    public let offsets: ResolvedSetting<OffsetControlRequest>

    init(profileSchemaVersion: Int, profileRevision: Int,
         thermalMethod: ResolvedSetting<ThermalMethod>, finishing: ResolvedSetting<FinishingMode>,
         printSpeedIps: ResolvedSetting<Int>, feedSpeedIps: ResolvedMotorSpeed = .notExplicitlyControlled,
         backfeedSpeedIps: ResolvedMotorSpeed = .notExplicitlyControlled,
         darkness: ResolvedSetting<Int>, tracking: ResolvedSetting<MediaTracking>,
         mediaGeometry: ResolvedSetting<MediaGeometryRequest>, offsets: ResolvedSetting<OffsetControlRequest> = .leaveUnchanged) {
        self.profileSchemaVersion = profileSchemaVersion
        self.profileRevision = profileRevision
        self.thermalMethod = thermalMethod
        self.finishing = finishing
        self.printSpeedIps = printSpeedIps
        self.feedSpeedIps = feedSpeedIps
        self.backfeedSpeedIps = backfeedSpeedIps
        self.darkness = darkness
        self.tracking = tracking
        self.mediaGeometry = mediaGeometry
        self.offsets = offsets
    }
}

/// Schema8 currently stores declarations only. Queue/ticket, preparation and
/// mechanical normalization must be extended together before ordinary admission.
enum OrdinaryPrinterProfileAdmission {
    static func validate(_ version: Int) throws {
        guard (1...7).contains(version) else { throw PrinterProfileError.invalidProfileVersion }
    }
}

public extension PrinterProfile {
    /// Resolves the documented precedence once, then validates the effective
    /// combination. This is deliberately transport-free: it creates neither
    /// ZPL nor a persistent device mutation.
    func resolveControls(
        job: PrinterControlRequest,
        workflowDefaults: PrinterControlDefaults = .init()
    ) throws -> ResolvedPrinterControls {
        try OrdinaryPrinterProfileAdmission.validate(schemaVersion)
        return try resolveEffectiveControls(job: job, workflowDefaults: workflowDefaults, finishingPlan: nil)
    }

    /// Offline finishing resolution only. The exact stored policy must reproduce
    /// the supplied plan; ordinary encoders still reject schema8 controls.
    func resolveFinishingControls(
        plan: FinishingJobPlan, job: PrinterControlRequest,
        workflowDefaults: PrinterControlDefaults = .init()
    ) throws -> ResolvedPrinterControls {
        guard schemaVersion == 8, let configuration = finishingConfiguration else {
            throw PrinterProfileError.invalidProfileVersion
        }
        let expected = try FinishingJobPlan(mode: plan.mode, outputLabelCount: plan.outputLabelCount,
            media: media, stock: configuration.stock, finishing: configuration.finishing,
            schedule: plan.schedule, scheduleQualification: configuration.schedules)
        guard expected == plan else { throw FinishingControlResolutionError.planMismatch }
        return try resolveEffectiveControls(job: job, workflowDefaults: workflowDefaults, finishingPlan: plan)
    }

    private func resolveEffectiveControls(
        job: PrinterControlRequest, workflowDefaults: PrinterControlDefaults,
        finishingPlan: FinishingJobPlan?
    ) throws -> ResolvedPrinterControls {
        guard let thermal = job.thermalMethod ?? workflowDefaults.thermalMethod
            ?? configuredDefaults.thermalMethod ?? (schemaVersion < 7 ? .directThermal : nil) else {
            throw ThermalControlQualification.Error.explicitMethodRequired
        }
        let finishing = job.finishing ?? workflowDefaults.finishing
            ?? configuredDefaults.finishing ?? installedHardware.selectedFinishing
        // Read-only observations are deliberately absent from this precedence
        // chain. Only explicit job choices and qualified configured defaults
        // authorize commands; otherwise the device setting is left unchanged.
        let speed = job.printSpeedIps ?? workflowDefaults.printSpeedIps ?? configuredDefaults.printSpeedIps
        let feed = job.feedSpeedIps ?? workflowDefaults.feedSpeedIps ?? configuredDefaults.feedSpeedIps
        let backfeed = job.backfeedSpeedIps ?? workflowDefaults.backfeedSpeedIps ?? configuredDefaults.backfeedSpeedIps
        let darkness = job.darkness ?? workflowDefaults.darkness ?? configuredDefaults.darkness
        let tracking = job.tracking ?? workflowDefaults.tracking ?? configuredDefaults.tracking
        let mediaGeometry: MediaGeometryRequest?
        if job.mediaGeometry != nil || workflowDefaults.mediaGeometry != nil || configuredDefaults.mediaGeometry != nil {
            func field(_ key: KeyPath<MediaGeometryRequest, Int?>) -> Int? {
                let explicit = job.mediaGeometry?[keyPath: key]
                let workflow = workflowDefaults.mediaGeometry?[keyPath: key]
                let configured = configuredDefaults.mediaGeometry?[keyPath: key]
                return explicit ?? workflow ?? configured
            }
            mediaGeometry = try .init(widthDots: field(\.widthDots), lengthDots: field(\.lengthDots),
                                      originXDot: field(\.originXDot), originYDot: field(\.originYDot))
        } else { mediaGeometry = nil }

        let offsets: OffsetControlRequest?
        if job.offsets != nil || workflowDefaults.offsets != nil || configuredDefaults.offsets != nil {
            func field(_ key: KeyPath<OffsetControlRequest, Int?>) -> Int? {
                job.offsets?[keyPath: key] ?? workflowDefaults.offsets?[keyPath: key] ?? configuredDefaults.offsets?[keyPath: key]
            }
            offsets = .init(blackMarkOffsetDots: field(\.blackMarkOffsetDots), shiftLeftDots: field(\.shiftLeftDots),
                            labelTopDots: field(\.labelTopDots))
        } else { offsets = nil }

        let effective = PrinterControlRequest(
            thermalMethod: thermal,
            finishing: finishing,
            printSpeedIps: speed,
            feedSpeedIps: feed,
            backfeedSpeedIps: backfeed,
            darkness: darkness,
            tracking: tracking,
            mediaGeometry: mediaGeometry, offsets: offsets
        )
        if let finishingPlan {
            guard finishing == finishingPlan.mode else { throw FinishingControlResolutionError.modeMismatch }
            try validateNonFinishingControls(effective)
        } else {
            try validate(effective)
        }
        return ResolvedPrinterControls(
            profileSchemaVersion: schemaVersion,
            profileRevision: revision,
            thermalMethod: .value(thermal),
            finishing: .value(finishing),
            printSpeedIps: speed.map(ResolvedSetting.value) ?? .leaveUnchanged,
            feedSpeedIps: feed.map(ResolvedMotorSpeed.value) ?? .notExplicitlyControlled,
            backfeedSpeedIps: backfeed.map(ResolvedMotorSpeed.value) ?? .notExplicitlyControlled,
            darkness: darkness.map(ResolvedSetting.value) ?? .leaveUnchanged,
            tracking: tracking.map(ResolvedSetting.value) ?? .leaveUnchanged,
            mediaGeometry: mediaGeometry.map(ResolvedSetting.value) ?? .leaveUnchanged,
            offsets: offsets.map(ResolvedSetting.value) ?? .leaveUnchanged
        )
    }
}

public enum FinishingControlResolutionError: Error, Equatable, Sendable {
    case planMismatch
    case modeMismatch
}
