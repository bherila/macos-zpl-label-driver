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

    public static let qualifiedMotorSpeedTuple: ZPLControlProtocol = .init(
        option: "printSpeedIps/feedSpeedIps/backfeedSpeedIps", command: "^PRp,s,b", sourceID: "R45",
        lifetime: .applicationUntilReissuedOrPowerOff,
        notes: "All three values explicit; feed/backfeed need separate profile qualification. Reference remains unknown.")

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
    case incompleteMotorSpeeds
    case unqualifiedMotorSpeeds
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

        var motorBytes: Data?
        if controls.feedSpeedIps != .notExplicitlyControlled || controls.backfeedSpeedIps != .notExplicitlyControlled {
            guard controls.profileSchemaVersion == 3 else { throw ZPLControlEncodingError.unqualifiedMotorSpeeds }
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
        if controls.finishing == .value(.tearOff) { output.append(contentsOf: "^MMT\n".utf8) }
        if let motorBytes { output.append(motorBytes) }
        else if case let .value(speed) = controls.printSpeedIps {
            output.append(contentsOf: "^PR\(speed)\n".utf8)
        }
        guard output.count <= maxOutputBytes else { throw ZPLControlEncodingError.outputLimit }
        return output
    }
}
