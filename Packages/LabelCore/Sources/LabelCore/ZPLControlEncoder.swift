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

    public init(option: String, command: String, sourceID: String, lifetime: Lifetime, notes: String) {
        self.option = option
        self.command = command
        self.sourceID = sourceID
        self.lifetime = lifetime
        self.notes = notes
    }

    public static let gc420dBaseline: [ZPLControlProtocol] = [
        .init(option: "printSpeedIps", command: "^PRp", sourceID: "R11",
              lifetime: .applicationUntilReissuedOrPowerOff,
              notes: "Only model-documented 2, 3, or 4 ips values are admitted."),
        .init(option: "finishing", command: "^MMT", sourceID: "R22",
              lifetime: .modelSpecificOrUnverified,
              notes: "Tear-off is the only selected installed baseline mode."),
    ]
}

public enum ZPLControlEncodingError: Error, Equatable, Sendable {
    case unsupportedPrintSpeed(Int)
    case unqualifiedDarkness
    case unqualifiedTracking
    case unsupportedThermalMethod
    case unsupportedFinishing
    case outputLimit
}

/// Encodes only the safe, provenance-backed subset of resolved GC420d controls.
/// It has no raw-string input and cannot emit reset, calibration, save, erase,
/// firmware, copy, media-dimension, or device-transport commands.
public struct ZPLControlEncoder: Sendable {
    public let maxOutputBytes: Int

    public init(maxOutputBytes: Int = 1_024) throws {
        guard maxOutputBytes > 0 else { throw ZPLControlEncodingError.outputLimit }
        self.maxOutputBytes = maxOutputBytes
    }

    public func encode(_ controls: ResolvedPrinterControls) throws -> Data {
        switch controls.thermalMethod {
        case .leaveUnchanged, .value(.directThermal): break
        case .value(.thermalTransfer): throw ZPLControlEncodingError.unsupportedThermalMethod
        }
        switch controls.finishing {
        case .leaveUnchanged: break
        case .value(.tearOff):
            // The explicitly selected setup mode. It is a printer-mode command,
            // not a cutter or peel command.
            break
        case .value: throw ZPLControlEncodingError.unsupportedFinishing
        }
        guard controls.darkness == .leaveUnchanged else { throw ZPLControlEncodingError.unqualifiedDarkness }
        guard controls.tracking == .leaveUnchanged else { throw ZPLControlEncodingError.unqualifiedTracking }
        // This encoder implements only the documented GC420d subset. A caller's
        // capability declaration cannot widen the documented command subset.
        if case let .value(speed) = controls.printSpeedIps, ![2, 3, 4].contains(speed) {
            throw ZPLControlEncodingError.unsupportedPrintSpeed(speed)
        }

        var output = Data()
        if controls.finishing == .value(.tearOff) { output.append(contentsOf: "^MMT\n".utf8) }
        if case let .value(speed) = controls.printSpeedIps {
            output.append(contentsOf: "^PR\(speed)\n".utf8)
        }
        guard output.count <= maxOutputBytes else { throw ZPLControlEncodingError.outputLimit }
        return output
    }
}
