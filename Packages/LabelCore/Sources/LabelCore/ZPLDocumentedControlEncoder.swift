import Foundation

/// Offline protocol representation, not an installed-unit capability profile.
/// Every associated value is explicit: omitted speed parameters must not select
/// Zebra's defaults, and mark offset is not a label home/shift/top adjustment.
public enum ZPLDocumentedControl: Equatable, Sendable {
    case printRate(printIps: Int, feedIps: Int, backfeedIps: Int)
    case absoluteDarkness(Int)
    case thermalMethod(ThermalMethod)
    case gapTracking
    case continuousTracking(labelLengthDots: Int)
    case blackMarkTracking(offsetDots: Int)
    case labelHome(xDots: Int, yDots: Int)
    case labelShiftLeft(dots: Int)
    case labelTop(dots: Int)
    case printWidth(dots: Int)
    case tearOff

    public enum Kind: String, CaseIterable, Hashable, Sendable {
        case printRate, absoluteDarkness, directThermal, thermalTransfer
        case gapTracking, blackMarkTracking, continuousTracking, labelHome, labelShiftLeft
        case labelTop, printWidth, tearOff
    }

    public var kind: Kind {
        switch self {
        case .printRate: return .printRate
        case .absoluteDarkness: return .absoluteDarkness
        case .thermalMethod(.directThermal): return .directThermal
        case .thermalMethod(.thermalTransfer): return .thermalTransfer
        case .gapTracking: return .gapTracking
        case .continuousTracking: return .continuousTracking
        case .blackMarkTracking: return .blackMarkTracking
        case .labelHome: return .labelHome
        case .labelShiftLeft: return .labelShiftLeft
        case .labelTop: return .labelTop
        case .printWidth: return .printWidth
        case .tearOff: return .tearOff
        }
    }
}

/// Explicit supplied model bounds intersect the conservative public protocol
/// subset below. These declarations do not discover, authenticate or qualify a
/// physical printer. Nil bounds remain unavailable, never zero or unlimited.
public struct ZPLDocumentedControlLimits: Equatable, Sendable {
    public let printSpeedChoicesIps: Set<Int>
    public let feedSpeedChoicesIps: Set<Int>
    public let backfeedSpeedChoicesIps: Set<Int>
    public let blackMarkOffsetDots: ClosedRange<Int>?
    public let maximumContinuousLabelLengthDots: Int?
    public let maximumPrintWidthDots: Int?
    public let labelTopDots: ClosedRange<Int>?

    public init(
        printSpeedChoicesIps: Set<Int> = [], feedSpeedChoicesIps: Set<Int> = [],
        backfeedSpeedChoicesIps: Set<Int> = [],
        blackMarkOffsetDots: ClosedRange<Int>? = nil,
        maximumPrintWidthDots: Int? = nil, labelTopDots: ClosedRange<Int>? = nil,
        maximumContinuousLabelLengthDots: Int? = nil
    ) {
        self.printSpeedChoicesIps = printSpeedChoicesIps
        self.feedSpeedChoicesIps = feedSpeedChoicesIps
        self.backfeedSpeedChoicesIps = backfeedSpeedChoicesIps
        self.blackMarkOffsetDots = blackMarkOffsetDots
        self.maximumContinuousLabelLengthDots = maximumContinuousLabelLengthDots
        self.maximumPrintWidthDots = maximumPrintWidthDots
        self.labelTopDots = labelTopDots
    }
}

/// Produces a bounded command fragment for offline inspection. It supplies no
/// format envelope, graphics, copies, transport, save, calibration or mechanical
/// accessory commands. It is deliberately separate from ordinary-job admission.
/// Provenance: R45, public Zebra P1134473-11EN Rev A command tables.
public struct ZPLDocumentedControlEncoder: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidOutputLimit
        case tooManyControls
        case duplicateControl
        case conflictingThermalMethods
        case conflictingTracking
        case unavailable(ZPLDocumentedControl.Kind)
        case invalidValue(ZPLDocumentedControl.Kind)
        case outputLimit
    }

    public let maximumOutputBytes: Int

    public init(maximumOutputBytes: Int = 1_024) throws {
        guard (1...64 * 1_024).contains(maximumOutputBytes) else {
            throw Error.invalidOutputLimit
        }
        self.maximumOutputBytes = maximumOutputBytes
    }

    public func encode(
        _ controls: [ZPLDocumentedControl],
        qualification: [ZPLDocumentedControl.Kind: CapabilityState] = [:],
        limits: ZPLDocumentedControlLimits = .init()
    ) throws -> Data {
        guard controls.count <= ZPLDocumentedControl.Kind.allCases.count else {
            throw Error.tooManyControls
        }
        var kinds = Set<ZPLDocumentedControl.Kind>()
        for control in controls {
            guard kinds.insert(control.kind).inserted else { throw Error.duplicateControl }
            guard qualification[control.kind] == .supported else {
                throw Error.unavailable(control.kind)
            }
        }
        guard !kinds.isSuperset(of: [.directThermal, .thermalTransfer]) else {
            throw Error.conflictingThermalMethods
        }
        guard kinds.intersection([.gapTracking, .blackMarkTracking, .continuousTracking]).count <= 1 else {
            throw Error.conflictingTracking
        }
        var output = Data()
        for control in controls {
            let command: String
            switch control {
            case let .printRate(printIps, feedIps, backfeedIps):
                // 1 and 13/14 ips are special-model values outside this subset.
                guard (2...12).contains(printIps), (2...12).contains(feedIps),
                      (2...12).contains(backfeedIps),
                      limits.printSpeedChoicesIps.contains(printIps),
                      limits.feedSpeedChoicesIps.contains(feedIps),
                      limits.backfeedSpeedChoicesIps.contains(backfeedIps) else {
                    throw Error.invalidValue(control.kind)
                }
                command = "^PR\(printIps),\(feedIps),\(backfeedIps)\n"
            case let .absoluteDarkness(value):
                guard (0...30).contains(value) else { throw Error.invalidValue(control.kind) }
                // Relative ^MD is additive to ~SD. Neutralize it explicitly.
                command = "^MD0\n~SD\(value < 10 ? "0" : "")\(value)\n"
            case .thermalMethod(.directThermal): command = "^MTD\n"
            case .thermalMethod(.thermalTransfer): command = "^MTT\n"
            case .gapTracking: command = "^MNY\n"
            case let .continuousTracking(length):
                guard (1...32_000).contains(length),
                      let maximum = limits.maximumContinuousLabelLengthDots,
                      (1...32_000).contains(maximum), length <= maximum else {
                    throw Error.invalidValue(control.kind)
                }
                // R46: fix continuous mode before length. The optional modern
                // ^LL media-scope flag can be Y or N without changing this
                // explicitly continuous format. Do not guess its delimiter or
                // claim that a later gap/mark format has been normalized.
                command = "^MNN\n^LL\(length)\n"
            case let .blackMarkTracking(offset):
                // Conservative intersection valid across the documented model
                // categories; wider model-specific offsets are not implemented.
                guard (-75...283).contains(offset),
                      limits.blackMarkOffsetDots?.contains(offset) == true else {
                    throw Error.invalidValue(control.kind)
                }
                command = "^MNM,\(offset)\n"
            case let .labelHome(x, y):
                guard (0...32_000).contains(x), (0...32_000).contains(y) else {
                    throw Error.invalidValue(control.kind)
                }
                command = "^LH\(x),\(y)\n"
            case let .labelShiftLeft(value):
                guard (-9_999...9_999).contains(value) else { throw Error.invalidValue(control.kind) }
                command = "^LS\(value)\n"
            case let .labelTop(value):
                guard (-120...120).contains(value),
                      limits.labelTopDots?.contains(value) == true else {
                    throw Error.invalidValue(control.kind)
                }
                command = "^LT\(value)\n"
            case let .printWidth(value):
                // Same bounded geometry subset as ordinary profile admission.
                // ^PW is additionally bounded by the supplied label/model width;
                // an overbroad declaration must not authorize printer clamping.
                guard (2...32_000).contains(value), let maximum = limits.maximumPrintWidthDots,
                      (2...32_000).contains(maximum), value <= maximum else {
                    throw Error.invalidValue(control.kind)
                }
                command = "^PW\(value)\n"
            case .tearOff: command = "^MMT\n"
            }
            let bytes = Data(command.utf8)
            guard bytes.count <= maximumOutputBytes - output.count else { throw Error.outputLimit }
            output.append(bytes)
        }
        return output
    }
}
