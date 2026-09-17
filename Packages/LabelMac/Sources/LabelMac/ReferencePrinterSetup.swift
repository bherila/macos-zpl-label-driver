import Combine
import LabelCore
import SwiftUI

public struct PrinterSetupFact: Equatable, Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        case configured
        case unavailable
        case unknown
    }

    public let id: String
    public let label: String
    public let value: String
    public let status: Status

    public init(id: String, label: String, value: String, status: Status) {
        self.id = id
        self.label = label
        self.value = value
        self.status = status
    }
}

@MainActor
public final class ReferencePrinterSetupModel: ObservableObject {
    public enum OffsetField: String, CaseIterable, Sendable { case blackMark, shiftLeft, labelTop }
    public enum GeometryField: String, CaseIterable, Sendable { case width, length, homeX, homeY }
    public enum MotorSpeedKind: Equatable, Sendable { case print, feed, backfeed }
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidOffsetText(OffsetField)
        case invalidGeometryText(GeometryField)
        case unavailableTracking(MediaTracking)
        case unavailableDarkness
        case unsupportedDarkness(Int)
        case unsupportedSpeed(Int)
        case unavailableMotorSpeed(MotorSpeedKind, CapabilityState)
        case unsupportedMotorSpeed(MotorSpeedKind, Int)
    }

    @Published public var offsetDraft: [OffsetField: String] = [:]
    @Published public var geometryDraft: [GeometryField: String] = [:]
    @Published public private(set) var selectedTracking: MediaTracking?
    public let profile: PrinterProfile
    @Published public var stockLoadedConfirmed = false
    @Published public var tearOffConfirmed = false
    @Published public private(set) var selectedDarkness: Int?
    @Published public private(set) var selectedSpeedIps: Int?
    @Published public private(set) var selectedFeedSpeedIps: Int?
    @Published public private(set) var selectedBackfeedSpeedIps: Int?

    init(profile: PrinterProfile) {
        self.profile = profile
        selectedTracking = profile.configuredDefaults.tracking
        selectedDarkness = profile.configuredDefaults.darkness
        selectedSpeedIps = profile.configuredDefaults.printSpeedIps
        selectedFeedSpeedIps = profile.configuredDefaults.feedSpeedIps
        selectedBackfeedSpeedIps = profile.configuredDefaults.backfeedSpeedIps
    }

    public static func gc420dUSB() throws -> ReferencePrinterSetupModel {
        ReferencePrinterSetupModel(profile: try .gc420dUSBReference())
    }

    public var trackingChoices: [MediaTracking] {
        guard profile.schemaVersion >= 5 else { return [] }
        var modes: [MediaTracking] = [.gap, .continuous]
        if profile.schemaVersion >= 6, profile.capabilities.offsets.blackMark.fact.state == .supported,
           profile.capabilities.offsets.blackMark.fact.evidence != .unobserved { modes.append(.blackMark) }
        return modes.filter {
            guard let fact = profile.capabilities.tracking[$0] else { return false }
            return fact.state == .supported && fact.evidence != .unobserved
        }
    }

    public func selectTracking(_ value: MediaTracking?) throws {
        if let value, !trackingChoices.contains(value) { throw Error.unavailableTracking(value) }
        selectedTracking = value
    }

    public func geometryRange(for field: GeometryField) -> ClosedRange<Int>? {
        guard profile.schemaVersion >= 5 else { return nil }
        let p = profile.capabilities.physicalGeometry
        let limit: QualifiedDotLimit
        let minimum: Int
        switch field {
        case .width: limit = p.width; minimum = 2
        case .length: limit = p.continuousLength; minimum = 1
        case .homeX: limit = p.homeX; minimum = 0
        case .homeY: limit = p.homeY; minimum = 0
        }
        guard limit.fact.state == .supported, limit.fact.evidence != .unobserved,
              let maximum = limit.maximumDots else { return nil }
        return minimum...maximum
    }

    public func geometryDefaultLabel(for field: GeometryField) -> String {
        let g = profile.configuredDefaults.mediaGeometry
        let value: Int?
        switch field {
        case .width: value = g?.widthDots
        case .length: value = g?.lengthDots
        case .homeX: value = g?.originXDot
        case .homeY: value = g?.originYDot
        }
        if let value { return "Configured default: \(value) dots" }
        return "No configured default"
    }

    private func geometryRequest() throws -> MediaGeometryRequest? {
        func value(_ field: GeometryField) throws -> Int? {
            let text = geometryDraft[field, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return nil }
            // Preserve invalid input as a draft; never turn parsing failure into inheritance.
            guard let value = Int(text), let range = geometryRange(for: field), range.contains(value) else {
                throw Error.invalidGeometryText(field)
            }
            return value
        }
        let width = try value(.width), length = try value(.length)
        let x = try value(.homeX), y = try value(.homeY)
        guard width != nil || length != nil || x != nil || y != nil else { return nil }
        return try .init(widthDots: width, lengthDots: length, originXDot: x, originYDot: y)
    }

    private func offsetLimit(for field: OffsetField) -> QualifiedDotRange {
        let p = profile.capabilities.offsets
        return switch field {
        case .blackMark: p.blackMark
        case .shiftLeft: p.shiftLeft
        case .labelTop: p.labelTop
        }
    }

    public func offsetRange(for field: OffsetField) -> ClosedRange<Int>? {
        let limit = offsetLimit(for: field)
        guard profile.schemaVersion >= 6, limit.fact.state == .supported,
              limit.fact.evidence != .unobserved else { return nil }
        return limit.range
    }

    public func offsetDefaultLabel(for field: OffsetField) -> String {
        let offsets = profile.configuredDefaults.offsets
        let value: Int?
        switch field {
        case .blackMark: value = offsets?.blackMarkOffsetDots
        case .shiftLeft: value = offsets?.shiftLeftDots
        case .labelTop: value = offsets?.labelTopDots
        }
        if let value { return "Configured default: \(value) dots" }
        return "No configured default"
    }

    private func offsetRequest() throws -> OffsetControlRequest? {
        func value(_ field: OffsetField) throws -> Int? {
            let text = offsetDraft[field, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return nil }
            guard let value = Int(text), let range = offsetRange(for: field), range.contains(value) else {
                throw Error.invalidOffsetText(field)
            }
            return value
        }
        let mark = try value(.blackMark), shift = try value(.shiftLeft), top = try value(.labelTop)
        guard mark != nil || shift != nil || top != nil else { return nil }
        return .init(blackMarkOffsetDots: mark, shiftLeftDots: shift, labelTopDots: top)
    }

    public var darknessChoices: [Int] {
        guard profile.schemaVersion >= 4, profile.capabilities.darkness.state == .supported,
              profile.capabilities.darkness.evidence != .unobserved else { return [] }
        return Array(0...30)
    }

    public var defaultDarknessChoiceLabel: String {
        if let value = profile.configuredDefaults.darkness {
            return "Use configured device default (\(value))"
        }
        return "Do not explicitly set darkness"
    }

    public func selectDarkness(_ value: Int?) throws {
        if let value {
            guard !darknessChoices.isEmpty else { throw Error.unavailableDarkness }
            guard darknessChoices.contains(value) else { throw Error.unsupportedDarkness(value) }
        }
        selectedDarkness = value
    }

    private var darknessFact: PrinterSetupFact {
        if !darknessChoices.isEmpty {
            return .init(id: "darkness", label: "Darkness",
                value: "Qualified profile range: 0–30; current setting unknown", status: .configured)
        }
        if profile.capabilities.darkness.state == .unsupported {
            return .init(id: "darkness", label: "Darkness", value: "Unavailable in this profile", status: .unavailable)
        }
        return .init(id: "darkness", label: "Darkness", value: "Not qualified; current setting unknown", status: .unknown)
    }

    public var speedChoices: [Int] { profile.capabilities.printSpeedChoicesIps.intersection([2, 3, 4]).sorted() }

    public func speedChoices(for kind: MotorSpeedKind) -> [Int] {
        switch kind {
        case .print: return speedChoices
        case .feed: return profile.capabilities.feedSpeeds.fact.state == .supported
            ? profile.capabilities.feedSpeeds.choicesIps.sorted() : []
        case .backfeed: return profile.capabilities.backfeedSpeeds.fact.state == .supported
            ? profile.capabilities.backfeedSpeeds.choicesIps.sorted() : []
        }
    }

    public func selectedSpeed(for kind: MotorSpeedKind) -> Int? {
        switch kind {
        case .print: selectedSpeedIps
        case .feed: selectedFeedSpeedIps
        case .backfeed: selectedBackfeedSpeedIps
        }
    }

    public func defaultChoiceLabel(for kind: MotorSpeedKind) -> String {
        let configured: Int?
        switch kind {
        case .print: configured = profile.configuredDefaults.printSpeedIps
        case .feed: configured = profile.configuredDefaults.feedSpeedIps
        case .backfeed: configured = profile.configuredDefaults.backfeedSpeedIps
        }
        if let configured { return "Use configured device default (\(configured) inches per second)" }
        return "Do not explicitly set this speed"
    }
    /// Editing/rendering a draft performs no device I/O and must not require
    /// asserting observations of hardware that may not be attached.
    public var canEditOfflineWorkflows: Bool { true }

    /// A reported transport is not a discovered device. Installation remains
    /// unavailable until a later bounded discovery flow supplies an identity.
    public var canInstallQueue: Bool {
        guard stockLoadedConfirmed && tearOffConfirmed,
              (try? workflowDefaults()) != nil else { return false }
        if case .observed = profile.connection.stableIdentity { return true }
        return false
    }

    public var installationReadinessMessage: String {
        if let validationMessage { return validationMessage }
        guard case .observed = profile.connection.stableIdentity else {
            return "Queue installation remains unavailable until this Mac positively identifies the USB device"
        }
        guard stockLoadedConfirmed && tearOffConfirmed else {
            return "Confirm the actual stock and tear-off configuration before queue installation"
        }
        return "Ready for queue installation"
    }

    public func selectSpeed(_ speed: Int?, kind: MotorSpeedKind = .print) throws {
        if let speed, !speedChoices(for: kind).contains(speed) {
            if kind == .print { throw Error.unsupportedSpeed(speed) }
            let fact = kind == .feed ? profile.capabilities.feedSpeeds.fact : profile.capabilities.backfeedSpeeds.fact
            if fact.state != .supported { throw Error.unavailableMotorSpeed(kind, fact.state) }
            throw Error.unsupportedMotorSpeed(kind, speed)
        }
        switch kind {
        case .print: selectedSpeedIps = speed
        case .feed: selectedFeedSpeedIps = speed
        case .backfeed: selectedBackfeedSpeedIps = speed
        }
    }

    public func workflowDefaults() throws -> PrinterControlRequest {
        let resolved = try profile.resolveControls(job: .init(
            thermalMethod: .directThermal, finishing: .tearOff,
            printSpeedIps: selectedSpeedIps, feedSpeedIps: selectedFeedSpeedIps,
            backfeedSpeedIps: selectedBackfeedSpeedIps, darkness: selectedDarkness,
            tracking: selectedTracking, mediaGeometry: geometryRequest(), offsets: offsetRequest()))
        // Validate against the actual current ordinary encoder as well as
        // supplied profile declarations; this is bounded memory work, no I/O.
        _ = try ZPLControlEncoder().encode(resolved)
        let printSpeed: Int?
        if case let .value(value) = resolved.printSpeedIps { printSpeed = value }
        else { printSpeed = nil }
        let darkness: Int?
        if case let .value(value) = resolved.darkness { darkness = value }
        else { darkness = nil }
        let tracking: MediaTracking?
        if case let .value(value) = resolved.tracking { tracking = value } else { tracking = nil }
        let geometry: MediaGeometryRequest?
        if case let .value(value) = resolved.mediaGeometry { geometry = value } else { geometry = nil }
        return .init(thermalMethod: .directThermal, finishing: .tearOff,
                     printSpeedIps: printSpeed, feedSpeedIps: resolved.feedSpeedIps.explicitValue,
                     backfeedSpeedIps: resolved.backfeedSpeedIps.explicitValue, darkness: darkness,
                     tracking: tracking, mediaGeometry: geometry,
                     offsets: { if case let .value(value) = resolved.offsets { return value }; return nil }())
    }

    public var validationMessage: String? {
        do { _ = try workflowDefaults(); return nil }
        catch PrinterProfileError.incompleteMotorSpeeds {
            return "Choose print, feed and backfeed speeds together, or use a complete configured default."
        } catch OffsetControlQualification.Error.blackMarkOffsetRequired {
            return "Enter a qualified black-mark offset in dots, including zero when explicitly intended."
        } catch OffsetControlQualification.Error.blackMarkModeRequired {
            return "A configured black-mark offset requires black-mark tracking."
        } catch Error.invalidOffsetText {
            return "Enter signed whole dots within the qualified offset range, or leave the field blank to use its configured default."
        } catch Error.invalidGeometryText {
            return "Enter whole dots within the qualified range, or leave the field blank to use its configured default."
        } catch PhysicalGeometryQualification.Error.incompleteHome {
            return "Choose both label-home coordinates, or use a complete configured default."
        } catch PhysicalGeometryQualification.Error.continuousLengthRequired {
            return "Continuous tracking requires a qualified label length in dots."
        } catch PhysicalGeometryQualification.Error.continuousModeRequired {
            return "A label length requires continuous tracking. An inherited length is still effective."
        } catch {
            return "The selected control combination is unavailable in this profile."
        }
    }

    private func motorFact(id: String, label: String, capability: QualifiedSpeedChoices) -> PrinterSetupFact {
        switch capability.fact.state {
        case .unknown: return .init(id: id, label: label, value: "Not qualified; current setting unknown", status: .unknown)
        case .unsupported: return .init(id: id, label: label, value: "Unavailable in this profile", status: .unavailable)
        case .supported:
            let choices = capability.choicesIps.sorted().map(String.init).joined(separator: ", ")
            return .init(id: id, label: label, value: "Qualified profile choices: \(choices) inches per second", status: .configured)
        }
    }

    private var trackingFact: PrinterSetupFact {
        if let value = profile.configuredDefaults.tracking {
            return .init(id: "tracking", label: "Media tracking",
                value: "Configured profile default: \(value.rawValue); current setting unknown", status: .configured)
        }
        return .init(id: "tracking", label: "Media tracking",
            value: "No configured default; current setting unknown", status: .unknown)
    }

    private var geometryFacts: [PrinterSetupFact] {
        GeometryField.allCases.map { field in
            let label: String
            let fact: CapabilityFact
            let p = profile.capabilities.physicalGeometry
            switch field {
            case .width: label = "Print width"; fact = p.width.fact
            case .length: label = "Continuous label length"; fact = p.continuousLength.fact
            case .homeX: label = "Label home X"; fact = p.homeX.fact
            case .homeY: label = "Label home Y"; fact = p.homeY.fact
            }
            if let range = geometryRange(for: field) {
                return .init(id: "geometry-\(field.rawValue)", label: label,
                    value: "Qualified range: \(range.lowerBound)–\(range.upperBound) dots; current setting unknown", status: .configured)
            }
            return .init(id: "geometry-\(field.rawValue)", label: label,
                value: fact.state == .unsupported ? "Unavailable in this profile" : "Not qualified; current setting unknown",
                status: fact.state == .unsupported ? .unavailable : .unknown)
        }
    }

    private var offsetFacts: [PrinterSetupFact] {
        OffsetField.allCases.map { field in
            let label: String
            switch field {
            case .blackMark: label = "Black-mark offset"
            case .shiftLeft: label = "Horizontal label shift"
            case .labelTop: label = "Label top offset"
            }
            if let range = offsetRange(for: field) {
                return .init(id: "offset-\(field.rawValue)", label: label,
                    value: "Qualified range: \(range.lowerBound)–\(range.upperBound) dots; current setting unknown", status: .configured)
            }
            let fact = offsetLimit(for: field).fact
            return .init(id: "offset-\(field.rawValue)", label: label,
                value: fact.state == .unsupported ? "Unavailable in this profile" : "Not qualified; current setting unknown",
                status: fact.state == .unsupported ? .unavailable : .unknown)
        }
    }

    public var facts: [PrinterSetupFact] {
        [
            .init(id: "model", label: "Model", value: profile.capabilities.model, status: .configured),
            .init(id: "transport", label: "Transport", value: "USB — device not discovered", status: .unknown),
            .init(id: "stock", label: "Stock", value: "4 × 6 in pre-cut direct thermal", status: .configured),
            .init(id: "finishing", label: "Finishing", value: "Tear-off", status: .configured),
            .init(id: "cutter", label: "Cutter", value: "Unavailable on selected setup", status: .unavailable),
            .init(id: "peeler", label: "Peeler", value: "Not qualified", status: .unknown),
            motorFact(id: "feedSpeed", label: "Feed speed", capability: profile.capabilities.feedSpeeds),
            motorFact(id: "backfeedSpeed", label: "Backfeed speed", capability: profile.capabilities.backfeedSpeeds),
            darknessFact,
            trackingFact,
        ] + geometryFacts + offsetFacts
    }
}

public struct ReferencePrinterSetupView: View {
    @ObservedObject private var model: ReferencePrinterSetupModel

    public init(model: ReferencePrinterSetupModel) {
        self.model = model
    }

    public var body: some View {
        GroupBox("Reference printer setup") {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(model.facts) { fact in
                        GridRow {
                            Text(fact.label).fontWeight(.semibold)
                            Label(fact.value, systemImage: symbol(for: fact.status))
                                .accessibilityLabel("\(fact.label): \(fact.value)")
                        }
                    }
                }
                speedPicker(.print, label: "Draft print speed for this setup session")
                if !model.speedChoices(for: .feed).isEmpty {
                    speedPicker(.feed, label: "Draft feed speed for this setup session")
                }
                if !model.speedChoices(for: .backfeed).isEmpty {
                    speedPicker(.backfeed, label: "Draft backfeed speed for this setup session")
                }
                if !model.darknessChoices.isEmpty {
                    Picker("Draft absolute darkness for this setup session", selection: Binding(
                        get: { model.selectedDarkness }, set: { try? model.selectDarkness($0) }
                    )) {
                        Text(model.defaultDarknessChoiceLabel).tag(Int?.none)
                        ForEach(model.darknessChoices, id: \.self) { value in
                            Text("\(value)").tag(Int?.some(value))
                        }
                    }
                    .accessibilityHint("Only qualified values are available. This edits a draft without changing the printer.")
                    Text("An explicit darkness value replaces the printer’s relative adjustment when printing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !model.trackingChoices.isEmpty {
                    Picker("Draft media tracking", selection: Binding(
                        get: { model.selectedTracking }, set: { try? model.selectTracking($0) }
                    )) {
                        Text("Use configured tracking default").tag(MediaTracking?.none)
                        ForEach(model.trackingChoices, id: \.self) { tracking in
                            Text(tracking == .gap ? "Gap / web sensing" : tracking == .continuous ? "Continuous" : "Black mark").tag(MediaTracking?.some(tracking))
                        }
                    }
                    .accessibilityHint("This chooses a draft control. The printer’s current tracking setting is unknown.")
                    Text("Black-mark tracking requires its qualified offset. A blank offset inherits its configured default; it does not reset the printer.").font(.caption)
                }
                ForEach(ReferencePrinterSetupModel.GeometryField.allCases, id: \.self) { field in
                    if let range = model.geometryRange(for: field) {
                        VStack(alignment: .leading, spacing: 3) {
                            TextField(geometryLabel(field), text: Binding(
                                get: { model.geometryDraft[field, default: ""] },
                                set: { model.geometryDraft[field] = $0 }
                            ), prompt: Text(model.geometryDefaultLabel(for: field)))
                            .accessibilityHint("Whole dots from \(range.lowerBound) through \(range.upperBound). Blank uses the configured default. No printer setting is changed.")
                            Text("\(range.lowerBound)–\(range.upperBound) dots. Blank: \(model.geometryDefaultLabel(for: field)).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(ReferencePrinterSetupModel.OffsetField.allCases, id: \.self) { field in
                    if let range = model.offsetRange(for: field) {
                        VStack(alignment: .leading, spacing: 3) {
                            TextField(offsetLabel(field), text: Binding(
                                get: { model.offsetDraft[field, default: ""] },
                                set: { model.offsetDraft[field] = $0 }
                            ), prompt: Text(model.offsetDefaultLabel(for: field)))
                            .accessibilityHint("Signed whole dots from \(range.lowerBound) through \(range.upperBound). Blank uses the configured default. No printer setting is changed.")
                            Text("\(range.lowerBound)–\(range.upperBound) dots. Blank: \(model.offsetDefaultLabel(for: field)).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if model.profile.schemaVersion >= 5 {
                    Text("Physical geometry is separate from source-page crop and loaded stock. Current device geometry remains unknown.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let message = model.validationMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .accessibilityLabel(message)
                }
                Text("These choices edit utility drafts. Saving a revision does not change the printer’s current settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("I loaded 4 × 6 inch pre-cut direct-thermal labels", isOn: $model.stockLoadedConfirmed)
                Toggle("This printer is in tear-off mode with no cutter", isOn: $model.tearOffConfirmed)

                Text("Offline workflow editing is available without a printer. These confirmations apply to installation/printing readiness; do not check them unless you have verified the actual printer and stock.")
                    .font(.caption)
                    .accessibilityLabel("Offline editing does not require hardware confirmation. Installation and printing readiness still do.")

                Label(model.installationReadinessMessage,
                      systemImage: model.canInstallQueue ? "checkmark.circle" : "exclamationmark.triangle")
                    .accessibilityLabel(model.installationReadinessMessage)
            }
            .padding(4)
        }
    }

    private func offsetLabel(_ field: ReferencePrinterSetupModel.OffsetField) -> String {
        switch field {
        case .blackMark: "Draft black-mark offset (dots)"
        case .shiftLeft: "Draft horizontal label shift (dots)"
        case .labelTop: "Draft label top offset (dots)"
        }
    }

    private func geometryLabel(_ field: ReferencePrinterSetupModel.GeometryField) -> String {
        switch field {
        case .width: "Draft print width (dots)"
        case .length: "Draft continuous label length (dots)"
        case .homeX: "Draft label home X (dots)"
        case .homeY: "Draft label home Y (dots)"
        }
    }

    private func speedPicker(_ kind: ReferencePrinterSetupModel.MotorSpeedKind, label: String) -> some View {
        Picker(label, selection: Binding(
            get: { model.selectedSpeed(for: kind) },
            set: { try? model.selectSpeed($0, kind: kind) }
        )) {
            Text(model.defaultChoiceLabel(for: kind)).tag(Int?.none)
            ForEach(model.speedChoices(for: kind), id: \.self) { speed in
                Text("\(speed) inches per second").tag(Int?.some(speed))
            }
        }
        .accessibilityHint("Only choices qualified in this profile are available. This edits a draft without changing the printer.")
    }

    private func symbol(for status: PrinterSetupFact.Status) -> String {
        switch status {
        case .configured: "checkmark.circle"
        case .unavailable: "nosign"
        case .unknown: "questionmark.circle"
        }
    }
}
