import Foundation

/// Installation declarations, not model support or authenticated sensor reads.
public struct InstalledFinishingAccessories: Equatable, Sendable {
    public let cutter: Observation<Bool>
    public let peeler: Observation<Bool>
    public let rewinder: Observation<Bool>

    public init(cutter: Observation<Bool> = .unobserved, peeler: Observation<Bool> = .unobserved,
                rewinder: Observation<Bool> = .unobserved) {
        self.cutter = cutter; self.peeler = peeler; self.rewinder = rewinder
    }
}

/// A mode fragment does not specify cut intervals, print quantities, prepeel,
/// job boundaries or completion. Ordinary-job admission is a separate contract.
/// Provenance: R45 ^MM table, printed pages305–306.
public struct FinishingControlQualification: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case disabled(FinishingMode)
        case unavailable(FinishingMode, CapabilityState)
        case missingModelEvidence(FinishingMode)
        case unverifiedAccessory(FinishingMode)
        case absentAccessory(FinishingMode)
        case invalidOutputLimit
        case outputLimit
    }

    public let modes: [FinishingMode: CapabilityFact]
    public let enabledModes: Set<FinishingMode>
    public let installed: InstalledFinishingAccessories

    public init(modes: [FinishingMode: CapabilityFact] = [:], enabledModes: Set<FinishingMode> = [],
                installed: InstalledFinishingAccessories = .init()) {
        self.modes = modes; self.enabledModes = enabledModes; self.installed = installed
    }

    public func validate(_ mode: FinishingMode) throws {
        guard enabledModes.contains(mode) else { throw Error.disabled(mode) }
        let fact = modes[mode] ?? .init(state: .unknown, evidence: .unobserved)
        guard fact.state == .supported else { throw Error.unavailable(mode, fact.state) }
        guard fact.evidence != .unobserved else { throw Error.missingModelEvidence(mode) }
        let accessory: Observation<Bool>
        switch mode {
        case .tearOff: return
        case .cut: accessory = installed.cutter
        case .peel: accessory = installed.peeler
        case .rewind: accessory = installed.rewinder
        }
        guard case let .observed(present, evidence) = accessory,
              evidence == .reportedInstallation else { throw Error.unverifiedAccessory(mode) }
        guard present else { throw Error.absentAccessory(mode) }
    }

    /// Bounded offline inspection only. In particular ^MMC alone does not
    /// implement a per-label/batch/job-end cutting policy; no ~JK is emitted.
    public func encodeMode(_ mode: FinishingMode, maximumOutputBytes: Int = 1024) throws -> Data {
        guard (1...64 * 1024).contains(maximumOutputBytes) else { throw Error.invalidOutputLimit }
        try validate(mode)
        let command: String
        switch mode {
        case .tearOff: command = "^MMT\n"
        case .cut: command = "^MMC\n"
        case .peel: command = "^MMP\n"
        case .rewind: command = "^MMR\n"
        }
        let result = Data(command.utf8)
        guard result.count <= maximumOutputBytes else { throw Error.outputLimit }
        return result
    }
}
