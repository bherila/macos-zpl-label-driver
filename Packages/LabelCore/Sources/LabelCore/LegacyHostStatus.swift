import Foundation

/// Bounded legacy ~HS observations (R44), never a job-specific print receipt.
public struct LegacyHostStatusFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let paperOut = Self(rawValue: 1 << 0)
    public static let paused = Self(rawValue: 1 << 1)
    public static let bufferFull = Self(rawValue: 1 << 2)
    public static let diagnosticMode = Self(rawValue: 1 << 3)
    public static let partialFormat = Self(rawValue: 1 << 4)
    public static let configurationRAMLost = Self(rawValue: 1 << 5)
    public static let underTemperature = Self(rawValue: 1 << 6)
    public static let overTemperature = Self(rawValue: 1 << 7)
    public static let headOpen = Self(rawValue: 1 << 8)
    public static let ribbonOut = Self(rawValue: 1 << 9)
    public static let thermalTransferSelected = Self(rawValue: 1 << 10)
    public static let peelLabelWaiting = Self(rawValue: 1 << 11)
}

/// Only typed observations survive decoding; opaque third-string data is dropped.
/// No readiness/completion inference, configuration change or raw frame retention.
public struct LegacyHostStatusSnapshot: Equatable, Sendable, RedactedDiagnosticValue {
    public let flags: LegacyHostStatusFlags
    public let labelLengthDots: Int
    public let formatsBuffered: Int
    public let labelsRemainingInBatch: Int
    public let graphicsStored: Int
    /// The documented single-byte mode code, not an authorized finishing setting.
    public let reportedPrintMode: UInt8
    public let staticRAMReportedPresent: Bool
}

public enum LegacyHostStatusUnavailable: Equatable, Sendable {
    case unverifiedSupport
    case unsupported
    case missingResponse
}

public enum LegacyHostStatusObservation: Equatable, Sendable {
    case unavailable(LegacyHostStatusUnavailable)
    case observed(LegacyHostStatusSnapshot)
}

/// Pure offline decoder. The production caller must separately establish unit,
/// channel, session/freshness and coordination evidence; this emits no query.
public enum LegacyHostStatusDecoder {
    public enum Error: Swift.Error, Equatable, Sendable {
        case responseTooLarge
        case malformedResponse
    }
    public static let maximumResponseBytes = 64 * 1024

    public static func decode(_ response: Data?, support: CapabilityState = .unknown) throws
        -> LegacyHostStatusObservation {
        switch support {
        case .unknown: return .unavailable(.unverifiedSupport)
        case .unsupported: return .unavailable(.unsupported)
        case .supported: break
        }
        guard let response, !response.isEmpty else { return .unavailable(.missingResponse) }
        guard response.count <= maximumResponseBytes else { throw Error.responseTooLarge }
        // Exact documented fixed-width subset; variants fail rather than guessed.
        guard response.count == 82 else { throw Error.malformedResponse }
        let bytes = Array(response)
        var cursor = 0
        var records: [[ArraySlice<UInt8>]] = []
        for widths in [[3,1,1,4,3,1,1,1,3,1,1,1], [3,1,1,1,1,1,1,1,8,1,3], [4,1]] {
            guard bytes[cursor] == 2 else { throw Error.malformedResponse }
            cursor += 1
            var fields: [ArraySlice<UInt8>] = []
            for (index, width) in widths.enumerated() {
                fields.append(bytes[cursor..<(cursor + width)])
                cursor += width
                if index < widths.count - 1 {
                    guard bytes[cursor] == 44 else { throw Error.malformedResponse }
                    cursor += 1
                }
            }
            guard bytes[cursor..<(cursor + 3)].elementsEqual([3,13,10]) else {
                throw Error.malformedResponse
            }
            cursor += 3
            records.append(fields)
        }
        guard cursor == bytes.count else { throw Error.malformedResponse }
        func decimal(_ field: ArraySlice<UInt8>) throws -> Int {
            var result = 0
            for byte in field {
                guard (48...57).contains(byte) else { throw Error.malformedResponse }
                result = result * 10 + Int(byte - 48) // At most eight digits.
            }
            return result
        }
        var numbers: [[Int]] = []
        for (row, fields) in records.enumerated() {
            var values: [Int] = []
            for (column, field) in fields.enumerated() {
                if row == 1, column == 5 {
                    let mode = field.first!
                    guard (48...57).contains(mode) || [65,75,83].contains(mode) else {
                        throw Error.malformedResponse
                    }
                    values.append(Int(mode))
                } else if row == 2, column == 0 {
                    guard field.allSatisfy({ (32...126).contains($0) && $0 != 44 }) else {
                        throw Error.malformedResponse
                    }
                    values.append(0) // Validate shape and discard opaque data.
                } else { values.append(try decimal(field)) }
            }
            numbers.append(values)
        }
        // R44 defines function settings as an eight-bit value. Discarding
        // this field must not admit a reply outside the documented grammar.
        guard numbers[1][0] <= 255,
              numbers[0][8] == 0, numbers[1][9] == 1 else { throw Error.malformedResponse }
        var flags: LegacyHostStatusFlags = []
        let mappings: [(Int,Int,LegacyHostStatusFlags)] = [
            (0,1,.paperOut),(0,2,.paused),(0,5,.bufferFull),(0,6,.diagnosticMode),
            (0,7,.partialFormat),(0,9,.configurationRAMLost),(0,10,.underTemperature),
            (0,11,.overTemperature),(1,2,.headOpen),(1,3,.ribbonOut),
            (1,4,.thermalTransferSelected),(1,7,.peelLabelWaiting)]
        for (row, column, flag) in mappings {
            let value = numbers[row][column]
            guard value == 0 || value == 1 else { throw Error.malformedResponse }
            if value == 1 { flags.insert(flag) }
        }
        guard numbers[2][1] <= 1 else { throw Error.malformedResponse }
        return .observed(LegacyHostStatusSnapshot(flags: flags,
            labelLengthDots: numbers[0][3], formatsBuffered: numbers[0][4],
            labelsRemainingInBatch: numbers[1][8], graphicsStored: numbers[1][10],
            reportedPrintMode: UInt8(numbers[1][5]), staticRAMReportedPresent: numbers[2][1] == 1))
    }
}
