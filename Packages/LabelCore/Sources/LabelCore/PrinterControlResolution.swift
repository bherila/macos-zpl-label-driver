/// An explicit choice to preserve a printer's existing setting is distinct
/// from a numeric or enum value. It prevents unknown installed values from
/// silently becoming zero or a guessed factory default.
public enum ResolvedSetting<Value: Equatable & Sendable>: Equatable, Sendable {
    case leaveUnchanged
    case value(Value)
}

public struct PrinterControlDefaults: Equatable, Sendable {
    public var thermalMethod: ThermalMethod?
    public var finishing: FinishingMode?
    public var printSpeedIps: Int?
    public var darkness: Int?
    public var tracking: MediaTracking?
    public var mediaGeometry: MediaGeometryRequest?

    public init(
        thermalMethod: ThermalMethod? = nil,
        finishing: FinishingMode? = nil,
        printSpeedIps: Int? = nil,
        darkness: Int? = nil,
        tracking: MediaTracking? = nil,
        mediaGeometry: MediaGeometryRequest? = nil
    ) {
        self.thermalMethod = thermalMethod
        self.finishing = finishing
        self.printSpeedIps = printSpeedIps
        self.darkness = darkness
        self.tracking = tracking
        self.mediaGeometry = mediaGeometry
    }
}

public struct ResolvedPrinterControls: Equatable, Sendable {
    public let profileSchemaVersion: Int
    public let profileRevision: Int
    public let thermalMethod: ResolvedSetting<ThermalMethod>
    public let finishing: ResolvedSetting<FinishingMode>
    public let printSpeedIps: ResolvedSetting<Int>
    public let darkness: ResolvedSetting<Int>
    public let tracking: ResolvedSetting<MediaTracking>
    public let mediaGeometry: ResolvedSetting<MediaGeometryRequest>
}

public extension PrinterProfile {
    /// Resolves the documented precedence once, then validates the effective
    /// combination. This is deliberately transport-free: it creates neither
    /// ZPL nor a persistent device mutation.
    func resolveControls(
        job: PrinterControlRequest,
        workflowDefaults: PrinterControlDefaults = .init()
    ) throws -> ResolvedPrinterControls {
        let thermal = job.thermalMethod ?? workflowDefaults.thermalMethod ?? .directThermal
        let finishing = job.finishing ?? workflowDefaults.finishing ?? installedHardware.selectedFinishing
        // Read-only observations are deliberately absent from this precedence
        // chain. Only explicit job choices and qualified configured defaults
        // authorize commands; otherwise the device setting is left unchanged.
        let speed = job.printSpeedIps ?? workflowDefaults.printSpeedIps
        let darkness = job.darkness ?? workflowDefaults.darkness
        let tracking = job.tracking ?? workflowDefaults.tracking
        let mediaGeometry = job.mediaGeometry ?? workflowDefaults.mediaGeometry

        try validate(.init(
            thermalMethod: thermal,
            finishing: finishing,
            printSpeedIps: speed,
            darkness: darkness,
            tracking: tracking,
            mediaGeometry: mediaGeometry
        ))
        return ResolvedPrinterControls(
            profileSchemaVersion: schemaVersion,
            profileRevision: revision,
            thermalMethod: .value(thermal),
            finishing: .value(finishing),
            printSpeedIps: speed.map(ResolvedSetting.value) ?? .leaveUnchanged,
            darkness: darkness.map(ResolvedSetting.value) ?? .leaveUnchanged,
            tracking: tracking.map(ResolvedSetting.value) ?? .leaveUnchanged,
            mediaGeometry: mediaGeometry.map(ResolvedSetting.value) ?? .leaveUnchanged
        )
    }
}
