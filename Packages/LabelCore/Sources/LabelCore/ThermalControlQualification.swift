import Foundation

/// Model command support is distinct from the loaded media and ribbon. This
/// policy produces offline fragments only; it does not authorize device I/O.
public struct ThermalControlQualification: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case unavailable(ThermalMethod, CapabilityState)
        case missingModelEvidence
        case unverifiedMedia
        case incompatibleMedia
        case unverifiedRibbon
        case incompatibleRibbon
    }

    public let directThermal: CapabilityFact
    public let thermalTransfer: CapabilityFact

    public init(directThermal: CapabilityFact, thermalTransfer: CapabilityFact) {
        self.directThermal = directThermal
        self.thermalTransfer = thermalTransfer
    }

    /// Both observations must describe the intended loaded configuration, not
    /// an inferred default or a marketing capability. False ribbon presence is
    /// an explicit observation, never a conversion of unknown into false.
    public func control(for method: ThermalMethod,
                        media: Observation<ThermalMethod>,
                        ribbonPresent: Observation<Bool>) throws -> ZPLDocumentedControl {
        let fact = method == .directThermal ? directThermal : thermalTransfer
        guard fact.state == .supported else { throw Error.unavailable(method, fact.state) }
        guard fact.evidence != .unobserved else { throw Error.missingModelEvidence }
        guard case let .observed(loadedMethod, mediaEvidence) = media,
              mediaEvidence == .reportedInstallation else { throw Error.unverifiedMedia }
        guard loadedMethod == method else { throw Error.incompatibleMedia }
        guard case let .observed(present, ribbonEvidence) = ribbonPresent,
              ribbonEvidence == .reportedInstallation else { throw Error.unverifiedRibbon }
        guard present == (method == .thermalTransfer) else { throw Error.incompatibleRibbon }
        return .thermalMethod(method)
    }
}

public extension ZPLDocumentedControlEncoder {
    func encodeThermalMethod(_ method: ThermalMethod, policy: ThermalControlQualification,
                             media: Observation<ThermalMethod>,
                             ribbonPresent: Observation<Bool>) throws -> Data {
        let control = try policy.control(for: method, media: media, ribbonPresent: ribbonPresent)
        return try encode([control], qualification: [control.kind: .supported])
    }
}
