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

public enum PrinterTransport: String, Equatable, Sendable {
    case usb
    case rawTCP
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

    public init(
        schemaVersion: Int,
        revision: Int,
        capabilities: PrinterCapabilities,
        installedHardware: InstalledHardware
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
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.capabilities = capabilities
        self.installedHardware = installedHardware
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
    case unsupportedThermalMethod(ThermalMethod)
    case unsupportedFinishing(FinishingMode)
    case unsupportedPrintSpeed(Int)
    case unavailableDarkness
    case unavailableTracking(MediaTracking)
}

public struct PrinterControlRequest: Equatable, Sendable {
    public var thermalMethod: ThermalMethod?
    public var finishing: FinishingMode?
    public var printSpeedIps: Int?
    public var darkness: Int?
    public var tracking: MediaTracking?

    public init(
        thermalMethod: ThermalMethod? = nil,
        finishing: FinishingMode? = nil,
        printSpeedIps: Int? = nil,
        darkness: Int? = nil,
        tracking: MediaTracking? = nil
    ) {
        self.thermalMethod = thermalMethod
        self.finishing = finishing
        self.printSpeedIps = printSpeedIps
        self.darkness = darkness
        self.tracking = tracking
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
            )
        )
    }
}
