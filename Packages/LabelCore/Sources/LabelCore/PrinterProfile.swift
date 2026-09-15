import Foundation

/// Typed capability and installed-hardware facts. These records deliberately
/// keep model documentation separate from observations of one installed unit.
public enum CapabilityState: String, Equatable, Sendable {
    case supported
    case unsupported
    case unknown
}

public enum CapabilityEvidence: Equatable, Sendable {
    case documentedModel(sourceID: String)
    case reportedInstallation
    case unobserved
}

public struct CapabilityFact: Equatable, Sendable {
    public let state: CapabilityState
    public let evidence: CapabilityEvidence

    public init(state: CapabilityState, evidence: CapabilityEvidence) {
        self.state = state
        self.evidence = evidence
    }
}

public enum ThermalMethod: String, Equatable, Sendable {
    case directThermal
    case thermalTransfer
}

public enum FinishingMode: String, Equatable, Sendable {
    case tearOff
    case cut
    case peel
    case rewind
}

public enum MediaTracking: String, Equatable, Sendable {
    case gap
    case blackMark
    case continuous
}

/// An observation is intentionally more precise than an optional: callers can
/// preserve the fact that a value has not been measured rather than treating it
/// as a missing default. Observed values carry their source separately from
/// model capabilities.
public enum Observation<Value: Equatable & Sendable>: Equatable, Sendable {
    case unobserved
    case observed(Value, evidence: CapabilityEvidence)
}

public enum MediaForm: String, Equatable, Sendable {
    case preCut
    case continuous
}

/// A calibrated printable rectangle is distinct from the nominal label face.
/// Its origin and dimensions must not be guessed from the print head, liner,
/// or pre-cut stock. Dot coordinates are intentionally not ZPL commands.
public struct MediaCalibration: Equatable, Sendable {
    public let widthDots: Int
    public let lengthDots: Int
    public let originXDot: Int
    public let originYDot: Int

    public init(widthDots: Int, lengthDots: Int, originXDot: Int, originYDot: Int) throws {
        guard widthDots > 0, lengthDots > 0 else {
            throw MediaConfigurationError.invalidCalibrationDimensions
        }
        self.widthDots = widthDots
        self.lengthDots = lengthDots
        self.originXDot = originXDot
        self.originYDot = originYDot
    }
}

public enum MediaConfigurationError: Error, Equatable, Sendable {
    case invalidCalibrationDimensions
}

/// Installed media facts that a profile may bind to a job. A nominal face is
/// useful for workflow planning, but is not a measured printable rectangle and
/// cannot authorize an encoder to emit media length, width, or offset commands.
public struct MediaConfiguration: Equatable, Sendable {
    public let form: Observation<MediaForm>
    public let nominalLabelFace: Observation<PhysicalSize>
    public let configuredTracking: Observation<MediaTracking>
    public let calibration: Observation<MediaCalibration>

    public init(
        form: Observation<MediaForm>,
        nominalLabelFace: Observation<PhysicalSize>,
        configuredTracking: Observation<MediaTracking>,
        calibration: Observation<MediaCalibration>
    ) {
        self.form = form
        self.nominalLabelFace = nominalLabelFace
        self.configuredTracking = configuredTracking
        self.calibration = calibration
    }
}

public enum PrinterTransport: String, Equatable, Sendable {
    case usb
    case rawTCP
}

/// A validated local connection identity. It is intentionally opaque to normal
/// callers and diagnostics; transport URIs, serial numbers, and USB paths must
/// not leak through routine status output.
public struct StableConnectionIdentity: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum ValidationError: Error, Equatable, Sendable { case invalidIdentifier }

    private let rawValue: String

    public init(opaqueValue: String) throws {
        guard !opaqueValue.isEmpty, opaqueValue.utf8.count <= 512,
              opaqueValue.unicodeScalars.allSatisfy({
                  !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0)
              })
        else { throw ValidationError.invalidIdentifier }
        rawValue = opaqueValue
    }

    public var description: String { "StableConnectionIdentity(redacted)" }
    public var debugDescription: String { description }
}

/// Connection facts live beside media and capabilities in the immutable
/// profile. An unobserved identity is not interchangeable with any other USB
/// device and cannot authorize delivery or coordination.
public struct ConnectionConfiguration: Equatable, Sendable {
    public let transport: PrinterTransport
    public let stableIdentity: Observation<StableConnectionIdentity>

    public init(transport: PrinterTransport, stableIdentity: Observation<StableConnectionIdentity>) {
        self.transport = transport
        self.stableIdentity = stableIdentity
    }
}

public struct PrinterCapabilities: Equatable, Sendable {
    public let model: String
    public let thermalTransfer: CapabilityFact
    public let cutter: CapabilityFact
    public let peeler: CapabilityFact
    public let rewind: CapabilityFact
    public let tracking: [MediaTracking: CapabilityFact]
    public let printSpeedChoicesIps: Set<Int>
    public let darkness: CapabilityFact

    public init(
        model: String,
        thermalTransfer: CapabilityFact,
        cutter: CapabilityFact,
        peeler: CapabilityFact,
        rewind: CapabilityFact,
        tracking: [MediaTracking: CapabilityFact],
        printSpeedChoicesIps: Set<Int>,
        darkness: CapabilityFact
    ) {
        self.model = model
        self.thermalTransfer = thermalTransfer
        self.cutter = cutter
        self.peeler = peeler
        self.rewind = rewind
        self.tracking = tracking
        self.printSpeedChoicesIps = printSpeedChoicesIps
        self.darkness = darkness
    }
}

public struct InstalledHardware: Equatable, Sendable {
    public let transport: PrinterTransport
    public let selectedFinishing: FinishingMode
    public let cutter: CapabilityFact
    public let peeler: CapabilityFact
    public let currentSpeedIps: Int?
    public let currentDarkness: Int?
    public let currentTracking: MediaTracking?

    public init(
        transport: PrinterTransport,
        selectedFinishing: FinishingMode,
        cutter: CapabilityFact,
        peeler: CapabilityFact,
        currentSpeedIps: Int?,
        currentDarkness: Int?,
        currentTracking: MediaTracking?
    ) {
        self.transport = transport
        self.selectedFinishing = selectedFinishing
        self.cutter = cutter
        self.peeler = peeler
        self.currentSpeedIps = currentSpeedIps
        self.currentDarkness = currentDarkness
        self.currentTracking = currentTracking
    }
}

/// This is an internal profile record, not a decoder for planning JSON or a
/// public runtime profile schema. Its revision is observable in job binding.
public struct PrinterProfile: Equatable, Sendable {
    public let schemaVersion: Int
    public let revision: Int
    public let capabilities: PrinterCapabilities
    public let installedHardware: InstalledHardware
    public let media: MediaConfiguration
    public let connection: ConnectionConfiguration

    public init(
        schemaVersion: Int,
        revision: Int,
        capabilities: PrinterCapabilities,
        installedHardware: InstalledHardware,
        media: MediaConfiguration,
        connection: ConnectionConfiguration
    ) throws {
        guard schemaVersion == 1, revision > 0 else { throw PrinterProfileError.invalidProfileVersion }
        guard Self.isSafeModelIdentifier(capabilities.model) else {
            throw PrinterProfileError.invalidModelIdentifier
        }
        guard capabilities.printSpeedChoicesIps.allSatisfy({ $0 > 0 }) else {
            throw PrinterProfileError.invalidPrintSpeedChoice
        }
        guard installedHardware.currentSpeedIps.map({ $0 > 0 }) ?? true else {
            throw PrinterProfileError.invalidInstalledPrintSpeed
        }
        guard installedHardware.transport == connection.transport else {
            throw PrinterProfileError.inconsistentConnectionTransport
        }
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.capabilities = capabilities
        self.installedHardware = installedHardware
        self.media = media
        self.connection = connection
    }

    private static func isSafeModelIdentifier(_ model: String) -> Bool {
        guard !model.isEmpty, model.utf8.count <= 128 else { return false }
        return model.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
        }
    }
}

public enum PrinterProfileError: Error, Equatable, Sendable {
    case invalidProfileVersion
    case invalidModelIdentifier
    case invalidPrintSpeedChoice
    case invalidInstalledPrintSpeed
    case inconsistentConnectionTransport
    case unsupportedThermalMethod(ThermalMethod)
    case unsupportedFinishing(FinishingMode)
    case unsupportedPrintSpeed(Int)
    case unavailableDarkness
    case unavailableTracking(MediaTracking)
    case unavailableMediaGeometry
}

/// A typed request for printer media geometry, distinct from document layout.
/// These values must never be derived from a PDF page or nominal label face.
public struct MediaGeometryRequest: Equatable, Sendable {
    public let widthDots: Int?
    public let lengthDots: Int?
    public let originXDot: Int?
    public let originYDot: Int?

    public init(
        widthDots: Int? = nil,
        lengthDots: Int? = nil,
        originXDot: Int? = nil,
        originYDot: Int? = nil
    ) throws {
        guard widthDots.map({ $0 > 0 }) ?? true,
              lengthDots.map({ $0 > 0 }) ?? true else {
            throw MediaConfigurationError.invalidCalibrationDimensions
        }
        self.widthDots = widthDots
        self.lengthDots = lengthDots
        self.originXDot = originXDot
        self.originYDot = originYDot
    }
}

public struct PrinterControlRequest: Equatable, Sendable {
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

public extension PrinterProfile {
    /// Validates explicit user choices before a control encoder or transport is
    /// involved. An absent field means leave the corresponding device setting
    /// unchanged; it is never converted to a guessed current value.
    func validate(_ request: PrinterControlRequest) throws {
        if let method = request.thermalMethod, method == .thermalTransfer {
            throw PrinterProfileError.unsupportedThermalMethod(method)
        }
        if let finishing = request.finishing, finishing != .tearOff {
            throw PrinterProfileError.unsupportedFinishing(finishing)
        }
        if let speed = request.printSpeedIps, !capabilities.printSpeedChoicesIps.contains(speed) {
            throw PrinterProfileError.unsupportedPrintSpeed(speed)
        }
        if request.darkness != nil { throw PrinterProfileError.unavailableDarkness }
        if let tracking = request.tracking {
            // The model documents sensor types, but the installed stock's
            // configured tracking remains unobserved. Do not change it merely
            // because the model is capable of a mode.
            guard installedHardware.currentTracking == tracking,
                  capabilities.tracking[tracking]?.state == .supported else {
                throw PrinterProfileError.unavailableTracking(tracking)
            }
        }
        // Nominal stock never authorizes device geometry. The reference profile
        // has no observed calibration or cited ordinary-job mapping, so an
        // explicit geometry request fails instead of being dropped or guessed.
        if request.mediaGeometry != nil { throw PrinterProfileError.unavailableMediaGeometry }
    }
}

public extension PrinterProfile {
    /// Documented GC420d facts plus the expressly reported USB/tear-off setup.
    /// `nil` current settings remain unknown until a bounded device observation.
    static func gc420dUSBReference(revision: Int = 1) throws -> PrinterProfile {
        let documented = CapabilityEvidence.documentedModel(sourceID: "R26")
        let unobserved = CapabilityEvidence.unobserved
        return try PrinterProfile(
            schemaVersion: 1,
            revision: revision,
            capabilities: PrinterCapabilities(
                model: "GC420d",
                thermalTransfer: CapabilityFact(state: .unsupported, evidence: documented),
                cutter: CapabilityFact(state: .unknown, evidence: unobserved),
                peeler: CapabilityFact(state: .unknown, evidence: unobserved),
                rewind: CapabilityFact(state: .unknown, evidence: unobserved),
                tracking: [
                    .gap: CapabilityFact(state: .supported, evidence: documented),
                    .blackMark: CapabilityFact(state: .supported, evidence: documented),
                    .continuous: CapabilityFact(state: .unknown, evidence: unobserved),
                ],
                printSpeedChoicesIps: [2, 3, 4],
                darkness: CapabilityFact(state: .unknown, evidence: unobserved)
            ),
            installedHardware: InstalledHardware(
                transport: .usb,
                selectedFinishing: .tearOff,
                cutter: CapabilityFact(state: .unsupported, evidence: .reportedInstallation),
                peeler: CapabilityFact(state: .unknown, evidence: unobserved),
                currentSpeedIps: nil,
                currentDarkness: nil,
                currentTracking: nil
            ),
            media: MediaConfiguration(
                form: .observed(.preCut, evidence: .reportedInstallation),
                nominalLabelFace: .observed(
                    try PhysicalSize(
                        width: Millimeters.inches(4),
                        height: Millimeters.inches(6)
                    ),
                    evidence: .reportedInstallation
                ),
                configuredTracking: .unobserved,
                calibration: .unobserved
            ),
            connection: ConnectionConfiguration(
                transport: .usb,
                stableIdentity: .unobserved
            )
        )
    }
}
