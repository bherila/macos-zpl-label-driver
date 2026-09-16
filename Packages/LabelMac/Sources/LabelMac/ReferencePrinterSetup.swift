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
    public enum Error: Swift.Error, Equatable, Sendable {
        case unsupportedSpeed(Int)
    }

    public let profile: PrinterProfile
    @Published public var stockLoadedConfirmed = false
    @Published public var tearOffConfirmed = false
    @Published public private(set) var selectedSpeedIps: Int?

    private init(profile: PrinterProfile) {
        self.profile = profile
    }

    public static func gc420dUSB() throws -> ReferencePrinterSetupModel {
        ReferencePrinterSetupModel(profile: try .gc420dUSBReference())
    }

    public var speedChoices: [Int] { profile.capabilities.printSpeedChoicesIps.sorted() }
    public var canEditOfflineWorkflows: Bool { stockLoadedConfirmed && tearOffConfirmed }

    /// A reported transport is not a discovered device. Installation remains
    /// unavailable until a later bounded discovery flow supplies an identity.
    public var canInstallQueue: Bool {
        guard canEditOfflineWorkflows else { return false }
        if case .observed = profile.connection.stableIdentity { return true }
        return false
    }

    public func selectSpeed(_ speed: Int?) throws {
        if let speed, !profile.capabilities.printSpeedChoicesIps.contains(speed) {
            throw Error.unsupportedSpeed(speed)
        }
        selectedSpeedIps = speed
    }

    public func workflowDefaults() throws -> PrinterControlRequest {
        let request = PrinterControlRequest(
            thermalMethod: .directThermal,
            finishing: .tearOff,
            printSpeedIps: selectedSpeedIps
        )
        try profile.validate(request)
        return request
    }

    public var facts: [PrinterSetupFact] {
        [
            .init(id: "model", label: "Model", value: profile.capabilities.model, status: .configured),
            .init(id: "transport", label: "Transport", value: "USB — device not discovered", status: .unknown),
            .init(id: "stock", label: "Stock", value: "4 × 6 in pre-cut direct thermal", status: .configured),
            .init(id: "finishing", label: "Finishing", value: "Tear-off", status: .configured),
            .init(id: "cutter", label: "Cutter", value: "Unavailable on selected setup", status: .unavailable),
            .init(id: "peeler", label: "Peeler", value: "Not qualified", status: .unknown),
            .init(id: "darkness", label: "Darkness", value: "Not qualified; leave unchanged", status: .unknown),
            .init(id: "tracking", label: "Media tracking", value: "Not observed; leave unchanged", status: .unknown),
        ]
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
                Picker("Draft print speed for this setup session", selection: Binding(
                    get: { model.selectedSpeedIps },
                    set: { try? model.selectSpeed($0) }
                )) {
                    Text("Leave printer setting unchanged").tag(Int?.none)
                    ForEach(model.speedChoices, id: \.self) { speed in
                        Text("\(speed) inches per second").tag(Int?.some(speed))
                    }
                }
                .accessibilityHint("Only documented speed choices are available")
                Text("A later queue-management step will save the selected default. No printer setting is changed here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("I loaded 4 × 6 inch pre-cut direct-thermal labels", isOn: $model.stockLoadedConfirmed)
                Toggle("This printer is in tear-off mode with no cutter", isOn: $model.tearOffConfirmed)

                Label(
                    model.canInstallQueue
                        ? "Ready for queue installation"
                        : "Queue installation remains unavailable until this Mac positively identifies the USB device",
                    systemImage: model.canInstallQueue ? "checkmark.circle" : "exclamationmark.triangle"
                )
                .accessibilityLabel(
                    model.canInstallQueue
                        ? "Queue installation ready"
                        : "Queue installation unavailable. USB device identity has not been discovered."
                )
            }
            .padding(4)
        }
    }

    private func symbol(for status: PrinterSetupFact.Status) -> String {
        switch status {
        case .configured: "checkmark.circle"
        case .unavailable: "nosign"
        case .unknown: "questionmark.circle"
        }
    }
}
